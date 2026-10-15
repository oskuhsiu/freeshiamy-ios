#!/usr/bin/env bash
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
source ci/simulator-build-args.sh
ARTIFACTS="${GITHUB_WORKSPACE:-$PWD}/ci-artifacts"
TEMP_ROOT="${RUNNER_TEMP:-/tmp}"
mkdir -p "$ARTIFACTS"
ACCEPTANCE_SCENARIO="${FSH_ACCEPTANCE_SCENARIO:-height}"
case "$ACCEPTANCE_SCENARIO" in
    height)
case "${FSH_HEIGHT_ENDPOINT:-}" in
    90|220) HEIGHT_ENDPOINT="$FSH_HEIGHT_ENDPOINT" ;;
    *)
        echo "Missing or invalid FSH_HEIGHT_ENDPOINT: '${FSH_HEIGHT_ENDPOINT:-missing}'; expected 90 or 220" \
            | tee "$ARTIFACTS/height-endpoint-selection.log"
        exit 1
        ;;
esac
if [[ "$HEIGHT_ENDPOINT" == 90 ]]; then UNSELECTED_HEIGHT_ENDPOINT=220; else UNSELECTED_HEIGHT_ENDPOINT=90; fi
printf 'Selected height endpoint: %s%%\nUnselected endpoint: %s%% not-run/pending in this matrix job\n' \
    "$HEIGHT_ENDPOINT" "$UNSELECTED_HEIGHT_ENDPOINT" | tee "$ARTIFACTS/height-endpoint-selection.log"
        ;;
    actions)
        if [[ "${FSH_HEIGHT_ENDPOINT+x}" == x ]]; then
            echo "Actions require FSH_HEIGHT_ENDPOINT genuinely unset, including no explicit empty value" \
                | tee "$ARTIFACTS/acceptance-scenario-selection.log"
            exit 1
        fi
        echo 'Selected scenario: input-actions; height endpoints not-run in this job (same-SHA workflow dependencies required)' \
            | tee "$ARTIFACTS/acceptance-scenario-selection.log"
        ;;
    *)
        echo "Invalid FSH_ACCEPTANCE_SCENARIO: '$ACCEPTANCE_SCENARIO'; expected height or actions" \
            | tee "$ARTIFACTS/acceptance-scenario-selection.log"
        exit 1
        ;;
esac
echo "[stage] preflight"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
    echo "Required Xcode 26.2 is unavailable: $DEVELOPER_DIR" | tee "$ARTIFACTS/preflight.log"
    exit 1
fi

{
    echo "Commit: $(git rev-parse HEAD)"
    echo "Runner image: ${ImageOS:-unknown} ${ImageVersion:-unknown}"
    sw_vers
    uname -m
    xcodebuild -version
    xcrun --sdk iphonesimulator --show-sdk-version
    xcrun simctl list runtimes
} 2>&1 | tee "$ARTIFACTS/preflight.log"
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Expected arm64 macOS runner" | tee -a "$ARTIFACTS/preflight.log"
    exit 1
fi
python3 ci/test-installed-geometry-parser.py > "$ARTIFACTS/geometry-parser-selftest.log" 2>&1
python3 ci/check-installed-ax-process.py --self-test > "$ARTIFACTS/installed-ax-parser-selftest.log" 2>&1
python3 ci/check-installed-height-process.py --self-test > "$ARTIFACTS/installed-height-parser-selftest.log" 2>&1
python3 ci/check-installed-height-milestones.py --self-test > "$ARTIFACTS/installed-height-milestone-selftest.log" 2>&1
python3 ci/check-installed-action-process.py --self-test > "$ARTIFACTS/installed-action-parser-selftest.log" 2>&1
python3 ci/check-content-size-readback.py --self-test > "$ARTIFACTS/content-size-readback-selftest.log" 2>&1

# The repository intentionally does not track a developer's signing overrides.
touch Config/Local.xcconfig
xcodebuild -list -project freeshiamy-ios.xcodeproj > "$ARTIFACTS/project-list.log" 2>&1
xcodebuild -help > "$ARTIFACTS/xcodebuild-help.log" 2>&1
xcrun simctl help ui > "$ARTIFACTS/simctl-ui-help.log" 2>&1 || true
get_app_container_help_result=0
xcrun simctl help get_app_container > "$ARTIFACTS/simctl-get-app-container-help.log" 2>&1 \
    || get_app_container_help_result=$?
if [[ "$get_app_container_help_result" != 0 ]]; then
    echo "diagnostic_missing=public get_app_container help status=$get_app_container_help_result" \
        >> "$ARTIFACTS/simctl-get-app-container-help.log"
fi
xcrun simctl list -j devicetypes > "$ARTIFACTS/simctl-device-types.json" 2>&1
DEVICE_TYPE="${FSH_SIM_DEVICE_TYPE:-com.apple.CoreSimulator.SimDeviceType.iPhone-16}"
case "$DEVICE_TYPE" in
    com.apple.CoreSimulator.SimDeviceType.iPhone-16)
        DEVICE_LABEL=iphone-16
        DEVICE_FAMILY=iPhone
        ;;
    com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3)
        DEVICE_LABEL=ipad-air-11-m3
        DEVICE_FAMILY=iPad
        ;;
    *)
        echo "Unsupported simulator device type: $DEVICE_TYPE" | tee "$ARTIFACTS/device-selection.log"
        exit 1
        ;;
esac
python3 - "$ARTIFACTS/simctl-device-types.json" "$DEVICE_TYPE" "$DEVICE_FAMILY" \
    > "$ARTIFACTS/device-selection.log" 2>&1 <<'PY'
import json, sys
device_types, identifier, family = sys.argv[1:]
matches = [device for device in json.load(open(device_types))["devicetypes"]
           if device.get("identifier") == identifier and device.get("productFamily") == family]
if len(matches) != 1:
    sys.exit(f"Required {family} device type {identifier} not uniquely available in simctl device catalog")
