#!/usr/bin/env python3
"""Bind expanded-More screenshots to the latest same-run host/caret geometry."""

import json
import math
import re
import sys
import tempfile
from pathlib import Path

STAGES = (("Height expanded portrait before rotation", "portrait"),
          ("Height expanded landscape", "landscape"),
          ("Height expanded portrait after rotation", "portrait"))
UUID = re.compile(r"[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}")
NUMBER = r"([^,{}\s]+)"


def exported_path(directory: Path, name: str) -> Path:
    if not isinstance(name, str) or not name:
        raise ValueError("attachment has no exported filename")
    path = (directory / name).resolve()
    if not path.is_relative_to(directory.resolve()) or not path.is_file():
        raise ValueError("attachment export is absent or outside its directory")
    return path


def rectangle(line: str, name: str) -> tuple[float, ...]:
    pattern = (rf"\b{name}=\{{\{{\s*{NUMBER}\s*,\s*{NUMBER}\s*\}}\s*,\s*"
               rf"\{{\s*{NUMBER}\s*,\s*{NUMBER}\s*\}}\}}")
    match = re.search(pattern, line)
    if not match:
        raise ValueError(f"missing/malformed {name} rectangle")
    return tuple(map(float, match.groups()))


def validate_geometry(line: str, expected_orientation: str) -> dict:
    scene = re.search(rf"\bscene=\{{\s*{NUMBER}\s*,\s*{NUMBER}\s*\}}", line)
    responder = re.search(r"\bresponder=(\S+)", line)
    if not scene or not responder or responder.group(1) != "multiline":
        raise ValueError("missing scene or focused multiline responder")
    sw, sh = map(float, scene.groups())
    window = rectangle(line, "window")
    viewport = rectangle(line, "viewport")
    guide = rectangle(line, "guide")
    caret = rectangle(line, "caret")
    if not all(map(math.isfinite, (sw, sh, *window, *viewport, *guide, *caret))):
        raise ValueError("nonfinite geometry")
    wx, wy, ww, wh = window
    vx, vy, vw, vh = viewport
    gx, gy, gw, gh = guide
    cx, cy, cw, ch = caret
    orientation = ("landscape" if ww > wh + 20 and sw > sh + 20 else
                   "portrait" if wh > ww + 20 and sh > sw + 20 else None)
    if orientation != expected_orientation:
        raise ValueError(f"expected {expected_orientation} scene/window, observed {orientation}")
    guide_visible = (sw > 0 and sh > 0 and ww > 0 and wh > 0 and
                     gw > 0 and gh > 100 and gy >= wy - 1 and gy < wy + wh - 1 and
                     gy + gh <= wy + wh + 1 and gx >= wx - 1 and gx + gw <= wx + ww + 1)
    viewport_visible = (vw > 0 and vh > 0 and vx >= wx - 1 and vy >= wy - 1 and
                        vx + vw <= wx + ww + 1 and vy + vh <= gy + 1)
    caret_visible = (cw > 0 and ch > 0 and cx >= vx - 1 and cx + cw <= vx + vw + 1 and
                     cy >= vy - 1 and cy + ch <= vy + vh + 1 and cy + ch <= gy + 1)
    if not (guide_visible and viewport_visible and caret_visible):
        raise ValueError("keyboard guide, viewport or caret is outside its accepted visible geometry")
    return {"scene": (sw, sh), "window": window, "viewport": viewport, "guide": guide, "caret": caret}


def check(log: str, attachments: Path) -> tuple[bool, str]:
    try:
        manifest = json.loads((attachments / "manifest.json").read_text(encoding="utf-8"))
        if not isinstance(manifest, list):
            raise ValueError("attachment manifest is not an array")
        items = [item for group in manifest for item in group.get("attachments", [])]
        markers = [item for item in items if item.get("suggestedHumanReadableName", "")
                   .startswith("Installed smoke host-geometry run ID")]
        if len(markers) != 1:
            raise ValueError(f"expected one current-test UUID marker, found {len(markers)}")
        run_id = exported_path(attachments, markers[0].get("exportedFileName")).read_text(encoding="utf-8").strip()
        if not UUID.fullmatch(run_id):
            raise ValueError("current-test marker is not a UUID")
        captures = []
        for stage, orientation in STAGES:
            matches = [item for item in items if item.get("suggestedHumanReadableName", "")
                       .startswith(stage + " — full screen_")]
            if len(matches) != 1:
                raise ValueError(f"expected one screenshot for '{stage}', found {len(matches)}")
            item = matches[0]
            screenshot = exported_path(attachments, item.get("exportedFileName"))
            timestamp = item.get("timestamp")
            if screenshot.suffix.lower() != ".png" or isinstance(timestamp, bool) or not isinstance(timestamp, (int, float)):
                raise ValueError(f"'{stage}' lacks an exported PNG or numeric epoch timestamp")
            if not math.isfinite(timestamp) or timestamp <= 0:
                raise ValueError(f"'{stage}' has a nonfinite/nonpositive timestamp")
            captures.append((stage, orientation, timestamp))
        if not all(captures[index][2] < captures[index + 1][2] for index in range(len(captures) - 1)):
            raise ValueError("expanded-More screenshots are not strictly chronological")
        records = []
        for number, line in enumerate(log.splitlines(), 1):
            if "[HostGeometry]" not in line:
                continue
            identity = re.search(r"\[HostGeometry\] run=(\S+)", line)
            if not identity or identity.group(1) != run_id:
                continue
            pid_match = re.search(r"\bpid=(\d+)\b", line)
            epoch_match = re.search(r"\bepoch=(\S+)", line)
            if not pid_match or not epoch_match:
                raise ValueError(f"same-run geometry line {number} lacks PID/epoch")
            epoch = float(epoch_match.group(1))
            if not math.isfinite(epoch) or epoch <= 0:
                raise ValueError(f"same-run geometry line {number} has invalid epoch")
            if records and epoch < records[-1][0]:
                raise ValueError("same-run host geometry is not chronological")
            records.append((epoch, pid_match.group(1), line))
        if not records or captures[0][2] <= records[0][0]:
            raise ValueError("missing same-run host geometry before first expanded capture")
        reports = []
        selected_pids = set()
        for stage, orientation, timestamp in captures:
            preceding = [record for record in records if record[0] <= timestamp]
            if not preceding:
                raise ValueError(f"no same-run geometry at/before '{stage}'")
            # Never search past a later invalid record for an older passing one.
            epoch, pid, line = preceding[-1]
            geometry = validate_geometry(line, orientation)
            selected_pids.add(pid)
            reports.append(f"{stage}: host PID={pid} epoch={epoch:.6f} capture={timestamp:.6f} "
                           f"gap={timestamp - epoch:.6f}s geometry={json.dumps(geometry, separators=(',', ':'))}")
        if len(selected_pids) != 1:
            raise ValueError(f"expanded captures span host PIDs: {sorted(selected_pids)}")
        return True, f"Expanded-More run {run_id}\n" + "\n".join(reports)
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        return False, f"installed height milestone evidence rejected: {error}"


