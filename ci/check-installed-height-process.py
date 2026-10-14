#!/usr/bin/env python3
"""Bind seven installed height captures to one PID's latest actual metrics."""

import json
import math
import pathlib
import re
import runpy
import sys
import tempfile

PROCESS = re.compile(r"\bFreeShiamyKeyboard\[(\d+):[^]]+\]")
LIFECYCLE = re.compile(
    r"FreeShiamyKeyboard lifecycle bundle=osku\.me\.freeshiamyios\.keyboard "
    r"pid=(\d+) hasFullAccess=(YES|NO)\b"
)
SEQUENCE = (("portrait", 0), ("portrait", 1), ("landscape", 1),
            ("landscape", 0), ("landscape", 1), ("portrait", 1), ("portrait", 0))
FIELDS = ("root", "window", "scene", "requested", "percent", "category", "expanded",
          "compact", "style", "epoch", "barDesired", "expandedDesired", "safeTop", "safeBottom")


def capture_stages(percent: int) -> list[str]:
    prefix = f"Height {percent}%"
    return [prefix + " chosen through Settings slider", prefix + " portrait collapsed before composition",
            "Height expanded portrait before rotation", "Height expanded landscape",
            prefix + " landscape collapsed keys restored", prefix + " landscape expanded again",
            "Height expanded portrait after rotation", prefix + " portrait collapsed composition preserved",
            prefix + " installed scenario complete"]


def captures(directory: pathlib.Path, percent: int) -> list[tuple[str, float]]:
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    if not isinstance(manifest, list):
        raise ValueError("capture manifest must be an array")
    items = [item for group in manifest for item in group.get("attachments", [])]
    resolved = []
    for stage in capture_stages(percent):
        matches = [item for item in items if item.get("suggestedHumanReadableName", "")
                   .startswith(stage + " — full screen_")]
        if len(matches) != 1:
            raise ValueError(f"expected one PNG capture '{stage}', found {len(matches)}")
        item = matches[0]
        name = item.get("exportedFileName")
        if not isinstance(name, str) or not name:
            raise ValueError(f"'{stage}' has no exported filename")
        path = (directory / name).resolve()
        epoch = item.get("timestamp")
        if (not path.is_relative_to(directory.resolve()) or not path.is_file() or path.suffix.lower() != ".png" or
                isinstance(epoch, bool) or not isinstance(epoch, (int, float)) or not math.isfinite(epoch) or epoch <= 0):
            raise ValueError(f"'{stage}' has no readable PNG/finite positive epoch timestamp")
        resolved.append((stage, float(epoch)))
    if not all(resolved[index][1] < resolved[index + 1][1] for index in range(len(resolved) - 1)):
        raise ValueError("chosen, seven state captures and completion must be strictly chronological")
    return resolved


def logged_epoch(line: str):
    values = re.findall(r"\bepoch=(\S+)", line)
    if len(values) != 1:
        return None
    try:
        epoch = float(values[0])
    except ValueError:
        return None
    return epoch if math.isfinite(epoch) and epoch > 0 else None