print(f"Selected device type: {matches[0]['name']} ({identifier}); product family: {family}")
PY
if ! grep -q -- '-testLanguage' "$ARTIFACTS/xcodebuild-help.log" || \
   ! grep -q -- '-testRegion' "$ARTIFACTS/xcodebuild-help.log" || \
   ! grep -q -- '-only-testing:TEST-IDENTIFIER' "$ARTIFACTS/xcodebuild-help.log" || \
   ! grep -q -- '-test-timeouts-enabled' "$ARTIFACTS/xcodebuild-help.log" || \
   ! grep -q -- '-maximum-test-execution-time-allowance' "$ARTIFACTS/xcodebuild-help.log" || \
   ! grep -q -- '-collect-test-diagnostics on-failure' "$ARTIFACTS/xcodebuild-help.log"; then
    echo "Xcode 26.2 does not list the required focused-test, timeout, or locale options" | tee "$ARTIFACTS/test-options-preflight.log"
    exit 1
fi

RUNTIME=$(xcrun simctl list -j runtimes | python3 -c '
import json, sys
for runtime in json.load(sys.stdin)["runtimes"]:
    if runtime["identifier"] == "com.apple.CoreSimulator.SimRuntime.iOS-26-2" and runtime.get("isAvailable"):
        print(runtime["identifier"])
        break
else:
    sys.exit("iOS 26.2 simulator runtime is unavailable")
')

if [[ "$ACCEPTANCE_SCENARIO" == height ]]; then
    DEVICE_SCOPE="height-${HEIGHT_ENDPOINT}"
else
    DEVICE_SCOPE=input-actions
fi
DEVICE_ID=$(xcrun simctl create "freeshiamy-ci-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-${DEVICE_LABEL}-${DEVICE_SCOPE}" \
    "$DEVICE_TYPE" "$RUNTIME")
if [[ "$ACCEPTANCE_SCENARIO" == height ]]; then
    echo "Job-owned simulator: $DEVICE_ID; type: $DEVICE_TYPE; runtime: $RUNTIME; selected height endpoint: ${HEIGHT_ENDPOINT}%" | tee -a "$ARTIFACTS/device-selection.log"
else
    echo "Job-owned simulator: $DEVICE_ID; type: $DEVICE_TYPE; runtime: $RUNTIME; selected scenario: input-actions; height endpoint unset" | tee -a "$ARTIFACTS/device-selection.log"
fi
cleanup() {
    xcrun simctl shutdown "$DEVICE_ID" >/dev/null 2>&1 || true
    xcrun simctl delete "$DEVICE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[stage] boot job-owned simulator $DEVICE_ID"
xcrun simctl boot "$DEVICE_ID"
python3 - "$DEVICE_ID" "$ARTIFACTS/simulator-boot.log" <<'PY'
import subprocess, sys
with open(sys.argv[2], "wb") as log:
    subprocess.run(["xcrun", "simctl", "bootstatus", sys.argv[1], "-b"],
                   stdout=log, stderr=subprocess.STDOUT, timeout=600, check=True)
PY
xcrun simctl spawn "$DEVICE_ID" defaults read -g AppleLanguages \
    > "$ARTIFACTS/simulator-languages.log" 2>&1 || true

run_stage() {
    local label="$1" scheme="$2" allowance="$3" maximum="$4" result=0
    shift 4
    local destination="platform=iOS Simulator,id=$DEVICE_ID"
    fsh_validate_simulator_destination "$destination" || return 1
    echo "[stage] $label on $DEVICE_ID"
    set +e
    xcodebuild test \
        -project freeshiamy-ios.xcodeproj \
        -scheme "$scheme" \
        -configuration Debug \
        -destination "$destination" \
        -testLanguage en \
        -testRegion US \
        -parallel-testing-enabled NO \
        -test-timeouts-enabled YES \
        -default-test-execution-time-allowance "$allowance" \
        -maximum-test-execution-time-allowance "$maximum" \
        -collect-test-diagnostics on-failure \
        -derivedDataPath "$TEMP_ROOT/freeshiamy-derived-data" \
        -resultBundlePath "$ARTIFACTS/$label.xcresult" \
        "$@" \
        "${FSH_CI_SIMULATOR_BUILD_ARGS[@]}" \
        2>&1 | tee "$ARTIFACTS/$label-xcodebuild.log"
    local -a pipeline_status=("${PIPESTATUS[@]}")
    local build_result=${pipeline_status[0]} log_result=${pipeline_status[1]}
    result=$build_result
    if [[ "$result" == 0 && "$log_result" != 0 ]]; then result=$log_result; fi
    set -e
    echo "[stage] $label xcodebuild status $build_result; tee status $log_result; combined stage status $result"
    if [[ -d "$ARTIFACTS/$label.xcresult" ]]; then
        mkdir -p "$ARTIFACTS/$label-attachments"
        if ! xcrun xcresulttool export attachments \
            --path "$ARTIFACTS/$label.xcresult" \
            --output-path "$ARTIFACTS/$label-attachments" \
            > "$ARTIFACTS/$label-attachments-export.log" 2>&1; then
            cat "$ARTIFACTS/$label-attachments-export.log"
            if [[ "$result" == 0 ]]; then result=1; fi
        fi
    fi
    xcrun simctl io "$DEVICE_ID" screenshot "$ARTIFACTS/$label-final.png" || true
    tail -n 120 "$ARTIFACTS/$label-xcodebuild.log"
    return "$result"
}

# Both built and installed bundle copies must carry the actual Simulator
# entitlement section and valid ad-hoc signatures. Source plists alone do not
# establish the extension's effective identity.
verify_ci_bundle_pair() {
    local label="$1" app_bundle="$2" result=0
    local scope bundle executable source_entitlements expected_id expected_executable actual_id actual_executable
    for scope in app keyboard-extension; do
        if [[ "$scope" == app ]]; then
            bundle="$app_bundle"
            expected_id=osku.me.freeshiamyios
            expected_executable=freeshiamy-ios
            source_entitlements=freeshiamy-ios/freeshiamy-ios.entitlements
        else
            bundle="$app_bundle/PlugIns/FreeShiamyKeyboard.appex"
            expected_id=osku.me.freeshiamyios.keyboard
            expected_executable=FreeShiamyKeyboard
            source_entitlements=FreeShiamyKeyboard/FreeShiamyKeyboard.entitlements
        fi
        mkdir -p "$ARTIFACTS/$label-$scope" || { result=1; continue; }
        actual_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist" 2>&1) || result=1
        actual_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Info.plist" 2>&1) || result=1
        printf 'expected_id=%s\nactual_id=%s\nexpected_executable=%s\nactual_executable=%s\n' \
            "$expected_id" "$actual_id" "$expected_executable" "$actual_executable" \
            > "$ARTIFACTS/$label-$scope/identity.txt"
        if [[ "$actual_id" != "$expected_id" || "$actual_executable" != "$expected_executable" ]]; then
            result=1
            continue
        fi
        executable="$bundle/$actual_executable"
        shasum -a 256 "$bundle/Info.plist" "$source_entitlements" "$executable" \
            > "$ARTIFACTS/$label-$scope/source-and-built-hashes.txt" 2>&1 || result=1
        codesign --display --verbose=4 "$bundle" \
            > "$ARTIFACTS/$label-$scope/codesign-display.log" 2>&1 || result=1
        codesign --verify --strict --verbose=4 "$bundle" \
            > "$ARTIFACTS/$label-$scope/codesign-verify.log" 2>&1 || result=1
        if ! grep -qx 'Signature=adhoc' "$ARTIFACTS/$label-$scope/codesign-display.log"; then result=1; fi
        python3 ci/check-simulator-effective-entitlements.py "$executable" "$source_entitlements" \
            "$ARTIFACTS/$label-$scope" > "$ARTIFACTS/$label-$scope/effective-check.log" 2>&1 || result=1
    done
    printf 'scope=%s\nidentity_result=%s\n' "$label" "$result" > "$ARTIFACTS/$label-identity-check.log"
    return "$result"
}

focused_result=0
run_stage hosted-focused freeshiamy-ios 120 180 \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testAXCompactAlternateTypographySettlesAcrossRepeatedLayouts' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testAttachedHostHeightAndDynamicTypeAdaptWithoutRebuildingComposition' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testCandidateAccessibilityDescribesCodeExactnessAndRealShortcutsAcrossContexts' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testHostActionTitlesWrapInAttachedAccessibilityViewport' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testHostPanelScrollsFocusedFieldsAboveSceneBackedKeyboard' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testHostCodeSearchRendersInAttachedWindow' \
    || focused_result=$?
built_identity_result=skipped
if [[ "$focused_result" == 0 ]]; then
    built_identity_result=0
    verify_ci_bundle_pair built-after-focused \
        "$TEMP_ROOT/freeshiamy-derived-data/Build/Products/Debug-iphonesimulator/freeshiamy-ios.app" \
        || built_identity_result=$?
    if [[ "$built_identity_result" != 0 ]]; then
        printf 'hosted-focused=%s\nbuilt-simulator-identity=%s\ninstalled-stages=not-run/identity-failed\n' \
            "$focused_result" "$built_identity_result" | tee "$ARTIFACTS/stage-status.txt"
        exit 1
    fi
fi
hosted_result=skipped
if [[ "$focused_result" == 0 ]]; then
    hosted_result=0
    run_stage hosted freeshiamy-ios 120 180 || hosted_result=$?
else
    echo '[stage] Full hosted suite skipped because focused diagnostics failed' | tee "$ARTIFACTS/hosted-skipped.log"
fi

# RequestsOpenAccess describes the extension's capability request, not whether
# the user granted Full Access. The UI test must independently observe OFF.
EXTENSION_PLIST="$TEMP_ROOT/freeshiamy-derived-data/Build/Products/Debug-iphonesimulator/freeshiamy-ios.app/PlugIns/FreeShiamyKeyboard.appex/Info.plist"
plist_result=0
if [[ ! -f "$EXTENSION_PLIST" ]]; then
    echo "Built extension Info.plist missing: $EXTENSION_PLIST" | tee "$ARTIFACTS/extension-plist.log"
    plist_result=1
else
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$EXTENSION_PLIST" > "$ARTIFACTS/extension-plist.log"
    /usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionAttributes:RequestsOpenAccess' "$EXTENSION_PLIST" >> "$ARTIFACTS/extension-plist.log"
    cat "$ARTIFACTS/extension-plist.log"
    grep -q '^osku.me.freeshiamyios.keyboard$' "$ARTIFACTS/extension-plist.log" || plist_result=1
    grep -q '^true$' "$ARTIFACTS/extension-plist.log" || plist_result=1
fi

ui_result=0
date -u +'%Y-%m-%d %H:%M:%S' > "$ARTIFACTS/installed-stage-start.txt"
run_stage installed-extension InstalledKeyboardSmoke 300 360 \
    '-only-testing:InstalledKeyboardUITests/InstalledKeyboardUITests/testInstalledKeyboardWithFullAccessOff' \
    || ui_result=$?
if [[ "$ui_result" == 0 ]] && \
   [[ "$(grep -Fc "Test Case '-[InstalledKeyboardUITests testInstalledKeyboardWithFullAccessOff]' passed" "$ARTIFACTS/installed-extension-xcodebuild.log" || true)" != 1 ]]; then
    echo '[stage] Default installed smoke did not complete exactly one selected test' \
        | tee "$ARTIFACTS/installed-extension-selection.log"
    ui_result=1
fi
# Collect extension process diagnostics even when the first UI boundary fails.
xcrun simctl spawn "$DEVICE_ID" log show --last 30m --style compact --info --debug \
    --predicate 'process == "FreeShiamyKeyboard" OR eventMessage CONTAINS "FreeShiamyKeyboard lifecycle"' \
    > "$ARTIFACTS/installed-extension-process.log" 2>&1 || true
# This window begins immediately before the black-box installed test, so the
# host PID and geometry cannot be confused with prior hosted XCTest fixtures.
xcrun simctl spawn "$DEVICE_ID" log show --start "$(cat "$ARTIFACTS/installed-stage-start.txt")" \
    --style compact --info --debug \
    --predicate 'process == "freeshiamy-ios" AND eventMessage CONTAINS "[HostGeometry]"' \
    > "$ARTIFACTS/installed-host-geometry.log" 2>&1 || true
host_geometry_result=0
python3 ci/check-installed-host-geometry.py "$ARTIFACTS/installed-host-geometry.log" \
    "$ARTIFACTS/installed-extension-attachments" \
    > "$ARTIFACTS/installed-host-geometry-check.log" 2>&1 || host_geometry_result=$?
process_observation=missing-inconclusive
process_result=1
if grep -Eq "FreeShiamyKeyboard lifecycle bundle=osku.me.freeshiamyios.keyboard pid=[0-9]+ hasFullAccess=NO" "$ARTIFACTS/installed-extension-process.log"; then
    process_observation=observed-no-full-access
    process_result=0
fi

# Read-only identity snapshots diagnose the handoff between independently
# selected installed stages. Missing diagnostics never substitute for a pass.
record_bundle_identity() {
    local label="$1" bundle="$2" plist="$2/Info.plist" key value executable status
    printf '\n[%s]\nbundle_path=%s\n' "$label" "$bundle"
    if [[ ! -f "$plist" ]]; then
        printf 'diagnostic_missing=%s Info.plist absent\n' "$label"
        return 0
    fi
    for key in CFBundleIdentifier CFBundleVersion CFBundleExecutable; do
        status=0
        value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>&1) || status=$?
        printf '%s=%s\n' "$key" "$value"
        if [[ "$status" != 0 || -z "$value" ]]; then
            printf 'diagnostic_missing=%s %s read status=%s\n' "$label" "$key" "$status"
        fi
    done
    status=0
    shasum -a 256 "$plist" || status=$?
    if [[ "$status" != 0 ]]; then printf 'diagnostic_missing=%s Info.plist SHA256 status=%s\n' "$label" "$status"; fi
    status=0
    executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>&1) || status=$?
    if [[ "$status" == 0 && -n "$executable" && -f "$bundle/$executable" ]]; then
        status=0
        shasum -a 256 "$bundle/$executable" || status=$?
        if [[ "$status" != 0 ]]; then printf 'diagnostic_missing=%s executable SHA256 status=%s\n' "$label" "$status"; fi
    else
        printf 'diagnostic_missing=%s executable absent or identity unreadable\n' "$label"
    fi
}

