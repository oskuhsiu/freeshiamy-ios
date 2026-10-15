#!/usr/bin/env bash
# One diagnostic iPad reproduction. The normal acceptance workflow is untouched.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
source ci/simulator-build-args.sh
OUT="${GITHUB_WORKSPACE:-$PWD}/ci-artifacts/ipad-activation-pid"
if [[ -e "$OUT" ]]; then echo "Refusing reused evidence directory: $OUT" >&2; exit 1; fi
mkdir -p "$OUT"
DEVICE_ID=''
OBSERVER_PID=''
cleanup() {
    local rc=$?
    if [[ -n "$OBSERVER_PID" ]]; then
        if kill -0 "$OBSERVER_PID" 2>/dev/null; then
            kill -TERM "$OBSERVER_PID" 2>/dev/null || true
        fi
        observer_wait_status=0
        wait "$OBSERVER_PID" > "$OUT/observer-exit.log" 2>&1 || observer_wait_status=$?
        printf 'observer_wait_status=%s\n' "$observer_wait_status" >> "$OUT/observer-lifecycle.log"
    fi
    if [[ -n "$DEVICE_ID" ]]; then
        local shutdown_status=0 delete_status=0
        xcrun simctl shutdown "$DEVICE_ID" > "$OUT/owned-device-shutdown.log" 2>&1 || shutdown_status=$?
        xcrun simctl delete "$DEVICE_ID" > "$OUT/owned-device-delete.log" 2>&1 || delete_status=$?
        printf 'shutdown_status=%s\ndelete_status=%s\n' "$shutdown_status" "$delete_status" > "$OUT/owned-device-cleanup-status.txt"
    fi
    printf 'script_exit=%s\n' "$rc" > "$OUT/status.txt"
}
trap cleanup EXIT

# Preserve actual command help and environment; reject missing capabilities.
{
    printf 'source_sha=%s\n' "$(git rev-parse HEAD)"
    printf 'source_tree=%s\n' "$(git rev-parse HEAD^{tree})"
    printf 'runner_image=%s %s\n' "${ImageOS:-unknown}" "${ImageVersion:-unknown}"
    sw_vers
    uname -m
    xcodebuild -version
    xcrun --sdk iphonesimulator --show-sdk-version
    xcrun simctl list runtimes
} > "$OUT/preflight.log" 2>&1
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 && "$(sw_vers -productVersion)" == 15.* ]]
[[ "$(xcodebuild -version | head -n1)" == 'Xcode 26.2' ]]
[[ "$(xcrun --sdk iphonesimulator --show-sdk-version)" == '26.2' ]]
xcodebuild -help > "$OUT/xcodebuild-help.log" 2>&1
xcrun simctl help spawn > "$OUT/simctl-spawn-help.log" 2>&1
xcrun simctl help get_app_container > "$OUT/simctl-get-app-container-help.log" 2>&1
xcrun simctl help ui > "$OUT/simctl-ui-help.log" 2>&1
log_stream_help_status=0
log help stream > "$OUT/log-stream-help.log" 2>&1 || log_stream_help_status=$?
sample_help_status=0
sample -h > "$OUT/sample-help.log" 2>&1 || sample_help_status=$?
log_show_help_status=0
log help show > "$OUT/log-show-help.log" 2>&1 || log_show_help_status=$?
printf 'log_stream_help_status=%s\nsample_help_status=%s\nlog_show_help_status=%s\n' \
    "$log_stream_help_status" "$sample_help_status" "$log_show_help_status" > "$OUT/help-status.txt"
for flag in '-only-testing:TEST-IDENTIFIER' '-testLanguage' '-testRegion' '-test-timeouts-enabled' '-maximum-test-execution-time-allowance' '-collect-test-diagnostics on-failure'; do
    grep -Fq -- "$flag" "$OUT/xcodebuild-help.log"
