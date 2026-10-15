#!/usr/bin/env python3
"""Bind each installed input-action test's captures to actual Full Access OFF metrics."""

import copy
import json
import math
import pathlib
import re
import sys
import tempfile
import uuid

PROCESS = re.compile(r"\bFreeShiamyKeyboard\[(\d+):[^]]+\]")
LIFECYCLE = re.compile(
    r"FreeShiamyKeyboard lifecycle bundle=osku\.me\.freeshiamyios\.keyboard "
    r"pid=(\d+) hasFullAccess=(YES|NO)\b"
)
FIELDS = ("root", "requested", "percent", "category", "style", "epoch")
# False milestones deliberately include dismissed keyboards: their captures
# establish chronology, but cannot require a live extension metric.
CASES = {
    "InstalledKeyboardUITests/testInstalledBracketRootsUseRealLongPressAndLiteralSymbols": (
        ("Bracket roots fresh portrait host", False),
        ("Bracket roots baseline settings observed height exactly 100%", False),
        ("Bracket roots activation dictionary ready", True),
        ("Opening root after real long press", True),
        ("Opening root f composition", True),
        ("Opening bracket candidate committed", True),
        ("Closing root after real long press", True),
        ("Closing root f composition", True),
        ("Closing bracket candidate committed", True),
        ("Literal brackets actual symbol page", True),
        ("Symbols inserted both literal brackets exactly", True),
        ("Installed bracket-root and symbol gestures complete", False),
    ),
    "InstalledKeyboardUITests/testInstalledCodeSearchReturnCommitsThenDismisses": (
        ("CodeSearch fresh portrait host", False),
        ("CodeSearch baseline settings observed height exactly 100%", False),
        ("CodeSearch activation dictionary ready", True),
        ("CodeSearch installed Search trait", True),
        ("CodeSearch live ci composition", True),
        ("First Search leaves installed keyboard active", True),
        ("First Search preserves Search label", True),
        ("Second Search dismisses through CodeSearch host", False),
        ("CodeSearch refocus activation dictionary ready", True),
        ("CodeSearch recomposed ci", True),
        ("CodeSearch actual 中 candidate", True),
        ("CodeSearch exact native code-search results", True),
        ("CodeSearch Search before final dismissal", True),
        ("Search dismisses with 中 results", False),
        ("Installed CodeSearch Return behavior complete", False),
    ),
}