def validate_metric(line: str, percent: int, category: str, style: str, state: tuple[str, int]) -> dict:
    fields = re.findall(r"\b(" + "|".join(FIELDS) + r")=(\S+)", line)
    metric = dict(fields)
    if len(fields) != len(FIELDS) or len(metric) != len(FIELDS):
        raise ValueError("missing or duplicate adaptive fields")
    geometry = []
    for name in ("root", "window", "scene"):
        dimensions = metric[name].split("x")
        if len(dimensions) != 2:
            raise ValueError("malformed adaptive dimensions")
        geometry.extend(map(float, dimensions))
    requested = float(metric["requested"])
    safe_top, safe_bottom = float(metric["safeTop"]), float(metric["safeBottom"])
    bar, expanded_desired = float(metric["barDesired"]), float(metric["expandedDesired"])
    if not all(math.isfinite(value) and value > 0 for value in (*geometry, requested)):
        raise ValueError("root/window/scene/requested must be finite and positive")
    if not all(math.isfinite(value) and value >= 0 for value in (safe_top, safe_bottom)):
        raise ValueError("safe-area insets must be finite and nonnegative")
    if not math.isfinite(bar) or not 37.5 <= bar <= 56 or expanded_desired != 180:
        raise ValueError("desired bar/expanded geometry does not match production bounds")
    _, root_height, _, _, scene_width, scene_height = geometry
    orientation = ("portrait" if scene_height > scene_width + 20 else
                   "landscape" if scene_width > scene_height + 20 else None)
    expanded = int(metric["expanded"])
    if (int(metric["percent"]) != percent or metric["category"] != category or metric["style"] != style or
            (orientation, expanded) != state or int(metric["compact"]) not in (0, 1)):
        raise ValueError("wrong actual percent/trait/orientation/expansion state")
    usable = max(0.0, scene_height - safe_top - safe_bottom)
    cap = max(0.0, min(0.60 * usable, usable - 44.0))
    expected = min(216.0 * percent / 100.0 + bar + (expanded_desired if expanded else 0.0), cap)
    if abs(requested - expected) > 1.0 or root_height > requested + 1.0:
        raise ValueError(f"requested/root height disagrees with independent budget: requested={requested}, expected={expected}, root={root_height}")
    return {"requested": requested, "expected": expected, "rootHeight": root_height,
            "scene": (scene_width, scene_height), "cap": cap, "expanded": expanded}