done
for flag in '--style' '--level' '--predicate'; do grep -Fq -- "$flag" "$OUT/log-stream-help.log"; done
grep -Fq -- '-file' "$OUT/sample-help.log"
for flag in '--start' '--end' '--timezone' '--style' '--info' '--debug'; do grep -Fq -- "$flag" "$OUT/log-show-help.log"; done
python3 ci/count-run21-log-events.py --self-test > "$OUT/compact-event-counter-selftest.log" 2>&1
xcrun simctl list -j devicetypes > "$OUT/device-types.json"
xcrun simctl list -j runtimes > "$OUT/runtimes.json"
python3 - "$OUT/device-types.json" "$OUT/runtimes.json" > "$OUT/device-selection.log" <<'PY'
import json, sys
types, runtimes = [json.load(open(p)) for p in sys.argv[1:]]
t = [d for d in types['devicetypes'] if d.get('identifier') == 'com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3' and d.get('productFamily') == 'iPad']
r = [d for d in runtimes['runtimes'] if d.get('identifier') == 'com.apple.CoreSimulator.SimRuntime.iOS-26-2' and d.get('isAvailable')]
if len(t) != 1 or len(r) != 1: raise SystemExit('Pinned iPad Air 11 M3 or iOS 26.2 unavailable')
print(t[0]['name'], t[0]['identifier'], r[0]['identifier'])
PY
# Build/verify both final Simulator Mach-O entitlements and ad-hoc signatures before boot.
# This is the repository's already-proven build-for-testing identity helper.
bash ci/verify-simulator-build-identity.sh > "$OUT/build-identity-run.log" 2>&1
PROOF="${GITHUB_WORKSPACE:-$PWD}/ci-artifacts/simulator-build-identity"
grep -qx 'result=0' "$PROOF/identity-result.txt"
DERIVED="${RUNNER_TEMP:-/tmp}/fsh-simulator-identity-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/freeshiamy-ios.app"

DEVICE_ID=$(xcrun simctl create "fsh-activation-pid-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}" \
    com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3 com.apple.CoreSimulator.SimRuntime.iOS-26-2)
printf 'owned_udid=%s\n' "$DEVICE_ID" > "$OUT/owned-device.txt"
xcrun simctl boot "$DEVICE_ID" > "$OUT/boot-command.log" 2>&1
python3 - "$DEVICE_ID" "$OUT/bootstatus.log" <<'PY_BOOT'
import subprocess, sys
with open(sys.argv[2], 'wb') as log:
    subprocess.run(['xcrun', 'simctl', 'bootstatus', sys.argv[1], '-b'],
                   stdout=log, stderr=subprocess.STDOUT, timeout=600, check=True)
PY_BOOT

# Each selected case remains an independent original xcodebuild test invocation.
run_case() {
    local label="$1" test="$2" result=0
    printf 'start_utc=%s\n' "$(date -u +'%Y-%m-%d %H:%M:%S')" > "$OUT/$label-bounds.txt"
    fsh_validate_simulator_destination "platform=iOS Simulator,id=$DEVICE_ID" || return 1
    set +e
    xcodebuild test -project freeshiamy-ios.xcodeproj -scheme InstalledKeyboardSmoke \
        -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE_ID" \
        -testLanguage en -testRegion US -parallel-testing-enabled NO \
        -test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
        -maximum-test-execution-time-allowance 360 -collect-test-diagnostics on-failure \
        -derivedDataPath "$DERIVED" -resultBundlePath "$OUT/$label.xcresult" \
        "-only-testing:InstalledKeyboardUITests/InstalledKeyboardUITests/$test" \
        "${FSH_CI_SIMULATOR_BUILD_ARGS[@]}" 2>&1 | tee "$OUT/$label-xcodebuild.log"
    local -a pipeline_status=("${PIPESTATUS[@]}")
    set -e
    printf 'end_utc_ceil=%s\nxcodebuild_status=%s\ntee_status=%s\n' \
        "$(python3 -c 'import datetime as d; n=d.datetime.now(d.timezone.utc); print((n+d.timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S"))')" \
        "${pipeline_status[0]}" "${pipeline_status[1]}" >> "$OUT/$label-bounds.txt"
    if [[ "${pipeline_status[0]}" != 0 || "${pipeline_status[1]}" != 0 ]]; then result=1; fi
    if [[ -d "$OUT/$label.xcresult" ]]; then
        xcrun xcresulttool export attachments --path "$OUT/$label.xcresult" \
            --output-path "$OUT/$label-attachments" > "$OUT/$label-attachments-export.log" 2>&1 || result=1
    else
        printf 'diagnostic_missing=xcresult\n' > "$OUT/$label-attachments-export.log"
        result=1
    fi
    xcrun simctl io "$DEVICE_ID" screenshot "$OUT/$label-final.png" > "$OUT/$label-screenshot.log" 2>&1 || true
    python3 - "$OUT/$label-xcodebuild.log" "$test" > "$OUT/$label-selection.log" <<'PY' || result=1
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(errors='replace')
expected = sys.argv[2]
completed = re.findall(r"^Test Case '-\[InstalledKeyboardUITests (\w+)\]' (passed|failed) ", text, re.M)
if completed != [(expected, 'passed')]:
    raise SystemExit(f'Expected exactly one selected pass for {expected}; actual={completed}')
