#!/usr/bin/env bash
# Export and decode one SHA-pinned failed run-26 xcresult; no Simulator or test.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
output="${1:-${GITHUB_WORKSPACE:-$PWD}/ci-artifacts/run26-activation-decode}"
if [[ -e "$output" ]]; then
    echo "Refusing to overwrite previous evidence: $output" >&2
    exit 1
fi
mkdir -p "$output"
overall=0
trap 'rc=$?; if [[ "$rc" != 0 ]]; then overall=$rc; fi; printf "decoder_exit_status=%s\n" "$overall" > "$output/decoder-status.txt"' EXIT

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 || "$(sw_vers -productVersion)" != 15.* ]] || \
   [[ ! -d "$DEVELOPER_DIR" ]] || [[ "$(xcodebuild -version | head -n 1)" != 'Xcode 26.2' ]]; then
    echo 'Requires macOS 15 arm64 with Xcode 26.2' >&2
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
python3 ci/check-run21-decode-help.py "$output/help-exit-status.txt" \
    "$output/xcresulttool-diagnostics-help.txt" "$output/log-show-help.txt" \
    > "$output/help-validation.txt" 2>&1 || { overall=1; exit "$overall"; }
python3 ci/count-run21-log-events.py --self-test > "$output/compact-event-counter-selftest.txt" 2>&1 \
    || { overall=1; exit "$overall"; }
python3 ci/decode-run26-evidence.py --self-test > "$output/zip-guard-selftest.txt" 2>&1 \
    || { overall=1; exit "$overall"; }
if [[ -z "${GITHUB_TOKEN:-}" ]] || ! command -v gh >/dev/null; then
    echo 'GITHUB_TOKEN and gh are required for the pinned retained artifact' >&2
    overall=1; exit "$overall"
fi
export GH_TOKEN="$GITHUB_TOKEN"

printf 'Retained run-26 diagnostics only; no Simulator, build, install, test or acceptance assertion.\n' \
    > "$output/READ-ME-FIRST.txt"

fail_case() {
    local case_dir="$1" reason="$2"
    printf 'status=failed reason=%s\n' "$reason" >> "$case_dir/case-status.txt"
    printf '%s\n' "$reason" >&2
    return 1
}

console_is_expected_absence() {
    python3 - "$1" "$2" <<'PY'
import json, sys
from pathlib import Path
stderr = Path(sys.argv[1]).read_text()
if stderr.strip() != 'Error: No console log available':
    raise SystemExit('Console stderr contains other errors or is not the known absence message')
with open(sys.argv[2]) as source:
    data = json.load(source)
logs = data.get('logs')
if not isinstance(logs, list) or 'console' in logs:
    raise SystemExit('Console availability did not confirm omission')
PY
}

