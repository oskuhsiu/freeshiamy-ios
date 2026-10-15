#!/usr/bin/env bash
# Decode two already-retained run-21 failures; never boot, build or rerun tests.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
output="${1:-${GITHUB_WORKSPACE:-$PWD}/ci-artifacts/run21-decode}"
if [[ -e "$output" ]]; then
    echo "Refusing to overwrite prior evidence: $output" >&2
    exit 1
fi
mkdir -p "$output"
overall=0
trap 'rc=$?; if [[ "$rc" != 0 ]]; then overall=$rc; fi; printf "decoder_exit_status=%s\n" "$overall" > "$output/decoder-status.txt"' EXIT

if [[ "$(uname -s)" != Darwin ]] || [[ "$(sw_vers -productVersion)" != 15.* ]] || \
   [[ "$(uname -m)" != arm64 ]]; then
    echo 'Requires macOS 15 arm64 for retained unified-log decoding' >&2
    overall=1; exit "$overall"
fi
if [[ ! -d "$DEVELOPER_DIR" ]] || [[ "$(xcodebuild -version | head -n 1)" != 'Xcode 26.2' ]]; then
    echo 'Requires installed Xcode 26.2' >&2
    overall=1; exit "$overall"
fi
{
    sw_vers
    uname -a
    xcodebuild -version
    xcrun xcresulttool version
} > "$output/tool-versions.txt" 2>&1 || { overall=1; exit "$overall"; }
if xcrun xcresulttool export diagnostics --help > "$output/xcresulttool-diagnostics-help.txt" 2>&1; then
    xcresult_help_status=0
else
    xcresult_help_status=$?
fi
if log help show > "$output/log-show-help.txt" 2>&1; then
    log_help_status=0
else
    log_help_status=$?
fi
printf 'xcresulttool_diagnostics_help_status=%s\nlog_show_help_status=%s\n' \
    "$xcresult_help_status" "$log_help_status" > "$output/help-exit-status.txt"
cat "$output/tool-versions.txt" "$output/xcresulttool-diagnostics-help.txt" \
    "$output/log-show-help.txt" > "$output/tool-versions-and-help.txt" \
    || { overall=1; exit "$overall"; }
if ! python3 ci/check-run21-decode-help.py \
    "$output/help-exit-status.txt" "$output/xcresulttool-diagnostics-help.txt" \
    "$output/log-show-help.txt" > "$output/help-validation.txt" 2>&1; then
    echo 'Required retained-decoder help usage/options missing or unexpected exit status' >&2
    overall=1; exit "$overall"
fi
python3 ci/count-run21-log-events.py --self-test > "$output/compact-event-counter-selftest.txt" 2>&1 \
    || { overall=1; exit "$overall"; }
if [[ -z "${FSH_RUN21_LOCAL_EVIDENCE:-}" ]]; then
    if [[ -z "${GITHUB_TOKEN:-}" ]] || ! command -v gh >/dev/null; then
        echo 'GITHUB_TOKEN and gh are required to read the two pinned artifacts' >&2
        overall=1; exit "$overall"
    fi
    export GH_TOKEN="$GITHUB_TOKEN"
fi

fail_case() {
    printf 'status=failed reason=%s\n' "$2" >> "$1/case-status.txt"
    echo "$2" >&2
    return 1
}

