#!/usr/bin/env bash
# Build-only, arm64 iOS Simulator ad-hoc signing proof. No boot, install, or tests.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
source ci/simulator-build-args.sh

destination='generic/platform=iOS Simulator'
fsh_validate_simulator_destination "$destination"
output="${GITHUB_WORKSPACE:-$PWD}/ci-artifacts/simulator-build-identity"
if [[ -e "$output" ]]; then
    echo "Refusing to overwrite previous build evidence: $output" >&2
    exit 1
fi
mkdir -p "$output"
result=0
trap 'rc=$?; if [[ "$rc" != 0 ]]; then result=$rc; fi; printf "build_identity_exit_status=%s\n" "$result" > "$output/status.txt"' EXIT

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 || "$(sw_vers -productVersion)" != 15.* ]] || \
   [[ ! -d "$DEVELOPER_DIR" ]] || [[ "$(xcodebuild -version | head -n 1)" != 'Xcode 26.2' ]]; then
    echo 'Requires macOS 15 arm64 with Xcode 26.2' >&2
    result=1; exit "$result"
fi
if [[ -e Config/Local.xcconfig ]]; then
    echo 'Refusing nonempty local signing override file in CI identity proof' >&2
    result=1; exit "$result"
fi
touch Config/Local.xcconfig
{
    printf 'source_sha=%s\n' "$(git rev-parse HEAD)"
    printf 'destination=%s\n' "$destination"
    printf 'shared_build_args='
    printf '%q ' "${FSH_CI_SIMULATOR_BUILD_ARGS[@]}"
    printf '\n'
    sw_vers
    uname -m
    xcodebuild -version
    xcrun --sdk iphonesimulator --show-sdk-version
} > "$output/preflight.log" 2>&1 || { result=1; exit "$result"; }
xcodebuild -showdestinations -project freeshiamy-ios.xcodeproj -scheme InstalledKeyboardSmoke \
    > "$output/show-destinations.log" 2>&1 || { result=1; exit "$result"; }

derived="${RUNNER_TEMP:-/tmp}/fsh-simulator-identity-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
if [[ -e "$derived" ]]; then
    echo "Refusing reused DerivedData: $derived" >&2
    result=1; exit "$result"
fi
printf 'owned_derived_data=%s\n' "$derived" >> "$output/preflight.log"
xcodebuild -showBuildSettings -json -project freeshiamy-ios.xcodeproj \
    -scheme InstalledKeyboardSmoke -configuration Debug -destination "$destination" \
    "${FSH_CI_SIMULATOR_BUILD_ARGS[@]}" \
    > "$output/build-settings.json" 2> "$output/build-settings.stderr" \
    || { result=1; exit "$result"; }

set +e
xcodebuild build-for-testing -project freeshiamy-ios.xcodeproj \
    -scheme InstalledKeyboardSmoke -configuration Debug -destination "$destination" \
    -derivedDataPath "$derived" "${FSH_CI_SIMULATOR_BUILD_ARGS[@]}" \
    2>&1 | tee "$output/xcodebuild-build-for-testing.log"
pipeline_status=("${PIPESTATUS[@]}")
build_status=${pipeline_status[0]}
tee_status=${pipeline_status[1]}
set -e
printf 'xcodebuild_status=%s\ntee_status=%s\n' "$build_status" "$tee_status" > "$output/build-command-status.txt"
if [[ "$build_status" != 0 || "$tee_status" != 0 ]]; then
    result=1; exit "$result"
fi

app="$derived/Build/Products/Debug-iphonesimulator/freeshiamy-ios.app"
extension="$app/PlugIns/FreeShiamyKeyboard.appex"
app_executable="$app/freeshiamy-ios"
extension_executable="$extension/FreeShiamyKeyboard"
if ! python3 - "$app" "$extension" > "$output/bundle-identities.json" 2> "$output/bundle-identities.stderr" <<'PY'
import hashlib, json, pathlib, plistlib, sys
bundles = [
    (pathlib.Path(sys.argv[1]), 'osku.me.freeshiamyios', 'freeshiamy-ios'),
    (pathlib.Path(sys.argv[2]), 'osku.me.freeshiamyios.keyboard', 'FreeShiamyKeyboard'),
]
records = []
for bundle, identifier, executable_name in bundles:
    plist_path = bundle / 'Info.plist'
    plist = plistlib.loads(plist_path.read_bytes())
    if plist.get('CFBundleIdentifier') != identifier or plist.get('CFBundleExecutable') != executable_name:
        raise SystemExit(f'Wrong built bundle identity: {bundle}')
    executable = bundle / executable_name
    if not executable.is_file():
        raise SystemExit(f'Built executable missing: {executable}')
    records.append({'bundle': str(bundle), 'bundleId': identifier,
                    'infoPlistSha256': hashlib.sha256(plist_path.read_bytes()).hexdigest(),
                    'executable': str(executable),
                    'executableSha256': hashlib.sha256(executable.read_bytes()).hexdigest()})