decode_case() {
    local key="$1" id="$2" stage="$3" start="$4" end="$5"
    local case_dir="$output/$key" zip xcresult console_status=0 bad=0
    local archive relative scope decoded error decode_status count_status
    local archive_index=0 simulator_count=0 runner_host_count=0 unknown_count=0
    local -a command
    mkdir "$case_dir" || return 1
    printf 'status=started case=%s run=38668884961 attempt=1 artifact=%s stage=%s\n' \
        "$key" "$id" "$stage" > "$case_dir/case-status.txt" || return 1
    zip="$case_dir/raw-artifact-$id.zip"
    gh api repos/oskuhsiu/freeshiamy-ios/actions/runs/38668884961 \
        > "$case_dir/source-run.json" || { fail_case "$case_dir" 'GitHub run metadata request failed'; return 1; }
    gh api "repos/oskuhsiu/freeshiamy-ios/actions/artifacts/$id" \
        > "$case_dir/source-artifact.json" || { fail_case "$case_dir" 'GitHub artifact metadata request failed'; return 1; }
    gh api "repos/oskuhsiu/freeshiamy-ios/actions/artifacts/$id/zip" \
        > "$zip" || { fail_case "$case_dir" 'GitHub artifact ZIP request failed'; return 1; }
    python3 ci/decode-run26-evidence.py "$key" "$case_dir/source-run.json" \
        "$case_dir/source-artifact.json" "$zip" "$case_dir" \
        > "$case_dir/verification.log" 2>&1 \
        || { fail_case "$case_dir" 'pinned metadata, ZIP digest or target xcresult verification failed'; return 1; }
    # The immutable pinned GitHub artifact retains the raw source ZIP; the
    # verified-source receipt records its digest without reuploading ~300 MB.
    rm "$zip" || { fail_case "$case_dir" 'temporary ZIP cleanup failed'; return 1; }

    xcresult="$case_dir/extracted/$stage.xcresult"
    xcrun xcresulttool export diagnostics --path "$xcresult" --output-path "$case_dir/diagnostics" \
        > "$case_dir/diagnostics-export.log" 2>&1 \
        || { fail_case "$case_dir" 'xcresulttool diagnostics export failed'; return 1; }
    xcrun xcresulttool get content-availability --path "$xcresult" \
        > "$case_dir/xcresult-content-availability.json" \
        2> "$case_dir/xcresult-content-availability.stderr" \
        || { printf 'diagnostic_error=xcresult-content-availability\n' >> "$case_dir/case-status.txt"; bad=1; }
    xcrun xcresulttool get test-results summary --path "$xcresult" \
        > "$case_dir/xcresult-test-summary.json" 2> "$case_dir/xcresult-test-summary.stderr" \
        || { printf 'diagnostic_error=xcresult-test-summary\n' >> "$case_dir/case-status.txt"; bad=1; }

    xcrun xcresulttool get log --type console --path "$xcresult" \
        > "$case_dir/xctest-console.json" 2> "$case_dir/xctest-console.stderr" || console_status=$?
    if [[ "$console_status" == 0 && -s "$case_dir/xctest-console.json" ]]; then
        printf 'console_export_status=0\nconsole=available\n' > "$case_dir/xctest-console-status.txt" || return 1
    elif [[ "$console_status" != 0 ]] && \
         console_is_expected_absence "$case_dir/xctest-console.stderr" \
             "$case_dir/xcresult-content-availability.json" \
             > "$case_dir/xctest-console-availability-check.log" 2>&1; then
        printf 'console_export_status=%s\nconsole=unavailable-optional (confirmed by xcresulttool stderr and availability)\n' \
            "$console_status" > "$case_dir/xctest-console-status.txt" || return 1
    else
        printf 'console_export_status=%s\nconsole=unexpected-export-error-or-empty\n' \
            "$console_status" > "$case_dir/xctest-console-status.txt" || return 1
        bad=1
    fi

    # Retain the entire exported diagnostics directory and complete session
    # text. The run's own stage log is in extracted/; no process predicate.
    find "$case_dir/diagnostics" -type f | sort > "$case_dir/diagnostic-files.txt" \
        || { fail_case "$case_dir" 'diagnostic inventory failed'; return 1; }
    find "$case_dir/diagnostics" -type d | sort > "$case_dir/diagnostic-directories.txt" \
        || { fail_case "$case_dir" 'diagnostic directory inventory failed'; return 1; }
    find "$case_dir/diagnostics" -type f \
        \( -iname '*session*.txt' -o -iname '*session*.log' -o -iname '*StandardOutputAndStandardError*' -o -iname '*xctest*.log' \) \
        | sort > "$case_dir/xctest-session-text-paths.txt" \
        || { fail_case "$case_dir" 'XCTest session inventory failed'; return 1; }
    if ! python3 - "$case_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
with (root / 'xctest-session-text.txt').open('wb') as combined:
    nonempty_payloads = 0
    for line in (root / 'xctest-session-text-paths.txt').read_text().splitlines():
        path = Path(line)
        payload = path.read_bytes()
        combined.write(('\n===== ' + str(path.relative_to(root)) + ' =====\n').encode())
        combined.write(payload)
        combined.write(b'\n')
        nonempty_payloads += bool(payload)
    if nonempty_payloads == 0:
        raise SystemExit('No nonempty exported XCTest session/stdout payload')
PY
    then
        printf 'diagnostic_error=xctest-session-concatenation\n' >> "$case_dir/case-status.txt"
        bad=1
    elif [[ ! -s "$case_dir/xctest-session-text.txt" ]]; then
        printf 'diagnostic_missing=xctest-session-text\n' >> "$case_dir/case-status.txt"
        bad=1
    fi

    mkdir "$case_dir/decoded-logs" || { fail_case "$case_dir" 'decoded-log directory creation failed'; return 1; }
    find "$case_dir/diagnostics" -type d -name '*.logarchive' -print0 \
        > "$case_dir/logarchive-paths.nul" \
        || { fail_case "$case_dir" 'logarchive inventory failed'; return 1; }
    find "$case_dir/diagnostics" -type f -name hostLaunchd_state.log \
        > "$case_dir/hostLaunchd-static-snapshot-paths.txt" \
        || { fail_case "$case_dir" 'hostLaunchd snapshot inventory failed'; return 1; }
    printf 'timezone=UTC start=%s+0000 end_exclusive=%s+0000 process_predicate=none\n' \
        "$start" "$end" > "$case_dir/logarchive-status.txt" || return 1
    while IFS= read -r -d '' archive; do
        archive_index=$((archive_index + 1))
        relative="${archive#"$case_dir/diagnostics/"}"
        case "/$relative" in
            */simctl_diagnostics/*)
                scope='Simulator unified-log store'; simulator_count=$((simulator_count + 1)) ;;
            */Mac/*|*/host_diagnostics/*|*/macos_diagnostics/*|*/macOS_diagnostics/*)
                scope='runner-host macOS unified-log store'; runner_host_count=$((runner_host_count + 1)) ;;
            *)
                scope='unclassified archive (no host/Simulator source claim)'
                unknown_count=$((unknown_count + 1)); bad=1 ;;
        esac
        decoded="$case_dir/decoded-logs/archive-${archive_index}-all-processes.log"
        error="$case_dir/decoded-logs/archive-${archive_index}-stderr.log"
        printf 'archive=%s path=%s scope=%s\n' "$archive_index" "$relative" "$scope" \
            >> "$case_dir/logarchive-status.txt" || return 1
        command=(log show --info --debug --timezone UTC --style compact \
            --start "${start}+0000" --end "${end}+0000" "$archive")
        printf 'archive=%s command=' "$archive_index" >> "$case_dir/logarchive-status.txt" || return 1
        printf '%q ' "${command[@]}" >> "$case_dir/logarchive-status.txt" || return 1
        printf '\n' >> "$case_dir/logarchive-status.txt" || return 1
        decode_status=0
        "${command[@]}" > "$decoded" 2> "$error" || decode_status=$?
        printf 'archive=%s decode_command_status=%s\n' "$archive_index" "$decode_status" \
            >> "$case_dir/logarchive-status.txt" || return 1
        if [[ "$decode_status" == 0 ]]; then
            count_status=0
            python3 ci/count-run21-log-events.py "$decoded" "${start}+0000" "${end}+0000" \
                > "$case_dir/decoded-logs/archive-${archive_index}-event-count.txt" \
                2> "$case_dir/decoded-logs/archive-${archive_index}-count-stderr.txt" || count_status=$?
            printf 'archive=%s event_count_status=%s ' "$archive_index" "$count_status" \
                >> "$case_dir/logarchive-status.txt" || return 1
            if [[ "$count_status" == 0 ]]; then
                cat "$case_dir/decoded-logs/archive-${archive_index}-event-count.txt" \
                    >> "$case_dir/logarchive-status.txt" || return 1
            else
                printf 'events=unverified\n' >> "$case_dir/logarchive-status.txt" || return 1
                bad=1
            fi
        else
            printf 'archive=%s events=not-counted/decode-error\n' "$archive_index" \
                >> "$case_dir/logarchive-status.txt" || return 1
            bad=1
        fi
    done < "$case_dir/logarchive-paths.nul"
    printf 'archive_inventory=%s simulator_archives=%s runner_host_archives=%s unclassified_archives=%s\n' \
        "$archive_index" "$simulator_count" "$runner_host_count" "$unknown_count" \
        >> "$case_dir/logarchive-status.txt" || return 1
    if [[ "$runner_host_count" == 0 ]]; then
        printf 'runner_host_logarchive=not-exported; hostLaunchd_state.log (if listed) is a static snapshot, not a host event timeline\n' \
            >> "$case_dir/logarchive-status.txt" || return 1
    fi
    if [[ "$key" == ipad90 ]]; then
        if [[ -s "$case_dir/extracted/installed-ax-runner-host-launch.log" ]]; then
            printf 'runner_host_stage_log=extracted/installed-ax-runner-host-launch.log (separate live host log, not a logarchive)\n' \
                >> "$case_dir/logarchive-status.txt" || return 1
        else
            printf 'runner_host_stage_log=missing\n' >> "$case_dir/logarchive-status.txt" || return 1
            bad=1
        fi
    else
        printf 'runner_host_stage_log=not-collected-for-default-installed-stage\n' \
            >> "$case_dir/logarchive-status.txt" || return 1
    fi
    if [[ "$archive_index" == 0 ]]; then
        printf 'diagnostic_missing=no exported .logarchive directory\n' >> "$case_dir/logarchive-status.txt" || return 1
        bad=1
    fi
    if [[ "$simulator_count" == 0 ]]; then
        printf 'diagnostic_missing=no Simulator-scoped .logarchive directory\n' \
            >> "$case_dir/logarchive-status.txt" || return 1
        bad=1
    fi
    if [[ "$bad" != 0 ]]; then
        fail_case "$case_dir" 'one or more diagnostics absent, unexpected, unclassified, empty or undecodable'
        return 1
    fi
    printf 'status=decoded-diagnostic-only; no build, test or acceptance claim\n' \
        >> "$case_dir/case-status.txt" || return 1
    return 0
}

# Independent case outcomes: a missing diagnostic or decoding error in one
# must never suppress extraction and decoding of the other pinned artifact.
decode_case iphone220 11944580203 installed-extension \
    '2026-10-15 02:12:24' '2026-10-15 02:15:11' || overall=1
decode_case ipad90 11944157161 installed-adaptive-ax \
    '2026-10-15 02:21:30' '2026-10-15 02:23:21' || overall=1
exit "$overall"
