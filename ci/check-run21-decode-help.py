#!/usr/bin/env python3
"""Validate the exact macOS help contracts needed to decode retained logs."""

import pathlib
import sys

XCRESULT_USAGE = "xcresulttool export diagnostics --path <path> --output-path <output-path>"
LOG_REQUIRED = (
    "usage: log show [options] <archive>",
    "--start <date>",
    "--end <date>",
    "--style <style>",
    "compact)",
    "--timezone local | <tz>",
    "--[no-]info",
    "--[no-]debug",
)


def validate(status_text, xcresult_help, log_help):
    lines = status_text.splitlines()
    if len(lines) != 2 or not lines[0].startswith("xcresulttool_diagnostics_help_status=") or not lines[1].startswith("log_show_help_status="):
        raise ValueError("Missing or malformed help exit statuses")
    try:
        xc_status = int(lines[0].split("=", 1)[1])
        log_status = int(lines[1].split("=", 1)[1])
    except ValueError as error:
        raise ValueError("Non-numeric help exit status") from error
    if xc_status != 0:
        raise ValueError(f"xcresulttool help exited {xc_status}; expected 0")
    if log_status not in (0, 64):
        raise ValueError(f"log help exited {log_status}; expected 0 or observed usage status 64")
    if XCRESULT_USAGE not in xcresult_help:
        raise ValueError("xcresulttool diagnostics export usage is missing")
    for option in LOG_REQUIRED:
        if option not in log_help:
            raise ValueError(f"log show required usage/option is missing: {option}")
    return f"validated xcresulttool_help_status={xc_status} log_help_status={log_status}"


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: check-run21-decode-help.py STATUS_FILE XCRESULT_HELP_FILE LOG_HELP_FILE")
    try:
        print(validate(*(pathlib.Path(arg).read_text() for arg in sys.argv[1:])))
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