def positive_epoch(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
        raise ValueError("capture timestamp must be finite positive epoch seconds")
    return float(value)


def attachment_path(directory, item, suffix):
    name = item.get("exportedFileName")
    if not isinstance(name, str) or not name:
        raise ValueError("missing exported attachment filename")
    path = (directory / name).resolve()
    if not path.is_relative_to(directory.resolve()) or not path.is_file() or path.suffix.lower() != suffix:
        raise ValueError(f"missing readable {suffix} attachment inside stage directory")
    return path


def case_captures(directory):
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    if not isinstance(manifest, list) or any(not isinstance(group, dict) for group in manifest):
        raise ValueError("manifest must be an array of test groups")
    if len(manifest) != len(CASES) or {group.get("testIdentifier") for group in manifest} != set(CASES):
        raise ValueError("manifest must contain exactly the two uniquely selected testIdentifier groups")
    resolved = {}
    uuids = set()
    for identifier, stages in CASES.items():
        groups = [group for group in manifest if group.get("testIdentifier") == identifier]
        if len(groups) != 1:
            raise ValueError(f"duplicate or missing test group {identifier}")
        items = groups[0].get("attachments")
        if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
            raise ValueError(f"{identifier}: malformed attachment list")
        markers = [item for item in items if str(item.get("suggestedHumanReadableName", ""))
                   .startswith("Installed smoke host-geometry run ID_")]
        if len(markers) != 1:
            raise ValueError(f"{identifier}: expected one current-case UUID marker, found {len(markers)}")
        run_id = attachment_path(directory, markers[0], ".txt").read_text(encoding="utf-8").strip()
        if str(uuid.UUID(run_id)).lower() != run_id.lower() or run_id.lower() in uuids:
            raise ValueError(f"{identifier}: malformed or reused fresh-host UUID")
        uuids.add(run_id.lower())
        captures = []
        for stage, active in stages:
            matches = [item for item in items if str(item.get("suggestedHumanReadableName", ""))
                       .startswith(stage + " — full screen_")]
            if len(matches) != 1:
                raise ValueError(f"{identifier}: expected one PNG capture '{stage}', found {len(matches)}")
            attachment_path(directory, matches[0], ".png")
            captures.append((stage, positive_epoch(matches[0].get("timestamp")), active))
        if not all(a[1] < b[1] for a, b in zip(captures, captures[1:])):
            raise ValueError(f"{identifier}: fresh-host, Settings, dictionary/critical and completion captures must be strictly ordered")
        resolved[identifier] = (run_id, captures)
    intervals = sorted((captures[0][1], captures[-1][1]) for _, captures in resolved.values())
    if intervals[0][1] >= intervals[1][0]:
        raise ValueError("fresh test-case capture intervals overlap")
    return resolved


def logged_epoch(line):
    epochs = re.findall(r"\bepoch=(\S+)", line)
    if len(epochs) != 1:
        raise ValueError("missing or duplicate logged epoch")
    epoch = float(epochs[0])
    if not math.isfinite(epoch) or epoch <= 0:
        raise ValueError("logged epoch must be finite and positive")
    return epoch


def validate_metric(line):
    fields = re.findall(r"\b(" + "|".join(FIELDS) + r")=(\S+)", line)
    metric = dict(fields)
    if len(fields) != len(FIELDS) or len(metric) != len(FIELDS):
        raise ValueError("missing or duplicate required adaptive metric")
    dimensions = metric["root"].split("x")
    if len(dimensions) != 2:
        raise ValueError("malformed actual root dimensions")
    geometry = [*map(float, dimensions), float(metric["requested"])]
    if not all(math.isfinite(value) and value > 0 for value in geometry):
        raise ValueError("actual root/requested geometry must be finite and positive")
    if metric["percent"] != "100" or metric["category"] != "UICTContentSizeCategoryL" or metric["style"] != "light":
        raise ValueError("actual metrics must show 100%, UICTContentSizeCategoryL and light")
    return {"root": geometry[:2], "requested": geometry[2]}


def check(log, directory):
    try:
        cases = case_captures(directory)
    except (OSError, ValueError, TypeError, AttributeError, KeyError) as error:
        return False, f"installed action captures rejected: {error}"
    traces, appearances = {}, []
    malformed_metrics = set()
    for index, line in enumerate(log.splitlines()):
        lifecycle_looking = "FreeShiamyKeyboard lifecycle" in line
        if "[AdaptiveKeyboard]" not in line and not lifecycle_looking:
            continue
        process = PROCESS.search(line)
        try:
            epoch = logged_epoch(line)
        except (ValueError, OverflowError):
            if lifecycle_looking:
                return False, f"unscopable lifecycle-looking record at log line {index + 1}: missing/invalid epoch"
            if process:
                malformed_metrics.add(process.group(1))
            continue
        if lifecycle_looking:
            if not process:
                return False, f"unscopable lifecycle-looking record at log line {index + 1}: missing actual process PID"
            # Keep all lifecycle-looking records, including wrong bundles/YES
            # and malformed values, until the latest appearance is selected.
            appearances.append((epoch, index, process.group(1), line))
        if process and "[AdaptiveKeyboard]" in line:
            traces.setdefault(process.group(1), []).append((epoch, index, line))
    reports = []
    for identifier, (run_id, captures) in cases.items():
        start, end = captures[0][1], captures[-1][1]
        scoped_appearances = [record for record in appearances if start <= record[0] <= end]
        selected, case_pid = [], None
        try:
            for stage, capture_epoch, active in captures:
                if not active:
                    continue
                preceding = [record for record in scoped_appearances if record[0] <= capture_epoch]
                if not preceding:
                    raise ValueError(f"'{stage}': missing fresh same-case lifecycle-looking appearance")
                latest_epoch = max(record[0] for record in preceding)
                latest = [record for record in preceding if record[0] == latest_epoch]
                if len(latest) != 1:
                    raise ValueError(f"'{stage}': tied/ambiguous latest appearances at {latest_epoch:.6f}")
                appearance_epoch, _, pid, lifecycle_line = latest[0]
                lifecycle = LIFECYCLE.search(lifecycle_line)
                if not lifecycle or lifecycle.group(1) != pid or lifecycle.group(2) != "NO":
                    raise ValueError(f"'{stage}': latest actual appearance has wrong bundle/PID, malformed lifecycle or Full Access YES")
                if case_pid is not None and pid != case_pid:
                    raise ValueError(f"'{stage}': within-case extension PID changed from {case_pid} to {pid}")
                case_pid = pid
                if pid in malformed_metrics:
                    raise ValueError(f"'{stage}': unscopable malformed same-PID adaptive epoch")
                metrics = sorted(record for record in traces.get(pid, []) if start <= record[0] <= capture_epoch)
                if not metrics:
                    raise ValueError(f"'{stage}': missing latest same-PID metric inside this case interval")
                epoch, _, line = metrics[-1]
                if epoch < appearance_epoch:
                    raise ValueError(f"'{stage}': latest same-PID metric predates selected appearance")
                geometry = validate_metric(line)  # Never skip a later invalid metric.
                selected.append(f"{stage}: appearance={appearance_epoch:.6f} epoch={epoch:.6f} capture={capture_epoch:.6f} "
                                f"gap={capture_epoch - epoch:.6f}s geometry={json.dumps(geometry, separators=(',', ':'))}")
        except (ValueError, OverflowError) as error:
            return False, (f"{identifier} run={run_id}: {error}; trace_counts="
                           f"{ {pid: len(records) for pid, records in traces.items()} }")
        reports.append(f"{identifier} run={run_id} PID={case_pid} Full Access OFF percent=100 category=UICTContentSizeCategoryL "
                       f"style=light interval={start:.6f}→{end:.6f}\n" + "\n".join(selected))
    return True, "\n".join(reports)


def self_test():
    with tempfile.TemporaryDirectory() as temporary:
        directory = pathlib.Path(temporary)
        manifest, valid = [], []
        for case_index, (identifier, stages) in enumerate(CASES.items()):
            start = 100 + case_index * 1000
            filename = f"marker-{case_index}.txt"
            (directory / filename).write_text(str(uuid.uuid4()), encoding="utf-8")
            items = [{"suggestedHumanReadableName": "Installed smoke host-geometry run ID_0_fixture",
                      "exportedFileName": filename, "timestamp": start - .1}]
            valid.append(f"2026-10-14 00:00:00.000 Df FreeShiamyKeyboard[27:a] FreeShiamyKeyboard lifecycle "
                         f"bundle=osku.me.freeshiamyios.keyboard pid=27 hasFullAccess=NO epoch={start + 15:.6f}")
            for index, (stage, active) in enumerate(stages):
                name = f"case-{case_index}-{index}.png"
                (directory / name).write_bytes(b"portable parser fixture; no native image claim")
                epoch = start + index * 10
                items.append({"suggestedHumanReadableName": stage + " — full screen_0_fixture",
                              "exportedFileName": name, "timestamp": epoch})
                if active:
                    valid.append(f"2026-10-14 00:00:00.000 Df FreeShiamyKeyboard[27:a] [AdaptiveKeyboard] "
                                 f"root=393.0x254.0 requested=254.0 percent=100 category=UICTContentSizeCategoryL "
                                 f"style=light epoch={epoch - 1:.6f}")
            manifest.append({"testIdentifier": identifier, "attachments": items})
        def accepted(lines=None, groups=None):
            (directory / "manifest.json").write_text(json.dumps(manifest if groups is None else groups), encoding="utf-8")
            return check("\n".join(valid if lines is None else lines), directory)[0]
        assert accepted(), "one surviving PID may satisfy both fresh cases"
        split = [line.replace("[27:a]", "[28:a]").replace("pid=27", "pid=28")
                 if logged_epoch(line) > 1000 else line for line in valid]
        assert accepted(split), "separate real PIDs also allowed"
        assert accepted([valid[0].replace("epoch=115.000000", "epoch=50.000000"), *valid])
        assert not accepted([line for line in valid if "epoch=1115.000000" not in line]), "case 2 needs fresh lifecycle even with PID reuse"
        assert not accepted([line for line in valid if not ("[AdaptiveKeyboard]" in line and logged_epoch(line) > 1000)]), "prior-case metrics cannot stand in for current-case observation"
        assert not accepted([line.replace("[27:a]", "[28:a]") if "[AdaptiveKeyboard]" in line else line for line in valid]), "lifecycle and metrics cannot mix PIDs"
        assert not accepted([line.replace("FreeShiamyKeyboard[27:a]", "FreeShiamyKeyboard") for line in valid]), "missing process identity cannot establish evidence"
        for old, new in (("hasFullAccess=NO", "hasFullAccess=YES"), ("pid=27", "pid=29"),
                         ("percent=100", "percent=90"), ("UICTContentSizeCategoryL", "UICTContentSizeCategoryXS"),
                         ("style=light", "style=dark"), ("requested=254.0", "requested=nan"),
                         ("root=393.0x254.0", "root=393.0xinf")):
            assert not accepted([line.replace(old, new) for line in valid]), (old, new)
        for field in FIELDS:
            broken = list(valid)
            broken[1] = re.sub(r"\b" + field + r"=\S+", "", broken[1])
            assert not accepted(broken), field
        for bad in ("0", "-1", "inf", "nan", "malformed"):
            assert not accepted([valid[0], valid[1].replace("requested=254.0", f"requested={bad}"), *valid[2:]])
        later_bad = valid[1].replace("epoch=119.000000", "epoch=119.500000").replace("style=light", "style=dark")
        assert not accepted([*valid, later_bad]), "latest invalid record must supersede earlier valid record"
        other_pid = [line.replace("[27:a]", "[28:a]").replace("pid=27", "pid=28") for line in valid]
        assert not accepted([*valid, *other_pid]), "tied fully satisfying PID appearances are ambiguous"
        # A newer process appearance owns the live keyboard even when the old
        # process has good metrics that would otherwise remain indefinitely valid.
        newer_yes = valid[0].replace("[27:a]", "[28:a]").replace("pid=27", "pid=28").replace("epoch=115.000000", "epoch=125.000000").replace("hasFullAccess=NO", "hasFullAccess=YES")
        newer_bad = valid[1].replace("[27:a]", "[28:a]").replace("epoch=119.000000", "epoch=129.000000").replace("percent=100", "percent=220").replace("UICTContentSizeCategoryL", "UICTContentSizeCategoryXS").replace("style=light", "style=dark")
        assert not accepted([*valid, newer_yes, newer_bad]), "stale good PID cannot mask newer YES/wrong-trait PID"
        newer_no = newer_yes.replace("hasFullAccess=YES", "hasFullAccess=NO")
        newer_good = newer_bad.replace("percent=220", "percent=100").replace("UICTContentSizeCategoryXS", "UICTContentSizeCategoryL").replace("style=dark", "style=light")
        assert not accepted([*valid, newer_no, newer_good]), "within-case PID change fails even with good new metrics"
        for broken in (newer_no.replace("hasFullAccess=NO", "hasFullAccess=MALFORMED"),
                       newer_no.replace("osku.me.freeshiamyios.keyboard", "wrong.bundle"),
                       newer_no.replace("epoch=125.000000", "epoch=nan"),
                       newer_no.replace("FreeShiamyKeyboard[28:a]", "FreeShiamyKeyboard")):
            assert not accepted([*valid, broken]), "new malformed/unscopable appearance must not be filtered out"
        assert not accepted([*valid, valid[0]]), "tied duplicate appearances are ambiguous"
        old_metric_appearance = valid[0].replace("epoch=115.000000", "epoch=129.500000")
        assert not accepted([*valid, old_metric_appearance]), "old same-PID metric cannot satisfy a fresh appearance"
        fresh_metric = valid[2].replace("epoch=129.000000", "epoch=129.700000")
        assert accepted([*valid, old_metric_appearance, fresh_metric]), "same-PID reappearance works with fresh metrics"
        mixed = [valid[0], *valid[1:4],
                 valid[3].replace("epoch=139.000000", "epoch=139.500000").replace("percent=100", "percent=90"),
                 valid[0].replace("[27:a]", "[28:a]").replace("pid=27", "pid=28"),
                 *[line.replace("[27:a]", "[28:a]").replace("pid=27", "pid=28") for line in valid[4:]]]
        assert not accepted(mixed), "partial processes cannot combine"
        assert not accepted(groups=manifest[:1])
        assert not accepted(groups=[*manifest, manifest[0]])
        bad_groups = copy.deepcopy(manifest)
        bad_groups[1]["testIdentifier"] = bad_groups[0]["testIdentifier"]
        assert not accepted(groups=bad_groups)
        for index in range(len(manifest[0]["attachments"])):
            broken = copy.deepcopy(manifest)
            broken[0]["attachments"].pop(index)
            assert not accepted(groups=broken), index
        duplicate = copy.deepcopy(manifest)
        duplicate[1]["attachments"].append(duplicate[1]["attachments"][3])
        assert not accepted(groups=duplicate)
        duplicate_marker = copy.deepcopy(manifest)
        duplicate_marker[0]["attachments"].append(duplicate_marker[0]["attachments"][0])
        assert not accepted(groups=duplicate_marker)
        reordered = copy.deepcopy(manifest)
        reordered[0]["attachments"][4]["timestamp"] = 101
        assert not accepted(groups=reordered)
        for timestamp in (None, True, float("nan"), float("inf"), 0):
            malformed = copy.deepcopy(manifest)
            malformed[0]["attachments"][3]["timestamp"] = timestamp
            assert not accepted(groups=malformed)
        # Invalid post-dismissal geometry cannot invalidate a dismissed-keyboard
        # capture: only active milestones need live metrics.
        post_dismissal = valid[-1].replace("epoch=1219.000000", "epoch=1239.000000").replace("requested=254.0", "requested=nan")
        assert "epoch=1239.000000" in post_dismissal
        assert accepted([*valid, post_dismissal])
    print("installed action per-test capture/process parser self-test passed")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        self_test()
    elif len(sys.argv) == 3:
        try:
            success, report = check(pathlib.Path(sys.argv[1]).read_text(errors="replace"), pathlib.Path(sys.argv[2]))
        except OSError as error:
            sys.exit(f"installed action process log unavailable: {error}")
        print(report)
        sys.exit(0 if success else 1)
    else:
        sys.exit("usage: check-installed-action-process.py LOG ATTACHMENTS | --self-test")