def check(log: str, expected_percent: int, expected_category: str,
          expected_style: str, attachments: pathlib.Path) -> tuple[bool, str]:
    try:
        milestones = captures(attachments, expected_percent)
    except (OSError, ValueError, TypeError, AttributeError, KeyError) as error:
        return False, f"installed height captures rejected: {error}"
    start, end = milestones[0][1], milestones[-1][1]
    lifecycles: dict[str, list[tuple[float, str]]] = {}
    records: dict[str, list[tuple[float, int, str]]] = {}
    unknown: set[str] = set()
    diagnostics: dict[str, int] = {}
    for index, line in enumerate(log.splitlines()):
        if "[AdaptiveKeyboard]" not in line and "FreeShiamyKeyboard lifecycle" not in line:
            continue
        process = PROCESS.search(line)
        if not process:
            continue
        pid = process.group(1)
        diagnostics[pid] = diagnostics.get(pid, 0) + 1
        epoch = logged_epoch(line)
        if epoch is None:
            unknown.add(pid)
            continue
        if not start <= epoch <= end:
            continue
        if "FreeShiamyKeyboard lifecycle" in line:
            lifecycle = LIFECYCLE.search(line)
            if lifecycle and lifecycle.group(1) == pid:
                lifecycles.setdefault(pid, []).append((epoch, lifecycle.group(2)))
            else:
                unknown.add(pid)
        if "[AdaptiveKeyboard]" in line:
            records.setdefault(pid, []).append((epoch, index, line))
    accepted = []
    failures = []
    for pid, events in sorted(lifecycles.items()):
        if pid in unknown or not any(value == "NO" for _, value in events) or any(value != "NO" for _, value in events):
            failures.append(f"PID={pid}: missing/malformed epoch or lifecycle is not Full Access OFF")
            continue
        states = sorted(records.get(pid, []))
        selected = []
        try:
            for (stage, timestamp), expected_state in zip(milestones[1:-1], SEQUENCE):
                preceding = [record for record in states if record[0] <= timestamp]
                if not preceding:
                    raise ValueError(f"'{stage}' has no same-PID adaptive record within chosen→complete interval")
                epoch, _, line = preceding[-1]
                # A later invalid record supersedes an earlier good one.
                geometry = validate_metric(line, expected_percent, expected_category, expected_style, expected_state)
                selected.append(f"{stage}: epoch={epoch:.6f} capture={timestamp:.6f} gap={timestamp - epoch:.6f}s "
                                f"geometry={json.dumps(geometry, separators=(',', ':'))}")
            accepted.append((pid, selected))
        except (ValueError, OverflowError) as error:
            failures.append(f"PID={pid}: {error}")
    if len(accepted) != 1:
        return False, (f"expected one fully satisfying same-PID Full Access OFF height scenario; accepted={[pid for pid, _ in accepted]}; "
                       f"diagnostic_trace_counts={diagnostics}; failures={failures}")
    pid, selected = accepted[0]
    return True, (f"Installed height PID={pid} Full Access OFF percent={expected_percent} category={expected_category} "
                  f"style={expected_style} interval={start:.6f}→{end:.6f}; diagnostic_trace_counts={diagnostics}\n" + "\n".join(selected))


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        directory = pathlib.Path(temporary)
        def fixture(percent=90, *, capped=False, smaller=False, pid=27):
            category = "UICTContentSizeCategoryXS" if percent == 90 else "UICTContentSizeCategoryAccessibilityXXXL"
            style = "light" if percent == 90 else "dark"
            items = []
            for index, stage in enumerate(capture_stages(percent)):
                filename = f"capture-{index}.png"
                (directory / filename).write_bytes(b"portable parser fixture; pixels reviewed separately")
                items.append({"suggestedHumanReadableName": stage + f" — full screen_0_{filename}",
                              "exportedFileName": filename, "timestamp": 100.0 + index * 10 + (1 if index not in (0, 8) else 0)})
            lifecycle = (f"2026-10-14 00:00:00.000 Df FreeShiamyKeyboard[{pid}:a] "
                         f"FreeShiamyKeyboard lifecycle bundle=osku.me.freeshiamyios.keyboard pid={pid} hasFullAccess=NO epoch=101.000000")
            lines = [lifecycle]
            for index, (orientation, expanded) in enumerate(SEQUENCE, 1):
                width, height = (393, 852 if capped else 1200) if orientation == "portrait" else (852, 393)
                bar = 38 if percent == 90 else 56
                usable = height - 34
                cap = max(0, min(0.60 * usable, usable - 44))
                requested = min(216 * percent / 100 + bar + (180 if expanded else 0), cap)
                root = requested - 20 if smaller else requested
                lines.append(f"2026-10-14 00:00:{index:02d}.000 Df FreeShiamyKeyboard[{pid}:a] "
                             f"[AdaptiveKeyboard] root={width}.0x{root:.1f} window={width}.0x{root:.1f} "
                             f"scene={width}.0x{height}.0 requested={requested:.1f} percent={percent} category={category} "
                             f"expanded={expanded} compact=0 style={style} epoch={100 + index * 10:.6f} "
                             f"barDesired={bar}.0 expandedDesired=180.0 safeTop=0.0 safeBottom=34.0")
            return lines, items, category, style
        def accepted(lines, items, percent=90, category=None, style=None):
            (directory / "manifest.json").write_text(json.dumps([{"attachments": items}]), encoding="utf-8")
            return check("\n".join(lines), percent, category or "UICTContentSizeCategoryXS", style or "light", directory)[0]
        valid, items, _, _ = fixture()
        baseline = runpy.run_path(str(pathlib.Path(__file__).with_name("check-installed-ax-process.py")))
        assert baseline["LIFECYCLE"].search(valid[0]), "baseline lifecycle regex must tolerate appended epoch"
        assert accepted(valid, items)
        smaller, _, _, _ = fixture(smaller=True)
        assert accepted(smaller, items)
        large, large_items, category, style = fixture(220)
        assert accepted(large, large_items, 220, category, style)
        wrong_size = list(large)
        wrong_size[1] = wrong_size[1].replace("requested=531.2", "requested=272.0").replace("x531.2", "x272.0")
        assert not accepted(wrong_size, large_items, 220, category, style)
        capped, capped_items, category, style = fixture(220, capped=True)
        assert accepted(capped, capped_items, 220, category, style)
        assert "requested=490.8" in capped[1] and "requested=490.8" in capped[2]
        old = [line.replace("[27:a]", "[9:a]").replace("pid=27", "pid=9")
               .replace("epoch=101.000000", "epoch=51.000000") for line in valid]
        pre_slider = valid[1].replace("epoch=110.000000", "epoch=90.000000").replace("percent=90", "percent=100")
        assert accepted([pre_slider, *old, *valid], items)
        partial = [valid[0], *valid[1:4], valid[0].replace("[27:a]", "[28:a]").replace("pid=27", "pid=28"),
                   *[line.replace("[27:a]", "[28:a]") for line in valid[4:]]]
        assert not accepted(partial, items)
        latest_wrong = valid[1].replace("epoch=110.000000", "epoch=110.500000").replace("requested=232.4", "requested=200.0")
        assert not accepted([valid[0], valid[1], latest_wrong, *valid[2:]], items)
        latest_trait = valid[1].replace("epoch=110.000000", "epoch=110.500000").replace("style=light", "style=dark")
        assert not accepted([*valid, latest_trait], items)
        other_valid = [line.replace("[27:a]", "[28:a]").replace("pid=27", "pid=28") for line in valid]
        assert not accepted([*valid, *other_valid], items)
        for field in FIELDS:
            broken = list(valid)
            broken[1] = re.sub(r"\b" + field + r"=\S+", "", broken[1])
            assert not accepted(broken, items), field
        for bad in ("nan", "inf", "-1", "bad"):
            assert not accepted([valid[0], valid[1].replace("safeTop=0.0", f"safeTop={bad}"), *valid[2:]], items)
        for bad in ("nan", "inf", "0", "-1", "bad"):
            assert not accepted([valid[0], valid[1].replace("root=393.0x232.4", f"root=393.0x{bad}"), *valid[2:]], items)
        assert not accepted([valid[0].replace("hasFullAccess=NO", "hasFullAccess=YES"), *valid[1:]], items)
        for old_value, new_value in (("percent=90", "percent=100"), ("style=light", "style=dark"),
                                     ("UICTContentSizeCategoryXS", "UICTContentSizeCategoryL"),
                                     ("expanded=0", "expanded=1"), ("expandedDesired=180.0", "expandedDesired=181.0"),
                                     ("barDesired=38.0", "barDesired=57.0")):
            assert not accepted([valid[0], valid[1].replace(old_value, new_value), *valid[2:]], items)
        assert not accepted(valid, items[:-1])
        assert not accepted(valid, items + [items[2]])
        reordered = [dict(item) for item in items]
        reordered[3]["timestamp"] = reordered[2]["timestamp"] - 1
        assert not accepted(valid, reordered)
        outside = [dict(item) for item in items]
        outside[1]["timestamp"] = outside[0]["timestamp"] - 1
        assert not accepted(valid, outside)
    print("installed height capture-bound process parser self-test passed")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
    elif len(sys.argv) == 6:
        try:
            percent = int(sys.argv[2])
        except ValueError:
            sys.exit("expected-percent must be an integer")
        if percent not in (90, 220) or sys.argv[4] not in ("light", "dark", "unspecified"):
            sys.exit("expected-percent must be 90 or 220 and expected-style must be light, dark or unspecified")
        success, report = check(pathlib.Path(sys.argv[1]).read_text(errors="replace"), percent,
                                sys.argv[3], sys.argv[4], pathlib.Path(sys.argv[5]))
        print(report)
        sys.exit(0 if success else 1)
    else:
        sys.exit("usage: check-installed-height-process.py LOG EXPECTED_PERCENT EXPECTED_CATEGORY EXPECTED_STYLE ATTACHMENTS | --self-test")
