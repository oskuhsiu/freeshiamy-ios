#!/usr/bin/env python3
"""Require real installed-host portrait and landscape keyboard-guide evidence."""

import re
import sys
import json
import math
from collections import defaultdict
from pathlib import Path


def rect(line, name):
    match = re.search(rf"{name}=(\{{\{{.*?\}}\}})", line)
    if not match:
        return None
    numbers = re.findall(r"-?\d+(?:\.\d+)?", match.group(1))
    return tuple(map(float, numbers)) if len(numbers) == 4 else None


attachments = Path(sys.argv[2])
manifest = json.loads((attachments / "manifest.json").read_text(encoding="utf-8"))
markers = [item for group in manifest for item in group.get("attachments", [])
           if item.get("suggestedHumanReadableName", "").startswith("Installed smoke host-geometry run ID")]
if len(markers) != 1:
    sys.exit(f"Expected one current-test run-ID attachment, found {len(markers)}")
expected_run_id = (attachments / markers[0]["exportedFileName"]).read_text(encoding="utf-8").strip()
if not re.fullmatch(r"[0-9A-Fa-f-]{36}", expected_run_id):
    sys.exit("Current-test run-ID attachment is not a UUID")

seen = defaultdict(list)
with open(sys.argv[1], encoding="utf-8", errors="replace") as log:
    for line in log:
        if "[HostGeometry]" not in line or "responder=multiline" not in line:
            continue
        identity = re.search(r"\[HostGeometry\] run=([0-9A-Fa-f-]{36}) pid=(\d+)", line)
        scene = re.search(r"scene=\{([-\d.]+), ([-\d.]+)\}", line)
        window = rect(line, "window")
        viewport = rect(line, "viewport")
        guide = rect(line, "guide")
        caret = rect(line, "caret")
        if not (identity and identity.group(1) == expected_run_id and scene and
                window and viewport and guide and caret):
            continue
        sw, sh = float(scene.group(1)), float(scene.group(2))
        wx, wy, ww, wh = window
        vx, vy, vw, vh = viewport
        gx, gy, gw, gh = guide
        cx, cy, cw, ch = caret
        if not all(map(math.isfinite, (sw, sh, *window, *viewport, *guide, *caret))):
            continue
        guide_visible = (sw > 0 and sh > 0 and ww > 0 and wh > 0 and
                         gw > 0 and gh > 100 and gy >= wy - 1 and gy < wy + wh - 1 and
                         gy + gh <= wy + wh + 1 and gx >= wx - 1 and gx + gw <= wx + ww + 1)
        viewport_visible = (vw > 0 and vh > 0 and vx >= wx - 1 and vy >= wy - 1 and
                            vx + vw <= wx + ww + 1 and vy + vh <= gy + 1)
        caret_visible = (cw > 0 and ch > 0 and cx >= vx - 1 and cx + cw <= vx + vw + 1 and
                         cy >= vy - 1 and cy + ch <= vy + vh + 1 and cy + ch <= gy + 1)
        if not (guide_visible and viewport_visible and caret_visible):
            continue
        orientation = ("landscape" if ww > wh + 20 and sw > sh + 20 else
                       "portrait" if wh > ww + 20 and sh > sw + 20 else None)
        if orientation:
            seen[(identity.group(1), identity.group(2))].append(orientation)

def complete_rotation(orientations):
    sequence = ("portrait", "landscape", "portrait")
    index = 0
    for orientation in orientations:
        if orientation == sequence[index]:
            index += 1
            if index == len(sequence):
                return True
    return False


for (run_id, pid), orientations in sorted(seen.items()):
    print(f"Installed run {run_id}, host PID {pid}: verified {', '.join(orientations)}")
if not any(complete_rotation(orientations) for orientations in seen.values()):
    sys.exit("Missing current-test same-PID portrait→landscape→portrait caret/keyboard-guide evidence")
