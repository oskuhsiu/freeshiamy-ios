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

# The repository intentionally does not track a developer's signing overrides.
touch Config/Local.xcconfig
xcodebuild -list -project freeshiamy-ios.xcodeproj > "$ARTIFACTS/project-list.log" 2>&1
xcodebuild -help > "$ARTIFACTS/xcodebuild-help.log" 2>&1
if ! grep -q -- '-testLanguage' "$ARTIFACTS/xcodebuild-help.log" || \
   ! grep -q -- '-testRegion' "$ARTIFACTS/xcodebuild-help.log"; then
    echo "Xcode 26.2 does not list the test language/region options" | tee "$ARTIFACTS/test-locale-preflight.log"
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

DEVICE_ID=$(xcrun simctl create "freeshiamy-ci-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$RUNTIME")
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
    local label="$1" scheme="$2" result=0
    echo "[stage] $label on $DEVICE_ID"
    xcodebuild test \
        -project freeshiamy-ios.xcodeproj \
        -scheme "$scheme" \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$DEVICE_ID" \
        -testLanguage en \
        -testRegion US \
        -parallel-testing-enabled NO \
        -derivedDataPath "$TEMP_ROOT/freeshiamy-derived-data" \
        -resultBundlePath "$ARTIFACTS/$label.xcresult" \
        CODE_SIGNING_ALLOWED=NO \
        > "$ARTIFACTS/$label-xcodebuild.log" 2>&1 || result=$?
    echo "[stage] $label xcodebuild exit status $result"
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

hosted_result=0
run_stage hosted freeshiamy-ios || hosted_result=$?

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
run_stage installed-extension InstalledKeyboardSmoke || ui_result=$?
# Collect extension process diagnostics even when the first UI boundary fails.
xcrun simctl spawn "$DEVICE_ID" log show --last 30m --style compact --info --debug \
    --predicate 'process == "FreeShiamyKeyboard" OR eventMessage CONTAINS "FreeShiamyKeyboard lifecycle"' \
    > "$ARTIFACTS/installed-extension-process.log" 2>&1 || true
process_observation=missing-inconclusive
process_result=1
if grep -Eq "FreeShiamyKeyboard lifecycle bundle=osku.me.freeshiamyios.keyboard pid=[0-9]+ hasFullAccess=NO" "$ARTIFACTS/installed-extension-process.log"; then
    process_observation=observed-no-full-access
    process_result=0
fi
# Missing unified-log evidence blocks a completed installed-extension claim for
# this first run. Classify that as inconclusive integration evidence, not a
# demonstrated keyboard product failure; retained UI evidence diagnoses it.
printf 'hosted=%s\nplist=%s\ninstalled-extension=%s\nprocess-log=%s\n' "$hosted_result" "$plist_result" "$ui_result" "$process_observation" | tee "$ARTIFACTS/stage-status.txt"
if [[ "$hosted_result" != 0 || "$plist_result" != 0 || "$ui_result" != 0 || "$process_result" != 0 ]]; then exit 1; fi