decode_case() {
    local key="$1" id="$2" stage="$3" start="$4" end="$5"
    local case_dir="$output/$key" archive decoded error index=0 bad=0
    case_dir="$output/$key"
    mkdir "$case_dir" || return 1
    printf 'status=started case=%s artifact=%s stage=%s\n' "$key" "$id" "$stage" > "$case_dir/case-status.txt"
    if [[ -n "${FSH_RUN21_LOCAL_EVIDENCE:-}" ]]; then
        cp "$FSH_RUN21_LOCAL_EVIDENCE/run-final.json" "$case_dir/source-run.json" || fail_case "$case_dir" 'local run metadata missing' || return 1
        cp "$FSH_RUN21_LOCAL_EVIDENCE/artifacts-final.json" "$case_dir/source-artifact.json" || fail_case "$case_dir" 'local artifact metadata missing' || return 1
        local local_zip
        case "$key" in
            ipad90) local_zip=ipad-90.zip ;;
            iphone220) local_zip=iphone-220.zip ;;
            *) fail_case "$case_dir" 'unknown retained case'; return 1 ;;
        esac
        cp "$FSH_RUN21_LOCAL_EVIDENCE/$local_zip" "$case_dir/raw-artifact-$id.zip" \
            || { fail_case "$case_dir" 'local ZIP missing'; return 1; }
    else
        gh api repos/oskuhsiu/freeshiamy-ios/actions/runs/38660719039 > "$case_dir/source-run.json" \
            || { fail_case "$case_dir" 'GitHub run metadata request failed'; return 1; }
        gh api "repos/oskuhsiu/freeshiamy-ios/actions/artifacts/$id" > "$case_dir/source-artifact.json" \
            || { fail_case "$case_dir" 'GitHub artifact metadata request failed'; return 1; }
        gh api "repos/oskuhsiu/freeshiamy-ios/actions/artifacts/$id/zip" > "$case_dir/raw-artifact-$id.zip" \
            || { fail_case "$case_dir" 'GitHub artifact ZIP request failed'; return 1; }
    fi
    python3 ci/decode-run21-evidence.py "$key" "$case_dir/source-run.json" \
        "$case_dir/source-artifact.json" "$case_dir/raw-artifact-$id.zip" "$case_dir" \
        > "$case_dir/verification.log" 2>&1 \
        || { fail_case "$case_dir" 'artifact metadata, digest or bundle verification failed'; return 1; }
    # The source ZIP remains at its pinned GitHub artifact ID. Keep verified
    # metadata/digest and extracted evidence without reuploading that ZIP.
    rm "$case_dir/raw-artifact-$id.zip" \
        || { fail_case "$case_dir" 'temporary ZIP cleanup failed'; return 1; }

    xcrun xcresulttool export diagnostics --path "$case_dir/extracted/$stage.xcresult" \
        --output-path "$case_dir/diagnostics" \
        > "$case_dir/diagnostics-export.log" 2>&1 \
        || { fail_case "$case_dir" 'xcresulttool diagnostics export failed'; return 1; }
    xcrun xcresulttool get content-availability --path "$case_dir/extracted/$stage.xcresult" \
        > "$case_dir/xcresult-content-availability.json" 2> "$case_dir/xcresult-content-availability.stderr" \
        || { fail_case "$case_dir" 'xcresulttool content-availability failed'; return 1; }
    xcrun xcresulttool get test-results summary --path "$case_dir/extracted/$stage.xcresult" \
        > "$case_dir/xcresult-test-summary.json" 2> "$case_dir/xcresult-test-summary.stderr" \
        || { fail_case "$case_dir" 'xcresulttool test summary failed'; return 1; }
    if ! xcrun xcresulttool get log --type console --path "$case_dir/extracted/$stage.xcresult" \
        > "$case_dir/xctest-console.json" 2> "$case_dir/xctest-console.stderr"; then
        printf 'diagnostic_missing=xctest-console-export\n' >> "$case_dir/case-status.txt"
        bad=1
    fi

    # Keep the full exported diagnostics and session text. No process filter is
    # applied: host-macOS launch and preferences events matter here.
    find "$case_dir/diagnostics" -type f | sort > "$case_dir/diagnostic-files.txt" \
        || { fail_case "$case_dir" 'diagnostic inventory failed'; return 1; }
    find "$case_dir/diagnostics" -type f \( -iname '*session*.txt' -o -iname '*session*.log' -o -iname '*StandardOutputAndStandardError*' -o -iname '*xctest*.log' \) \
        | sort > "$case_dir/xctest-session-text-paths.txt" \
        || { fail_case "$case_dir" 'XCTest session inventory failed'; return 1; }
    if ! python3 - "$case_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
