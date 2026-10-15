#!/usr/bin/env python3
"""Compare one public simctl content-size token using ASCII case only."""

import pathlib
import re
import sys

# Canonical desired_size values listed by the retained Xcode 26.2 simctl help.
CATEGORIES = frozenset((
    "extra-small", "small", "medium", "large", "extra-large", "extra-extra-large",
    "extra-extra-extra-large", "accessibility-medium", "accessibility-large",
    "accessibility-extra-large", "accessibility-extra-extra-large",
    "accessibility-extra-extra-extra-large",
))
TOKEN_LINE = re.compile(rb"[A-Za-z]+(?:-[A-Za-z]+)*\n?")


def check(raw: bytes, expected: str) -> tuple[bool, str]:
    if expected not in CATEGORIES:
        return False, f"invalid expected content-size category: {expected!r}"
    if not TOKEN_LINE.fullmatch(raw):
        return False, f"expected exactly one ASCII content-size token line; raw={raw!r}"
    normalized = raw.removesuffix(b"\n").lower().decode("ascii")
    if normalized not in CATEGORIES or normalized != expected:
        return False, f"content-size readback mismatch: raw={raw!r}; ASCII-normalized={normalized!r}; expected={expected!r}"
    return True, f"content-size readback accepted: raw={raw!r}; ASCII-normalized={normalized!r}; expected={expected!r}"


def self_test() -> None:
    for raw in (b"extra-small", b"extra-small\n", b"extra-Small\n", b"EXTRA-SMALL"):
        assert check(raw, "extra-small")[0]
    assert check(b"accessibility-extra-extra-extra-large\n", "accessibility-extra-extra-extra-large")[0]
    assert check(b"Large\n", "large")[0]
    for category in CATEGORIES:
        assert check(category.encode("ascii"), category)[0]
    for raw in (b"", b"\n", b"extra-small\n\n", b"extra-small\nlarge\n", b" extra-small\n",
                b"extra-small \n", b"extra-small\t", b"extra-small\r\n", b"prefix extra-small\n",
                b"extra-small suffix\n", b"extra-small-junk\n", b"extra--small\n", b"unknown\n",
                b"unsupported\n", b"small\n", b"extra_small\n", b"extra-small\x00", "extra-ſmall\n".encode()):
        assert not check(raw, "extra-small")[0], raw
    for expected in ("", "unknown", "unsupported", "EXTRA-SMALL", "extra-Small", "extra-small\n", "invalid"):
        assert not check(b"extra-small\n", expected)[0], expected
    print("public content-size single-token ASCII readback self-test passed")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
    elif len(sys.argv) == 3:
        try:
            success, report = check(pathlib.Path(sys.argv[1]).read_bytes(), sys.argv[2])
        except OSError as error:
            sys.exit(f"content-size readback unavailable: {error}")
        print(report)
        sys.exit(0 if success else 1)
    else:
        sys.exit("usage: check-content-size-readback.py RAW_READBACK EXPECTED_CATEGORY | --self-test")