record_app_identity() {
    local label="$1" app_bundle="$TEMP_ROOT/freeshiamy-derived-data/Build/Products/Debug-iphonesimulator/freeshiamy-ios.app"
    local container status=0
    {
        printf 'Source SHA: %s\nOwned simulator: %s\nSnapshot: %s\n' "$(git rev-parse HEAD)" "$DEVICE_ID" "$label"
        date -u +'%Y-%m-%d %H:%M:%S UTC'
        record_bundle_identity 'built containing app' "$app_bundle"
        record_bundle_identity 'built keyboard extension' "$app_bundle/PlugIns/FreeShiamyKeyboard.appex"
        if [[ "$get_app_container_help_result" != 0 ]]; then
            echo 'diagnostic_missing=public simctl get_app_container help unavailable; see simctl-get-app-container-help.log'
        else
            xcrun simctl get_app_container "$DEVICE_ID" osku.me.freeshiamyios app \
                > "$ARTIFACTS/$label-installed-app-container.log" 2>&1 || status=$?
            printf 'get_app_container status: %s\n' "$status"
            cat "$ARTIFACTS/$label-installed-app-container.log"
            if [[ "$status" == 0 ]]; then
                container=$(cat "$ARTIFACTS/$label-installed-app-container.log")
                if [[ -d "$container" ]]; then
                    record_bundle_identity 'installed containing app' "$container"
                    record_bundle_identity 'installed keyboard extension' "$container/PlugIns/FreeShiamyKeyboard.appex"
                else
                    echo 'diagnostic_missing=public app-container result is not a readable installed bundle directory'
                fi
            else
                echo 'diagnostic_missing=public get_app_container failed; supported help retained, no alternate flags attempted'
            fi
        fi
    } > "$ARTIFACTS/$label-app-identity.log" 2>&1
}