print(json.dumps(records, indent=2))
PY
then
    result=1; exit "$result"
fi

# Retain only the final signed executables and their own bundle metadata so
# the Mach-O claims can be independently reproduced without DerivedData.
python3 - "$app" "$extension" "$output" > "$output/retained-products.json" \
    2> "$output/retained-products.stderr" <<'PY' || { result=1; exit "$result"; }
import hashlib, json, pathlib, shutil, sys
app, extension, output = map(pathlib.Path, sys.argv[1:])
records = []
for label, bundle, executable in (
        ('app', app, 'freeshiamy-ios'),
        ('keyboard-extension', extension, 'FreeShiamyKeyboard')):
    target = output / 'products' / label
    target.mkdir(parents=True)
    for filename in ('Info.plist', executable):
        source = bundle / filename
        destination = target / filename
        if not source.is_file() or source.is_symlink():
            raise SystemExit(f'Missing regular final product: {source}')
        shutil.copyfile(source, destination)
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        retained_hash = hashlib.sha256(destination.read_bytes()).hexdigest()
        if source_hash != retained_hash:
            raise SystemExit(f'Retained product differs from final product: {source}')
        records.append({'source': str(source), 'retained': str(destination),
                        'bytes': source.stat().st_size, 'sha256': source_hash})
print(json.dumps(records, indent=2))
PY

for entry in "app|$app|$app_executable|freeshiamy-ios/freeshiamy-ios.entitlements" \
             "keyboard-extension|$extension|$extension_executable|FreeShiamyKeyboard/FreeShiamyKeyboard.entitlements"; do
    IFS='|' read -r label bundle executable source_entitlements <<< "$entry"
    mkdir -p "$output/$label"
    shasum -a 256 "$source_entitlements" "$executable" \
        > "$output/$label/source-and-executable-sha256.txt" 2>&1 || result=1
    codesign --display --verbose=4 "$bundle" > "$output/$label/codesign-display.log" 2>&1 \
        || result=1
    codesign --verify --strict --verbose=4 "$bundle" > "$output/$label/codesign-verify.log" 2>&1 \
        || result=1
    if ! grep -qx 'Signature=adhoc' "$output/$label/codesign-display.log"; then
        echo 'Expected ad-hoc signature is missing' >> "$output/$label/codesign-verify.log"
        result=1
    fi
    # Ordinary codesign entitlements are diagnostic only. The app/extension
    # acceptance gate is the Simulator-effective Mach-O section below.
    ordinary_status=0
    codesign --display --entitlements :- "$bundle" \
        > "$output/$label/codesign-ordinary-entitlements.plist" \
        2> "$output/$label/codesign-ordinary-entitlements.stderr" || ordinary_status=$?
    printf 'ordinary_entitlements_display_status=%s\n' "$ordinary_status" \
        > "$output/$label/codesign-ordinary-entitlements-status.txt"
    python3 ci/check-simulator-effective-entitlements.py "$executable" "$source_entitlements" \
        "$output/$label" > "$output/$label/effective-check.log" 2>&1 || result=1
done

python3 - "$derived" "$output" > "$output/signing-intermediates-manifest.json" \
    2> "$output/signing-intermediates.stderr" <<'PY' || result=1
import hashlib, json, pathlib, shutil, sys
root, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
source = root / 'Build' / 'Intermediates.noindex'
target = output / 'signing-intermediates'
target.mkdir()
records = []
for path in sorted(source.rglob('*')):
    if not path.is_file() or path.is_symlink():
        continue
    lower = path.name.lower()
    if not (lower.endswith('.xcent') or lower.endswith('.xcent.der') or
            'entitlement' in lower and lower.endswith(('.plist', '.der'))):
        continue
    relative = path.relative_to(source)
    destination = target / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, destination)
    records.append({'path': str(relative), 'bytes': path.stat().st_size,
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
print(json.dumps({'source': str(source), 'files': records,
                  'missing': 'no signing intermediates found' if not records else None}, indent=2))
PY
printf 'result=%s\n' "$result" > "$output/identity-result.txt"
exit "$result"
