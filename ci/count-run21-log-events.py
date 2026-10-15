#!/usr/bin/env python3
"""Count timestamped records in retained macOS log-show compact output."""

import pathlib
import re
import sys

# A compact event begins with a real date/time including milliseconds. The
# header is nonempty but has no timestamp, so byte count alone is insufficient.
EVENT = re.compile(
    r"^(?P<time>\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2})\.\d{3,6}"
    r"(?P<offset>[+-]\d{4})?\s+(?:Df|Db|A|I|E|F)\s+.+?\[\d+:[^\]\n]+\]"
)


def count_events(path, start, end):
    start_key = start[:19]
    end_key = end[:19]
    if not start_key < end_key:
        raise ValueError("Invalid event window")
    count = 0
    with path.open(encoding="utf-8", errors="replace") as source:
        for number, line in enumerate(source, 1):
            match = EVENT.match(line)
            if match is None:
                continue
            if match.group("offset") not in (None, "+0000"):
                raise ValueError(f"Timestamped record {number} contradicts requested UTC rendering")
            instant = match.group("time").replace("T", " ")
            if not start_key <= instant < end_key:
                raise ValueError(f"Timestamped record {number} outside requested UTC window: {instant}")
            count += 1
    if count == 0:
        raise ValueError("No timestamped compact log records; header-only output is inconclusive")
    return count


def self_test():
    import tempfile
    start, end = "2026-10-15 00:43:12+0000", "2026-10-15 00:44:46+0000"
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / "test.log"
        path.write_text("Filtering the log data using...\nTimestamp               Ty Process\n")
        try:
            count_events(path, start, end)
        except ValueError:
            pass
        else:
            raise AssertionError("Header-only output was accepted")
        path.write_text("Timestamp               Ty Process\n"
                        "2026-10-15 00:43:12.123 not a unified-log event\n")
        try:
            count_events(path, start, end)
        except ValueError:
            pass
        else:
            raise AssertionError("Timestamp-prefixed junk was accepted")
        path.write_text("Timestamp               Ty Process\n"
                        "2026-10-15 00:43:12.000 I  launchd[1:1] event\n"
                        "  continuation line without timestamp\n")
        assert count_events(path, start, end) == 1
        path.write_text("2026-10-15 00:43:12.123+0800 I  launchd[1:1] event\n")
        try:
            count_events(path, start, end)
        except ValueError:
            pass
        else:
            raise AssertionError("Non-UTC timestamp was accepted")
        path.write_text("2026-10-15 00:44:46.000 I  launchd[1:1] event\n")
        try:
            count_events(path, start, end)
        except ValueError:
            pass
        else:
            raise AssertionError("Exclusive end was accepted")
        # Exact Df/activity lines from the retained run-21 host-process log.
        path.write_text(
            "2026-10-15 00:48:52.751 Df freeshiamy-ios[54376:23d51] (libMobileGestalt.dylib) No persisted cache on this platform.\n"
            "2026-10-15 00:48:52.756 A  freeshiamy-ios[54376:23d79] (CoreFoundation) Loading Preferences From User Session CFPrefsD\n"
        )
        assert count_events(path, "2026-10-15 00:48:35+0000",
                            "2026-10-15 00:50:36+0000") == 2
    print("run21 compact-log event counter self-test passed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif len(sys.argv) == 4:
        try:
            print(f"events={count_events(pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3])}")
        except ValueError as error:
            raise SystemExit(str(error))
    else:
        raise SystemExit("usage: count-run21-log-events.py COMPACT_LOG START_UTC END_UTC")