# The public simctl app-container selector returns the installed .app bundle.
# Its separate group-container query is diagnostic path evidence only, never
# a claim that the keyboard extension successfully read shared defaults.
installed_identity_result=skipped
installed_container_status=0
xcrun simctl get_app_container "$DEVICE_ID" osku.me.freeshiamyios app \
    > "$ARTIFACTS/installed-identity-app-container.log" 2>&1 || installed_container_status=$?
if [[ "$installed_container_status" == 0 ]]; then
    installed_app_bundle=$(cat "$ARTIFACTS/installed-identity-app-container.log")
    if [[ -d "$installed_app_bundle" ]]; then
        installed_identity_result=0
        verify_ci_bundle_pair installed-default "$installed_app_bundle" || installed_identity_result=$?
    else
        installed_identity_result=1
        echo 'diagnostic_missing=installed app-container path is not a directory' \
            >> "$ARTIFACTS/installed-identity-app-container.log"
    fi
elif [[ "$ui_result" == 0 ]]; then
    installed_identity_result=1
fi
group_container_status=0
xcrun simctl get_app_container "$DEVICE_ID" osku.me.freeshiamyios group.osku.me.freeshiamy_ios \
    > "$ARTIFACTS/installed-identity-group-container.log" 2>&1 || group_container_status=$?
printf '\nscope=read-only group path; not extension read access\nget_app_container_status=%s\n' \
    "$group_container_status" >> "$ARTIFACTS/installed-identity-group-container.log"
record_app_identity installed-default-identity
if [[ "$ui_result" == 0 && "$installed_identity_result" != 0 ]]; then
    printf 'installed-extension=%s\ninstalled-simulator-identity=%s\nax-height-stages=not-run/identity-failed\n' \
        "$ui_result" "$installed_identity_result" | tee "$ARTIFACTS/stage-status.txt"
    exit 1
fi

collect_ax_service_log() {
    local label="$1" predicate="$2" status=0 records
    xcrun simctl spawn "$DEVICE_ID" log show \
        --start "$(cat "$ARTIFACTS/installed-ax-stage-start.txt")" \
        --style compact --info --debug --predicate "$predicate" \
        > "$ARTIFACTS/$label.log" 2>&1 || status=$?
    records=$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' "$ARTIFACTS/$label.log" || true)
    printf '\ndiagnostic_command_status=%s matching_event_records=%s\n' "$status" "$records" \
        >> "$ARTIFACTS/$label.log"
    if [[ "$status" != 0 ]]; then
        printf '\ndiagnostic_missing=%s public log show status=%s\n' "$label" "$status" \
            >> "$ARTIFACTS/$label.log"
    elif [[ "$records" == 0 ]]; then
        printf '\ndiagnostic_missing=%s no matching event records\n' "$label" \
            >> "$ARTIFACTS/$label.log"
    fi
}