def self_test() -> None:
    run_id = "12345678-1234-1234-1234-123456789ABC"
    def line(epoch, orientation, *, pid=123, run=run_id, caret=None):
        landscape = orientation == "landscape"
        scene = "{852, 393}" if landscape else "{393, 852}"
        window = "{{0, 0}, {852, 393}}" if landscape else "{{0, 0}, {393, 852}}"
        viewport = "{{0, 30}, {852, 150}}" if landscape else "{{0, 50}, {393, 400}}"
        guide = "{{0, 180}, {852, 213}}" if landscape else "{{0, 450}, {393, 402}}"
        caret = caret or "{{10, 100}, {2, 20}}"
        return (f"[HostGeometry] run={run} pid={pid} epoch={epoch:.6f} scene={scene} "
                f"window={window} viewport={viewport} guide={guide} caret={caret} responder=multiline")
    valid = [line(10, "portrait"), line(20, "landscape"), line(30, "portrait")]
    with tempfile.TemporaryDirectory() as temporary:
        attachments = Path(temporary)
        (attachments / "run.txt").write_text(run_id, encoding="utf-8")
        items = [{"suggestedHumanReadableName": "Installed smoke host-geometry run ID_0_run.txt",
                  "exportedFileName": "run.txt"}]
        for index, (stage, _) in enumerate(STAGES):
            filename = f"capture{index}.png"
            (attachments / filename).write_bytes(b"parser fixture; image pixels are independently reviewed")
            items.append({"suggestedHumanReadableName": stage + f" — full screen_0_{filename}",
                          "exportedFileName": filename, "timestamp": 15.0 + index * 10})
        def accepted(lines, entries=None):
            (attachments / "manifest.json").write_text(json.dumps([{"attachments": items if entries is None else entries}]), encoding="utf-8")
            return check("\n".join(lines), attachments)[0]
        assert accepted(valid)
        assert not accepted([value.replace(run_id, "ABCDEF12-1234-1234-1234-123456789ABC") for value in valid])
        assert not accepted([valid[0], line(20, "landscape", pid=456), valid[2]])
        assert not accepted([valid[0], valid[1], line(24, "landscape", caret="{{10, 195}, {2, 20}}"), valid[2]])
        assert not accepted(valid, items[:-1])
        assert not accepted(valid, items + [items[1]])
        assert not accepted([valid[0], line(20, "portrait"), valid[2]])
        assert not accepted([valid[0], valid[1].replace("caret={{10, 100}, {2, 20}}", "caret=malformed"), valid[2]])
        assert not accepted([valid[0], line(20, "landscape", caret="{{nan, 100}, {2, 20}}"), valid[2]])
        assert not accepted([valid[0], valid[1].replace("epoch=20.000000", "epoch=inf"), valid[2]])
        assert not accepted([valid[0], valid[1].replace("responder=multiline", "responder=singleline"), valid[2]])
        assert not accepted([valid[0], valid[1].replace("scene={852, 393}", "scene={393, 852}"), valid[2]])
        reordered = [dict(item) for item in items]
        reordered[2]["timestamp"] = 10.0
        assert not accepted(valid, reordered)
        assert not accepted([line(16, "portrait"), *valid[1:]])
        assert not accepted(valid, [dict(item, timestamp=float("nan")) if "timestamp" in item else item for item in items])
    print("installed height milestone parser self-test passed")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
    elif len(sys.argv) == 3:
        success, report = check(Path(sys.argv[1]).read_text(errors="replace"), Path(sys.argv[2]))
        print(report)
        sys.exit(0 if success else 1)
    else:
        sys.exit("usage: check-installed-height-milestones.py HOST_LOG ATTACHMENTS | --self-test")
