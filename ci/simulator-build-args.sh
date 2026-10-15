#!/usr/bin/env bash
# CI builds only for arm64 iOS Simulator, with ad-hoc signing so declared
# app-group entitlements can be embedded in the Simulator-effective executable.
FSH_CI_SIMULATOR_BUILD_ARGS=(
    -sdk iphonesimulator
    ARCHS=arm64
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGN_IDENTITY=-
)

fsh_validate_simulator_destination() {
    local destination="$1"
    if [[ "$destination" == 'generic/platform=iOS Simulator' ]] || \
       [[ "$destination" =~ ^platform=iOS\ Simulator,id=[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
        return 0
    fi
    printf 'Refusing non-Simulator or invalid destination: %s\n' "$destination" >&2
    return 1
}