# End bounds are rounded up to the next whole second so a fractional-second
# test completion is included by log show, without widening by more than 1s.
capture_stage_end_utc() {
    python3 -c 'import datetime; now=datetime.datetime.now(datetime.timezone.utc); print((now+datetime.timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S"))'
}

# This is the unfiltered runner-host macOS store, distinct from simctl's
# Simulator store. The stage's end was captured before later diagnostics.
collect_runner_host_launch_log() {
    local label="$1" start_file="$2" end_file="$3" status=0 records start end
    start=$(cat "$start_file")
    end=$(cat "$end_file")
    local -a command=(log show --start "${start}+0000" --end "${end}+0000"
        --timezone UTC --style compact --info --debug)
    "${command[@]}" \
        > "$ARTIFACTS/$label.log" 2>&1 || status=$?
    records=$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' "$ARTIFACTS/$label.log" || true)
    printf '\ncommand=' >> "$ARTIFACTS/$label.log"
    printf '%q ' "${command[@]}" >> "$ARTIFACTS/$label.log"
    printf '\nscope=unfiltered runner-host-macOS (not Simulator; default private-data redaction)\nstart_utc_seconds_floor=%s UTC\nend_utc_seconds_ceil=%s UTC (at most 1s after stage-end capture)\ndiagnostic_command_status=%s event_records=%s\n' \
        "$start" "$end" "$status" "$records" >> "$ARTIFACTS/$label.log"
    if [[ "$status" != 0 || "$records" == 0 ]]; then
        printf 'diagnostic_missing=%s runner-host log status=%s records=%s\n' \
            "$label" "$status" "$records" >> "$ARTIFACTS/$label.log"
    fi
}

# Actions have their own stage window; the unchanged AX/height path below is
# covered by successful same-SHA workflow dependencies, not repeated here.
collect_action_service_log() {
    local label="$1" predicate="$2" start_file="$3" status=0 records
    xcrun simctl spawn "$DEVICE_ID" log show \
        --start "$(cat "$start_file")" \
        --style compact --info --debug --predicate "$predicate" \
        > "$ARTIFACTS/$label.log" 2>&1 || status=$?
    records=$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' "$ARTIFACTS/$label.log" || true)
    printf '\ndiagnostic_command_status=%s matching_event_records=%s\n' "$status" "$records" \
        >> "$ARTIFACTS/$label.log"
    if [[ "$status" != 0 ]]; then
        printf '\ndiagnostic_missing=%s public log show status=%s\n' "$label" "$status" \
            >> "$ARTIFACTS/$label.log"
    elif [[ "$records" == 0 ]]; then
        printf '\ndiagnostic_missing=%s no matching event records\n' "$label" \
            >> "$ARTIFACTS/$label.log"
    fi
}

if [[ "$ACCEPTANCE_SCENARIO" == actions ]]; then
    action_content_size_result=skipped
    action_appearance_result=skipped
    action_ui_result=skipped
    action_process_result=skipped
    if [[ "$focused_result" == 0 && "$hosted_result" == 0 && "$plist_result" == 0 && \
          "$ui_result" == 0 && "$host_geometry_result" == 0 && "$process_result" == 0 ]]; then
        action_content_size_result=0
        action_appearance_result=0
        echo '[stage] Input actions public simulator traits large/light' | tee "$ARTIFACTS/installed-input-actions-traits.log"
        if ! xcrun simctl ui "$DEVICE_ID" content_size large \
            >> "$ARTIFACTS/installed-input-actions-traits.log" 2>&1; then action_content_size_result=1; fi
        if ! xcrun simctl ui "$DEVICE_ID" content_size \
            > "$ARTIFACTS/installed-input-actions-content-size-readback.log" 2>&1; then action_content_size_result=1; fi
        if ! python3 ci/check-content-size-readback.py "$ARTIFACTS/installed-input-actions-content-size-readback.log" large \
            > "$ARTIFACTS/installed-input-actions-content-size-check.log" 2>&1; then action_content_size_result=1; fi
        if ! xcrun simctl ui "$DEVICE_ID" appearance light \
            >> "$ARTIFACTS/installed-input-actions-traits.log" 2>&1; then action_appearance_result=1; fi
        if ! xcrun simctl ui "$DEVICE_ID" appearance \
            > "$ARTIFACTS/installed-input-actions-appearance-readback.log" 2>&1; then action_appearance_result=1; fi
        if ! grep -qx light "$ARTIFACTS/installed-input-actions-appearance-readback.log"; then action_appearance_result=1; fi
        if [[ "$action_content_size_result" == 0 && "$action_appearance_result" == 0 ]]; then
            date -u +'%Y-%m-%d %H:%M:%S' > "$ARTIFACTS/installed-input-actions-stage-start.txt"
            record_app_identity installed-input-actions-before
            action_ui_result=0
            run_stage installed-input-actions InstalledKeyboardSmoke 300 360 \
                '-only-testing:InstalledKeyboardUITests/InstalledKeyboardUITests/testInstalledBracketRootsUseRealLongPressAndLiteralSymbols' \
                '-only-testing:InstalledKeyboardUITests/InstalledKeyboardUITests/testInstalledCodeSearchReturnCommitsThenDismisses' \
                || action_ui_result=$?
            action_selection_result=0
            python3 - "$ARTIFACTS/installed-input-actions-xcodebuild.log" \
                > "$ARTIFACTS/installed-input-actions-selection.log" 2>&1 <<'PY_SELECTION' || action_selection_result=$?
import pathlib, re, sys
log = pathlib.Path(sys.argv[1]).read_text(errors="replace")
expected = {"testInstalledBracketRootsUseRealLongPressAndLiteralSymbols",
            "testInstalledCodeSearchReturnCommitsThenDismisses"}
completed = re.findall(r"^Test Case '-\[InstalledKeyboardUITests (\w+)\]' (passed|failed) ", log, re.M)
summaries = re.findall(r"^\s*Executed (\d+) tests?, with (\d+) failures", log, re.M)
if (len(completed) != 2 or {name for name, _ in completed} != expected or
        any(result != "passed" for _, result in completed) or not summaries or
        any(count != "2" or failures != "0" for count, failures in summaries)):
    sys.exit(f"Expected exactly two selected cases passed once each and two executed tests; cases={completed}; summaries={summaries}")
