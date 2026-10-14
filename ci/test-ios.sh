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

set +e
echo "[stage] xcodebuild test on $DEVICE_ID"
xcodebuild test \
    -project freeshiamy-ios.xcodeproj \
    -scheme freeshiamy-ios \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" \
    -parallel-testing-enabled NO \
    -derivedDataPath "$TEMP_ROOT/freeshiamy-derived-data" \
    -resultBundlePath "$ARTIFACTS/test.xcresult" \
    CODE_SIGNING_ALLOWED=NO \
    > "$ARTIFACTS/xcodebuild.log" 2>&1
result=$?
set -e

echo "[stage] xcodebuild exit status $result"
xcrun simctl io "$DEVICE_ID" screenshot "$ARTIFACTS/simulator-final.png" || true
tail -n 120 "$ARTIFACTS/xcodebuild.log"
exit "$result"
