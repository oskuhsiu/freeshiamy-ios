#!/usr/bin/env python3
"""Self-test the installed rotation evidence gate without a simulator."""

import json
import subprocess
import sys
import tempfile
from pathlib import Path


RUN = "12345678-1234-1234-1234-123456789ABC"
OTHER = "ABCDEF12-1234-1234-1234-123456789ABC"
CHECKER = Path(__file__).with_name("check-installed-host-geometry.py")


def line(orientation, *, run=RUN, scene=None, viewport=None, caret=None, pid=123):
    landscape = orientation == "landscape"
    scene = scene or ("{852, 393}" if landscape else "{393, 852}")
    window = "{{0, 0}, {852, 393}}" if landscape else "{{0, 0}, {393, 852}}"
    viewport = viewport or ("{{0, 30}, {852, 150}}" if landscape else "{{0, 50}, {393, 400}}")
    guide = "{{0, 180}, {852, 213}}" if landscape else "{{0, 450}, {393, 402}}"
    caret = caret or "{{10, 100}, {2, 20}}"
    return (f"[HostGeometry] run={run} pid={pid} scene={scene} window={window} "
            f"viewport={viewport} guide={guide} caret={caret} responder=multiline\n")


def check(name, lines, should_pass):
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        (directory / "geometry.log").write_text("".join(lines), encoding="utf-8")
        attachments = directory / "attachments"
        attachments.mkdir()
        (attachments / "run.txt").write_text(RUN, encoding="utf-8")
        manifest = [{"attachments": [{"suggestedHumanReadableName":
                                       "Installed smoke host-geometry run ID_0_sample.txt",
                                       "exportedFileName": "run.txt"}]}]
        (attachments / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        result = subprocess.run([sys.executable, str(CHECKER), str(directory / "geometry.log"),
                                 str(attachments)], capture_output=True, text=True, check=False)
        if (result.returncode == 0) != should_pass:
            raise AssertionError(f"{name}: unexpected status {result.returncode}: {result.stdout}{result.stderr}")
    print(f"{name}: {'pass' if should_pass else 'rejected'}")


if __name__ == "__main__":
    check("same-run real rotation", [line("portrait"), line("landscape"), line("portrait")], True)
    check("wrong run token", [line("portrait", run=OTHER), line("landscape", run=OTHER),
                               line("portrait", run=OTHER)], False)
    check("under-keyboard viewport and caret",
          [line("portrait"), line("landscape", viewport="{{0, 30}, {852, 220}}",
                                   caret="{{10, 195}, {2, 20}}"), line("portrait")], False)
    check("window-only orientation", [line("portrait"), line("landscape", scene="{393, 852}"),
                                       line("portrait")], False)
    check("nonfinite scene geometry", [line("portrait"),
                                        line("landscape", scene="{" + "9" * 400 + ", 393}"),
                                        line("portrait")], False)
    check("missing initial portrait", [line("landscape"), line("portrait")], False)
    check("split host PID", [line("portrait"), line("landscape", pid=456),
                             line("portrait", pid=456)], False)