print("Exactly two selected installed action cases passed once each; executed-test summaries agree")
PY_SELECTION
            if [[ "$action_ui_result" == 0 && "$action_selection_result" != 0 ]]; then action_ui_result=$action_selection_result; fi
            record_app_identity installed-input-actions-after
            collect_action_service_log installed-input-actions-extension-process 'process == "FreeShiamyKeyboard"' \
                "$ARTIFACTS/installed-input-actions-stage-start.txt"
            collect_action_service_log installed-input-actions-host-geometry \
                'process == "freeshiamy-ios" AND eventMessage CONTAINS "[HostGeometry]"' \
                "$ARTIFACTS/installed-input-actions-stage-start.txt"
            action_process_result=0
            python3 ci/check-installed-action-process.py "$ARTIFACTS/installed-input-actions-extension-process.log" \
                "$ARTIFACTS/installed-input-actions-attachments" \
                > "$ARTIFACTS/installed-input-actions-process-check.log" 2>&1 || action_process_result=$?
            if [[ "$action_ui_result" != 0 || "$action_process_result" != 0 ]]; then
                collect_action_service_log installed-input-actions-host-full-process 'process == "freeshiamy-ios"' \
                    "$ARTIFACTS/installed-input-actions-stage-start.txt"
                collect_action_service_log installed-input-actions-service-launch \
                    'subsystem CONTAINS[c] "PlugInKit" OR subsystem CONTAINS[c] "ExtensionKit" OR subsystem CONTAINS[c] "RunningBoard" OR subsystem CONTAINS[c] "LaunchServices" OR process == "pkd" OR process == "runningboardd" OR process == "lsd" OR process == "launchd" OR eventMessage CONTAINS "osku.me.freeshiamyios.keyboard"' \
                    "$ARTIFACTS/installed-input-actions-stage-start.txt"
                collect_action_service_log installed-input-actions-install-registration \
                    'process == "installd" OR subsystem CONTAINS[c] "MobileInstallation" OR ((eventMessage CONTAINS "osku.me.freeshiamyios") AND (eventMessage CONTAINS[c] "install" OR eventMessage CONTAINS[c] "register" OR eventMessage CONTAINS[c] "registration"))' \
                    "$ARTIFACTS/installed-input-actions-stage-start.txt"
            fi
        else
            echo '[stage] Input actions skipped because public trait readbacks failed' | tee "$ARTIFACTS/installed-input-actions-skipped.log"
        fi
    else
        echo '[stage] Input actions skipped because local baseline acceptance gates did not all succeed' \
            | tee "$ARTIFACTS/installed-input-actions-skipped.log"
    fi
    printf 'scenario=input-actions\nhosted-focused=%s\nbuilt-simulator-identity=%s\nhosted-full=%s\nplist=%s\ninstalled-extension=%s\ninstalled-simulator-identity=%s\ninstalled-host-geometry=%s\nprocess-log=%s\nactions-content-size=%s\nactions-appearance=%s\nactions-ui=%s\nactions-process=%s\nax-height-status=not-run/dependency-gated\n' \
        "$focused_result" "$built_identity_result" "$hosted_result" "$plist_result" "$ui_result" "$installed_identity_result" "$host_geometry_result" "$process_observation" \
        "$action_content_size_result" "$action_appearance_result" "$action_ui_result" "$action_process_result" \
        | tee "$ARTIFACTS/stage-status.txt"
    if [[ "$focused_result" != 0 || "$built_identity_result" != 0 || "$hosted_result" != 0 || "$plist_result" != 0 || "$ui_result" != 0 || \
          "$installed_identity_result" != 0 || \
          "$host_geometry_result" != 0 || "$process_result" != 0 || "$action_content_size_result" != 0 || \
          "$action_appearance_result" != 0 || "$action_ui_result" != 0 || "$action_process_result" != 0 ]]; then exit 1; fi
    exit 0
fi

ax_content_size_result=skipped
ax_result=skipped
ax_process_result=skipped
if [[ "$ui_result" == 0 && "$host_geometry_result" == 0 && "$process_result" == 0 ]]; then
    record_app_identity installed-default-to-ax-before
    ax_content_size_result=0
    echo '[stage] set public simulator content size to Accessibility XXXL' | tee "$ARTIFACTS/installed-ax-content-size.log"
    if ! xcrun simctl ui "$DEVICE_ID" content_size accessibility-extra-extra-extra-large \
        >> "$ARTIFACTS/installed-ax-content-size.log" 2>&1; then
        ax_content_size_result=1
    fi
    if ! xcrun simctl ui "$DEVICE_ID" content_size \
        > "$ARTIFACTS/installed-ax-content-size-readback.log" 2>&1; then
        ax_content_size_result=1
    fi
    if ! grep -qx 'accessibility-extra-extra-extra-large' "$ARTIFACTS/installed-ax-content-size-readback.log"; then
        ax_content_size_result=1
    fi
    if [[ "$ax_content_size_result" == 0 ]]; then
        ax_result=0
        date -u +'%Y-%m-%d %H:%M:%S' > "$ARTIFACTS/installed-ax-stage-start.txt"
        run_stage installed-adaptive-ax InstalledKeyboardSmoke 300 360 \
            '-only-testing:InstalledKeyboardUITests/InstalledKeyboardUITests/testInstalledAccessibilityMoreAndOffscreenCandidate' \
            || ax_result=$?
        capture_stage_end_utc > "$ARTIFACTS/installed-ax-stage-end.txt"
        if [[ "$ax_result" == 0 ]] && \
           [[ "$(grep -Fc "Test Case '-[InstalledKeyboardUITests testInstalledAccessibilityMoreAndOffscreenCandidate]' passed" "$ARTIFACTS/installed-adaptive-ax-xcodebuild.log" || true)" != 1 ]]; then
            echo '[stage] AX installed smoke did not complete exactly one selected test' \
                | tee "$ARTIFACTS/installed-adaptive-ax-selection.log"
            ax_result=1
        fi
        # Preserve identity and the entire owned-device handoff timeline even
        # when AX fails before the extension's viewDidAppear lifecycle marker.
        record_app_identity installed-ax-after
        collect_ax_service_log installed-ax-host-process 'process == "freeshiamy-ios"'
        collect_ax_service_log installed-ax-extension-full-process 'process == "FreeShiamyKeyboard"'
        collect_ax_service_log installed-ax-service-launch \
            'subsystem CONTAINS[c] "PlugInKit" OR subsystem CONTAINS[c] "ExtensionKit" OR subsystem CONTAINS[c] "RunningBoard" OR subsystem CONTAINS[c] "LaunchServices" OR process == "pkd" OR process == "runningboardd" OR process == "lsd" OR process == "launchd" OR eventMessage CONTAINS "osku.me.freeshiamyios.keyboard"'
        collect_ax_service_log installed-ax-install-registration \
            'process == "installd" OR subsystem CONTAINS[c] "MobileInstallation" OR ((eventMessage CONTAINS "osku.me.freeshiamyios") AND (eventMessage CONTAINS[c] "install" OR eventMessage CONTAINS[c] "register" OR eventMessage CONTAINS[c] "registration"))'
        xcrun simctl spawn "$DEVICE_ID" log show \
            --start "$(cat "$ARTIFACTS/installed-ax-stage-start.txt")" \
            --style compact --info --debug \
            --predicate 'process == "FreeShiamyKeyboard"' \
            > "$ARTIFACTS/installed-ax-extension-process.log" 2>&1 || true
        ax_process_result=0
        python3 ci/check-installed-ax-process.py "$ARTIFACTS/installed-ax-extension-process.log" \
            > "$ARTIFACTS/installed-ax-process-check.log" 2>&1 || ax_process_result=$?
        if [[ "$ax_result" != 0 || "$ax_process_result" != 0 ]]; then
            collect_runner_host_launch_log installed-ax-runner-host-launch \
                "$ARTIFACTS/installed-ax-stage-start.txt" "$ARTIFACTS/installed-ax-stage-end.txt"
        fi
    fi
