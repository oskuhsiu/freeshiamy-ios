#!/usr/bin/env bash
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
ARTIFACTS="${GITHUB_WORKSPACE:-$PWD}/ci-artifacts"
TEMP_ROOT="${RUNNER_TEMP:-/tmp}"
mkdir -p "$ARTIFACTS"
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

DEVICE_ID=$(xcrun simctl create "freeshiamy-ci-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-${DEVICE_LABEL}" \
    "$DEVICE_TYPE" "$RUNTIME")
echo "Job-owned simulator: $DEVICE_ID; type: $DEVICE_TYPE; runtime: $RUNTIME" | tee -a "$ARTIFACTS/device-selection.log"
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
    echo "[stage] $label on $DEVICE_ID"
    set +e
    xcodebuild test \
        -project freeshiamy-ios.xcodeproj \
        -scheme "$scheme" \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$DEVICE_ID" \
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
        CODE_SIGNING_ALLOWED=NO \
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

focused_result=0
run_stage hosted-focused freeshiamy-ios 120 180 \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testAXCompactAlternateTypographySettlesAcrossRepeatedLayouts' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testAttachedHostHeightAndDynamicTypeAdaptWithoutRebuildingComposition' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testCandidateAccessibilityDescribesCodeExactnessAndRealShortcutsAcrossContexts' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testHostActionTitlesWrapInAttachedAccessibilityViewport' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testHostPanelScrollsFocusedFieldsAboveSceneBackedKeyboard' \
    '-only-testing:KeyboardInputTests/KeyboardInputTests/testHostCodeSearchRendersInAttachedWindow' \
    || focused_result=$?
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
    fi
else
    echo '[stage] Installed AX/More test skipped because default installed smoke or evidence failed' \
        | tee "$ARTIFACTS/installed-ax-skipped.log"
fi
# Missing unified-log evidence blocks a completed installed-extension claim for
# this first run. Classify that as inconclusive integration evidence, not a
# demonstrated keyboard product failure; retained UI evidence diagnoses it.
printf 'hosted-focused=%s\nhosted-full=%s\nplist=%s\ninstalled-extension=%s\ninstalled-host-geometry=%s\nprocess-log=%s\ninstalled-ax-content-size=%s\ninstalled-ax=%s\ninstalled-ax-process=%s\n' \
    "$focused_result" "$hosted_result" "$plist_result" "$ui_result" "$host_geometry_result" "$process_observation" \
    "$ax_content_size_result" "$ax_result" "$ax_process_result" | tee "$ARTIFACTS/stage-status.txt"
if [[ "$focused_result" != 0 || "$hosted_result" != 0 || "$plist_result" != 0 || "$ui_result" != 0 || "$host_geometry_result" != 0 || "$process_result" != 0 || "$ax_content_size_result" != 0 || "$ax_result" != 0 || "$ax_process_result" != 0 ]]; then exit 1; fi