with (root / 'xctest-session-text.txt').open('wb') as combined:
    for line in (root / 'xctest-session-text-paths.txt').read_text().splitlines():
        path = Path(line)
        combined.write(('\n===== ' + str(path.relative_to(root)) + ' =====\n').encode())
        combined.write(path.read_bytes())
        combined.write(b'\n')
PY
    then
        fail_case "$case_dir" 'XCTest session concatenation failed'
        return 1
    fi
    if [[ ! -s "$case_dir/xctest-session-text.txt" ]]; then
        printf 'diagnostic_missing=xctest-session-text\n' >> "$case_dir/case-status.txt"
        bad=1
    fi

    mkdir "$case_dir/decoded-logs" || { fail_case "$case_dir" 'decoded-log directory creation failed'; return 1; }
    find "$case_dir/diagnostics" -type d -name '*.logarchive' -print0 \
        > "$case_dir/logarchive-paths.nul" \
        || { fail_case "$case_dir" 'logarchive inventory failed'; return 1; }
    printf 'Timezone=UTC; start=%s+0000; end_exclusive=%s+0000; no process predicate\n' "$start" "$end" \
        > "$case_dir/logarchive-status.txt"
    while IFS= read -r -d '' archive; do
        index=$((index + 1))
        printf '%s\t%s\n' "$index" "${archive#"$case_dir"/}" >> "$case_dir/logarchive-status.txt"
        decoded="$case_dir/decoded-logs/archive-${index}-all-processes.log"
        error="$case_dir/decoded-logs/archive-${index}-stderr.log"
        if log show --info --debug \
            --timezone UTC --style compact --start "${start}+0000" --end "${end}+0000" \
            "$archive" \
            > "$decoded" 2> "$error"; then
            if python3 ci/count-run21-log-events.py "$decoded" "${start}+0000" "${end}+0000" \
                > "$case_dir/decoded-logs/archive-${index}-event-count.txt" 2> "$case_dir/decoded-logs/archive-${index}-count-stderr.txt"; then
                printf 'archive=%s status=decoded %s\n' "$index" \
                    "$(cat "$case_dir/decoded-logs/archive-${index}-event-count.txt")" \
                    >> "$case_dir/logarchive-status.txt"
            else
                printf 'archive=%s status=no-verified-timestamped-compact-events\n' "$index" >> "$case_dir/logarchive-status.txt"
                bad=1
            fi
        else
            printf 'archive=%s status=decode-error\n' "$index" >> "$case_dir/logarchive-status.txt"
            bad=1
        fi
    done < "$case_dir/logarchive-paths.nul"
    if [[ "$index" == 0 ]]; then
        printf 'diagnostic_missing=no exported .logarchive directory found\n' >> "$case_dir/logarchive-status.txt"
        bad=1
    fi
    if [[ "$bad" != 0 ]]; then
        fail_case "$case_dir" 'one or more retained diagnostics missing, empty or undecodable'
        return 1
    fi
    printf 'status=decoded-diagnostic-only; no test or acceptance claim\n' >> "$case_dir/case-status.txt"
}

# Each case is independent: a failed first decode cannot silently complete or
# prevent the second retained case from being investigated.
decode_case ipad90 11938853295 installed-adaptive-ax \
    '2026-10-15 00:43:12' '2026-10-15 00:44:46' || overall=1
decode_case iphone220 11939791339 installed-height-ax220 \
    '2026-10-15 00:48:35' '2026-10-15 00:50:36' || overall=1
printf 'Diagnostic-only operation; no simulator, build, test rerun or acceptance assertion.\n' \
    > "$output/READ-ME-FIRST.txt"
exit "$overall"