print('exactly one selected pass:', completed)
PY
    printf 'result=%s\n' "$result" >> "$OUT/$label-bounds.txt"
    return "$result"
}

# Actual final identity and hash, for the pre-AX handoff and post-reinstall check.
identity() {
    local label="$1" path installed=''
    path="$OUT/$label"
    mkdir -p "$path" || return 1
    xcrun simctl get_app_container "$DEVICE_ID" osku.me.freeshiamyios app \
        > "$path/installed-container.log" 2>&1 || return 1
    installed=$(cat "$path/installed-container.log") || return 1
    [[ -d "$installed" ]] || return 1
    printf 'installed_app=%s\ninstalled_extension=%s\n' "$installed" "$installed/PlugIns/FreeShiamyKeyboard.appex" > "$path/paths.txt" || return 1
    python3 - "$PROOF/bundle-identities.json" "$APP" "$installed" "$path" <<'PY' || return 1
import hashlib, json, pathlib, plistlib, sys
proof, built, installed, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])
expected = {r['bundleId']: r['executableSha256'] for r in json.loads(proof.read_text())}
records = []
for scope, root in [('built', built), ('installed', installed)]:
    for kind, bundle, bundle_id, executable in [
        ('app', root, 'osku.me.freeshiamyios', 'freeshiamy-ios'),
        ('keyboard-extension', root/'PlugIns'/'FreeShiamyKeyboard.appex', 'osku.me.freeshiamyios.keyboard', 'FreeShiamyKeyboard')]:
        metadata = plistlib.loads((bundle/'Info.plist').read_bytes())
        if metadata.get('CFBundleIdentifier') != bundle_id or metadata.get('CFBundleExecutable') != executable:
            raise SystemExit(f'Wrong {scope} {kind} bundle identity: {bundle}')
        actual = hashlib.sha256((bundle/executable).read_bytes()).hexdigest()
        records.append({'scope': scope, 'kind': kind, 'path': str(bundle), 'bundle_id': bundle_id,
                        'executable_sha256': actual, 'preboot_sha256': expected[bundle_id]})
        if actual != expected[bundle_id]: raise SystemExit(f'{scope} {kind} differs from preboot signed final executable')
(output/'identity.json').write_text(json.dumps(records, indent=2)+'\n')
PY
    local kind bundle executable entitlements
    for kind in app keyboard-extension; do
        if [[ "$kind" == app ]]; then
            bundle="$installed"; executable="$bundle/freeshiamy-ios"; entitlements=freeshiamy-ios/freeshiamy-ios.entitlements
        else
            bundle="$installed/PlugIns/FreeShiamyKeyboard.appex"; executable="$bundle/FreeShiamyKeyboard"; entitlements=FreeShiamyKeyboard/FreeShiamyKeyboard.entitlements
        fi
        mkdir -p "$path/$kind" || return 1
        codesign --display --verbose=4 "$bundle" > "$path/$kind/codesign-display.log" 2>&1 || return 1
        codesign --verify --strict --verbose=4 "$bundle" > "$path/$kind/codesign-verify.log" 2>&1 || return 1
        grep -qx 'Signature=adhoc' "$path/$kind/codesign-display.log" || return 1
        python3 ci/check-simulator-effective-entitlements.py "$executable" "$entitlements" "$path/$kind" \
            > "$path/$kind/effective-check.log" 2>&1 || return 1
    done
}

