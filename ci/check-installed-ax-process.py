#!/usr/bin/env python3
"""Check stage-scoped installed extension evidence without reading private text."""

import pathlib
import re
import sys

PROCESS = re.compile(r"\bFreeShiamyKeyboard\[(\d+):[^]]+\]")
LIFECYCLE = re.compile(
    r"FreeShiamyKeyboard lifecycle bundle=osku\.me\.freeshiamyios\.keyboard "
    r"pid=(\d+) hasFullAccess=NO\b"
)
ADAPTIVE = re.compile(
    r"\[AdaptiveKeyboard\] .*\bpercent=100 "
    r"category=UICTContentSizeCategoryAccessibilityXXXL expanded=([01])\b"
)


def check(log: str) -> tuple[bool, str]:
    lifecycles: set[str] = set()
    expanded: dict[str, set[str]] = {}
    for line in log.splitlines():
        process = PROCESS.search(line)
        if not process:
            continue
        pid = process.group(1)
        lifecycle = LIFECYCLE.search(line)
        if lifecycle and lifecycle.group(1) == pid:
            lifecycles.add(pid)
        adaptive = ADAPTIVE.search(line)
        if adaptive:
            expanded.setdefault(pid, set()).add(adaptive.group(1))
    accepted = sorted(pid for pid in lifecycles if expanded.get(pid) == {"0", "1"})
    if len(accepted) != 1:
        return False, (
            f"expected one extension PID with Full Access OFF and installed AX-XXXL "
            f"100% collapsed/expanded geometry; lifecycle={sorted(lifecycles)} "
            f"adaptive={{{', '.join(f'{pid}: {sorted(states)}' for pid, states in sorted(expanded.items()))}}}"
        )
    return True, f"installed AX-XXXL extension PID={accepted[0]} Full Access OFF percent=100 expanded=0,1"


def self_test() -> None:
    lifecycle = ("2026-10-14 00:00:01 Df FreeShiamyKeyboard[27:a] "
                 "FreeShiamyKeyboard lifecycle bundle=osku.me.freeshiamyios.keyboard "
                 "pid=27 hasFullAccess=NO")
    closed = ("2026-10-14 00:00:02 Df FreeShiamyKeyboard[27:a] "
              "[AdaptiveKeyboard] root=393.0x200.0 percent=100 "
              "category=UICTContentSizeCategoryAccessibilityXXXL expanded=0 compact=0")
    opened = closed.replace("expanded=0", "expanded=1")
    positive, _ = check("\n".join((lifecycle, closed, opened)))
    assert positive
    assert not check("\n".join((lifecycle, closed)))[0]
    assert not check("\n".join((lifecycle, closed, opened.replace("[27:a]", "[28:a]"))))[0]
    assert not check("\n".join((lifecycle.replace("hasFullAccess=NO", "hasFullAccess=YES"), closed, opened)))[0]
    assert not check("\n".join((lifecycle, closed.replace("AccessibilityXXXL", "L"), opened)))[0]
    assert not check("\n".join((lifecycle, closed.replace("percent=100", "percent=90"), opened)))[0]
    print("installed AX process parser self-test passed")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
    elif len(sys.argv) == 2:
        success, report = check(pathlib.Path(sys.argv[1]).read_text(errors="replace"))
        print(report)
        sys.exit(0 if success else 1)
    else:
        sys.exit("usage: check-installed-ax-process.py LOG | --self-test")