else
    echo '[stage] Installed AX/More test skipped because default installed smoke or evidence failed' \
        | tee "$ARTIFACTS/installed-ax-skipped.log"
fi

# Each height stage changes only public simulator traits. The real app Settings
# slider chooses the saved percentage, and extension process evidence verifies it.
collect_height_service_log() {
    local label="$1" predicate="$2" start_file="$3" status=0 records
    xcrun simctl spawn "$DEVICE_ID" log show \
        --start "$(cat "$start_file")" \
        --style compact --info --debug --predicate "$predicate" \
        > "$ARTIFACTS/$label.log" 2>&1 || status=$?
    records=$(grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' "$ARTIFACTS/$label.log" || true)
    printf '\ndiagnostic_command_status=%s matching_event_records=%s\n' "$status" "$records" \
        >> "$ARTIFACTS/$label.log"
    if [[ "$status" != 0 ]]; then
        printf '\ndiagnostic_missing=%s public log show status=%s\n' "$label" "$status" \
            >> "$ARTIFACTS/$label.log"
    elif [[ "$records" == 0 ]]; then
        printf '\ndiagnostic_missing=%s no matching event records\n' "$label" \
            >> "$ARTIFACTS/$label.log"
    fi
}

run_height_stage() {
    local label="$1" test_name="$2" percent="$3" category="$4" content_size="$5" appearance="$6" prefix="$7"
    local content_result=0 appearance_result=0 ui_stage_result=skipped process_stage_result=skipped
    local geometry_stage_result=skipped milestone_stage_result=skipped
    echo "[stage] $label public simulator traits $content_size/$appearance" | tee "$ARTIFACTS/$label-traits.log"
    if ! xcrun simctl ui "$DEVICE_ID" content_size "$content_size" \
        >> "$ARTIFACTS/$label-traits.log" 2>&1; then content_result=1; fi
    if ! xcrun simctl ui "$DEVICE_ID" content_size \
        > "$ARTIFACTS/$label-content-size-readback.log" 2>&1; then content_result=1; fi
    if ! python3 ci/check-content-size-readback.py "$ARTIFACTS/$label-content-size-readback.log" "$content_size" \
        > "$ARTIFACTS/$label-content-size-check.log" 2>&1; then content_result=1; fi
    if ! xcrun simctl ui "$DEVICE_ID" appearance "$appearance" \
        >> "$ARTIFACTS/$label-traits.log" 2>&1; then appearance_result=1; fi
    if ! xcrun simctl ui "$DEVICE_ID" appearance \
        > "$ARTIFACTS/$label-appearance-readback.log" 2>&1; then appearance_result=1; fi
    if ! grep -qx "$appearance" "$ARTIFACTS/$label-appearance-readback.log"; then appearance_result=1; fi
    if [[ "$content_result" == 0 && "$appearance_result" == 0 ]]; then
        date -u +'%Y-%m-%d %H:%M:%S' > "$ARTIFACTS/$label-stage-start.txt"
        record_app_identity "$label-before"
        ui_stage_result=0
        run_stage "$label" InstalledKeyboardSmoke 300 360 \
            "-only-testing:InstalledKeyboardUITests/InstalledKeyboardUITests/$test_name" \
            || ui_stage_result=$?
        capture_stage_end_utc > "$ARTIFACTS/$label-stage-end.txt"
        if [[ "$ui_stage_result" == 0 ]] && \
           [[ "$(grep -Fc "Test Case '-[InstalledKeyboardUITests $test_name]' passed" "$ARTIFACTS/$label-xcodebuild.log" || true)" != 1 ]]; then
            echo '[stage] Height installed scenario did not complete exactly one selected test' \
                | tee "$ARTIFACTS/$label-selection.log"
            ui_stage_result=1
        fi
        record_app_identity "$label-after"
        xcrun simctl spawn "$DEVICE_ID" log show \
            --start "$(cat "$ARTIFACTS/$label-stage-start.txt")" --style compact --info --debug \
            --predicate 'process == "FreeShiamyKeyboard"' \
            > "$ARTIFACTS/$label-extension-process.log" 2>&1 || true
        xcrun simctl spawn "$DEVICE_ID" log show \
            --start "$(cat "$ARTIFACTS/$label-stage-start.txt")" --style compact --info --debug \
            --predicate 'process == "freeshiamy-ios" AND eventMessage CONTAINS "[HostGeometry]"' \
            > "$ARTIFACTS/$label-host-geometry.log" 2>&1 || true
        process_stage_result=0
        python3 ci/check-installed-height-process.py "$ARTIFACTS/$label-extension-process.log" \
            "$percent" "$category" "$appearance" "$ARTIFACTS/$label-attachments" \
            > "$ARTIFACTS/$label-process-check.log" 2>&1 || process_stage_result=$?
        geometry_stage_result=0
        python3 ci/check-installed-host-geometry.py "$ARTIFACTS/$label-host-geometry.log" \
            "$ARTIFACTS/$label-attachments" \
            > "$ARTIFACTS/$label-host-geometry-check.log" 2>&1 || geometry_stage_result=$?
        milestone_stage_result=0
        python3 ci/check-installed-height-milestones.py "$ARTIFACTS/$label-host-geometry.log" \
            "$ARTIFACTS/$label-attachments" \
            > "$ARTIFACTS/$label-milestones-check.log" 2>&1 || milestone_stage_result=$?
        if [[ "$ui_stage_result" != 0 || "$process_stage_result" != 0 || \
              "$geometry_stage_result" != 0 || "$milestone_stage_result" != 0 ]]; then
            # Preserve the same read-only timeline for any failed acceptance
            # gate, including failures detected only by a post-UI evidence check.
            collect_height_service_log "$label-host-full-process" 'process == "freeshiamy-ios"' \
                "$ARTIFACTS/$label-stage-start.txt"
            collect_height_service_log "$label-service-launch" \
                'subsystem CONTAINS[c] "PlugInKit" OR subsystem CONTAINS[c] "ExtensionKit" OR subsystem CONTAINS[c] "RunningBoard" OR subsystem CONTAINS[c] "LaunchServices" OR process == "pkd" OR process == "runningboardd" OR process == "lsd" OR process == "launchd" OR eventMessage CONTAINS "osku.me.freeshiamyios.keyboard"' \
                "$ARTIFACTS/$label-stage-start.txt"
            collect_height_service_log "$label-install-registration" \
                'process == "installd" OR subsystem CONTAINS[c] "MobileInstallation" OR ((eventMessage CONTAINS "osku.me.freeshiamyios") AND (eventMessage CONTAINS[c] "install" OR eventMessage CONTAINS[c] "register" OR eventMessage CONTAINS[c] "registration"))' \
                "$ARTIFACTS/$label-stage-start.txt"
            collect_runner_host_launch_log "$label-runner-host-launch" \
                "$ARTIFACTS/$label-stage-start.txt" "$ARTIFACTS/$label-stage-end.txt"
        fi
    else
        echo '[stage] Height installed scenario skipped because public trait readback failed' \
            | tee "$ARTIFACTS/$label-skipped.log"
    fi
    printf -v "${prefix}_content_size_result" '%s' "$content_result"
    printf -v "${prefix}_appearance_result" '%s' "$appearance_result"
    printf -v "${prefix}_ui_result" '%s' "$ui_stage_result"
    printf -v "${prefix}_process_result" '%s' "$process_stage_result"
    printf -v "${prefix}_host_geometry_result" '%s' "$geometry_stage_result"
    printf -v "${prefix}_milestone_result" '%s' "$milestone_stage_result"
}

selected_height_content_size_result=skipped
selected_height_appearance_result=skipped
selected_height_ui_result=skipped
selected_height_process_result=skipped
selected_height_host_geometry_result=skipped
selected_height_milestone_result=skipped
if [[ "$focused_result" == 0 && "$hosted_result" == 0 && "$plist_result" == 0 && \
      "$ui_result" == 0 && "$host_geometry_result" == 0 && "$process_result" == 0 && \
      "$ax_content_size_result" == 0 && "$ax_result" == 0 && "$ax_process_result" == 0 ]]; then
    if [[ "$HEIGHT_ENDPOINT" == 90 ]]; then
        run_height_stage installed-height-xs90 testInstalledHeight90ExtraSmallLight \
            90 UICTContentSizeCategoryXS extra-small light selected_height
    else
        run_height_stage installed-height-ax220 testInstalledHeight220AccessibilityDark \
            220 UICTContentSizeCategoryAccessibilityXXXL accessibility-extra-extra-extra-large dark selected_height
    fi
else
    echo "[stage] Selected height ${HEIGHT_ENDPOINT}% skipped because baseline acceptance gates did not all succeed" \
        | tee "$ARTIFACTS/installed-height-selected-skipped.log"
fi

# Missing unified-log evidence blocks a completed installed-extension claim for
# this first run. Classify that as inconclusive integration evidence, not a
# demonstrated keyboard product failure; retained UI evidence diagnoses it.
printf 'hosted-focused=%s\nbuilt-simulator-identity=%s\nhosted-full=%s\nplist=%s\ninstalled-extension=%s\ninstalled-simulator-identity=%s\ninstalled-host-geometry=%s\nprocess-log=%s\ninstalled-ax-content-size=%s\ninstalled-ax=%s\ninstalled-ax-process=%s\n' \
    "$focused_result" "$built_identity_result" "$hosted_result" "$plist_result" "$ui_result" "$installed_identity_result" "$host_geometry_result" "$process_observation" \
    "$ax_content_size_result" "$ax_result" "$ax_process_result" | tee "$ARTIFACTS/stage-status.txt"
printf 'selected-height-endpoint=%s\nunselected-height-endpoint=%s\nunselected-height-status=not-run/pending\nselected-height-content-size=%s\nselected-height-appearance=%s\nselected-height-ui=%s\nselected-height-process=%s\nselected-height-host-geometry=%s\nselected-height-milestones=%s\n' \
    "$HEIGHT_ENDPOINT" "$UNSELECTED_HEIGHT_ENDPOINT" \
    "$selected_height_content_size_result" "$selected_height_appearance_result" "$selected_height_ui_result" \
    "$selected_height_process_result" "$selected_height_host_geometry_result" "$selected_height_milestone_result" \
    | tee -a "$ARTIFACTS/stage-status.txt"
if [[ "$focused_result" != 0 || "$built_identity_result" != 0 || "$hosted_result" != 0 || "$plist_result" != 0 || "$ui_result" != 0 || "$installed_identity_result" != 0 || "$host_geometry_result" != 0 || "$process_result" != 0 || "$ax_content_size_result" != 0 || "$ax_result" != 0 || "$ax_process_result" != 0 || \
      "$selected_height_content_size_result" != 0 || "$selected_height_appearance_result" != 0 || "$selected_height_ui_result" != 0 || "$selected_height_process_result" != 0 || "$selected_height_host_geometry_result" != 0 || "$selected_height_milestone_result" != 0 ]]; then exit 1; fi