# Bounded, unfiltered Simulator and runner-host timelines for both selected
# stages, including first-boundary failure. Each command/status is retained.
collect_stage_logs() {
    local label="$1" start end sim_status=0 host_status=0 sim_count_status=0 host_count_status=0
    start=$(sed -n 's/^start_utc=//p' "$OUT/$label-bounds.txt")
    end=$(sed -n 's/^end_utc_ceil=//p' "$OUT/$label-bounds.txt")
    xcrun simctl spawn "$DEVICE_ID" log show --start "${start}+0000" --end "${end}+0000" \
        --timezone UTC --style compact --info --debug \
        > "$OUT/$label-simulator-all-processes.log" 2>&1 || sim_status=$?
    python3 ci/count-run21-log-events.py "$OUT/$label-simulator-all-processes.log" \
        "${start}+0000" "${end}+0000" > "$OUT/$label-simulator-event-count.txt" \
        2> "$OUT/$label-simulator-event-count.stderr" || sim_count_status=$?
    printf 'command=xcrun simctl spawn %s log show --start %s+0000 --end %s+0000 --timezone UTC --style compact --info --debug\nstatus=%s\nevent_count_status=%s\nstart_utc_floor=%s\nend_utc_ceil=%s\n' \
        "$DEVICE_ID" "$start" "$end" "$sim_status" "$sim_count_status" "$start" "$end" \
        > "$OUT/$label-simulator-log-status.txt"
    if [[ "$sim_status" != 0 || "$sim_count_status" != 0 ]]; then
        echo diagnostic_missing=simulator-log >> "$OUT/$label-simulator-log-status.txt"
    fi
    log show --start "${start}+0000" --end "${end}+0000" --timezone UTC \
        --style compact --info --debug > "$OUT/$label-runner-host-launch.log" 2>&1 || host_status=$?
    python3 ci/count-run21-log-events.py "$OUT/$label-runner-host-launch.log" \
        "${start}+0000" "${end}+0000" > "$OUT/$label-runner-host-event-count.txt" \
        2> "$OUT/$label-runner-host-event-count.stderr" || host_count_status=$?
    printf 'command=log show --start %s+0000 --end %s+0000 --timezone UTC --style compact --info --debug\nstatus=%s\nevent_count_status=%s\nstart_utc_floor=%s\nend_utc_ceil=%s\n' \
        "$start" "$end" "$host_status" "$host_count_status" "$start" "$end" \
        > "$OUT/$label-runner-host-log-status.txt"
    if [[ "$host_status" != 0 || "$host_count_status" != 0 ]]; then
        echo diagnostic_missing=runner-host-log >> "$OUT/$label-runner-host-log-status.txt"
    fi
    [[ "$sim_status" == 0 && "$sim_count_status" == 0 && "$host_status" == 0 && "$host_count_status" == 0 ]]
}

# The default installed picker case is setup. A failure retains its first
# boundary evidence and ends this experiment without sampling or retrying.
default_result=0
run_case installed-default testInstalledKeyboardWithFullAccessOff || default_result=$?
default_log_result=0
collect_stage_logs installed-default || default_log_result=$?
if [[ "$default_result" != 0 ]]; then
    identity default-after || printf 'diagnostic_missing=default post-stage identity failed\n' > "$OUT/default-after-identity-failure.log"
    printf 'default=failed\nax=not-run/default-failed\nobserver=not-run\n' > "$OUT/stage-status.txt"
    exit 1
fi
if [[ "$default_log_result" != 0 ]]; then
    printf 'default=passed\ndefault_logs=incomplete\nax=not-run/default-evidence-incomplete\n' > "$OUT/stage-status.txt"
    exit 1
fi
if ! identity default-after; then
    printf 'default=passed\nidentity=failed\nax=not-run/identity-failed\n' > "$OUT/stage-status.txt"
    exit 1
fi
xcrun simctl ui "$DEVICE_ID" content_size accessibility-extra-extra-extra-large \
    > "$OUT/ax-trait-set.log" 2>&1
xcrun simctl ui "$DEVICE_ID" content_size > "$OUT/ax-trait-readback.log" 2>&1
grep -qx accessibility-extra-extra-extra-large "$OUT/ax-trait-readback.log"
identity ax-before

# Arm before AX xcodebuild, with no name-based PID discovery. The observer stops
# after one exact launch, failure, or this original AX stage's end.
python3 ci/observe-ipad-keyboard-activation.py --udid "$DEVICE_ID" \
    --output "$OUT/observer" --stream-help "$OUT/log-stream-help.log" \
    --sample-help "$OUT/sample-help.log" --max-seconds 420 &
OBSERVER_PID=$!
printf 'observer_pid=%s\n' "$OBSERVER_PID" > "$OUT/observer-lifecycle.log"
for _ in {1..50}; do
    if [[ -f "$OUT/observer/armed.json" || -f "$OUT/observer/observer-summary.json" ]]; then break; fi
    if ! kill -0 "$OBSERVER_PID" 2>/dev/null; then break; fi
    sleep 0.1
done
if [[ ! -f "$OUT/observer/armed.json" || -f "$OUT/observer/observer-summary.json" ]] || ! kill -0 "$OBSERVER_PID" 2>/dev/null; then
    printf 'diagnostic_missing=observer did not prove log-stream readiness before AX invocation\n' >> "$OUT/observer-lifecycle.log"
    printf 'default=passed\nax=not-run/observer-readiness-missing\n' > "$OUT/stage-status.txt"
    exit 1
fi
ax_result=0
run_case installed-adaptive-ax testInstalledAccessibilityMoreAndOffscreenCandidate || ax_result=$?
if kill -0 "$OBSERVER_PID" 2>/dev/null; then kill -TERM "$OBSERVER_PID" 2>/dev/null || true; fi
observer_wait_status=0
wait "$OBSERVER_PID" > "$OUT/observer-exit.log" 2>&1 || observer_wait_status=$?
printf 'observer_wait_status=%s\n' "$observer_wait_status" >> "$OUT/observer-lifecycle.log"
OBSERVER_PID=''
ax_identity_result=0
identity ax-after || { ax_identity_result=1; printf 'diagnostic_missing=AX post-reinstall installed identity failed\n' > "$OUT/ax-after-identity-failure.log"; }

# Stage-window logs, including host service113/fallback. These cannot replace
# the original selected UI result or prove sample overlap.
ax_log_result=0
collect_stage_logs installed-adaptive-ax || ax_log_result=$?
python3 ci/check-installed-ax-process.py "$OUT/installed-adaptive-ax-simulator-all-processes.log" \
    > "$OUT/ax-process-check.log" 2>&1 || true
correlation_result=0
python3 ci/check-ipad-activation-correlation.py "$OUT" \
    > "$OUT/observer-correlation.log" 2>&1 || correlation_result=$?
printf 'default=passed\nax_ui_status=%s\nax_identity_status=%s\nax_log_status=%s\ncorrelation_status=%s\nobserver=%s\nhosted=not-run/diagnostic-only\nheight=not-run/diagnostic-only\nactions=not-run/diagnostic-only\nacceptance=not-advanced\n' \
    "$ax_result" "$ax_identity_result" "$ax_log_result" "$correlation_result" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("diagnostic","missing"))' "$OUT/observer/observer-summary.json" 2>/dev/null || echo missing)" \
    > "$OUT/stage-status.txt"
if [[ "$ax_result" != 0 || "$ax_identity_result" != 0 || "$ax_log_result" != 0 || "$correlation_result" != 0 ]]; then exit 1; fi
exit 0
