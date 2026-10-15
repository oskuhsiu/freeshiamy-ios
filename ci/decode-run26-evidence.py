#!/usr/bin/env python3
"""Pin and safely extract the two retained run-26 installed failures."""

import hashlib
import json
import pathlib
import shutil
import stat
import sys
import zipfile

RUN_ID = 38668884961
ATTEMPT = 1
SOURCE_SHA = "7eb7dc50b36cc3032701f59d933b93efecb5ae55"
CASES = {
    "iphone220": {
        "artifactId": 11944580203,
        "artifactName": "ios-simulator-iphone-height-220-38668884961-1",
        "bytes": 140776419,
        "sha256": "c2c2115ac9e3de3a40b36c8b19ef368afeface6339ee4d4a138ca71c1587da21",
        "stage": "installed-extension",
    },
    "ipad90": {
        "artifactId": 11944157161,
        "artifactName": "ios-simulator-ipad-height-90-38668884961-1",
        "bytes": 159297551,
        "sha256": "c37fe22d897b0c11eb2ddd71e8adac59d4fcc7773f027470725f4f85abab88d2",
        "stage": "installed-adaptive-ax",
        "extraFiles": ("installed-ax-runner-host-launch.log",
                       "installed-ax-stage-start.txt", "installed-ax-stage-end.txt"),
    },
}


def require(actual, expected, label):
    if actual != expected:
        raise ValueError(f"{label}: expected {expected!r}, got {actual!r}")


def safe_member(name):
    path = pathlib.PurePosixPath(name)
    return bool(name and not name.startswith("/") and "\\" not in name
                and all(part not in ("", ".", "..") for part in path.parts))


def verify_extract(case_name, run_file, artifact_file, zip_file, output):
    if case_name not in CASES:
        raise ValueError(f"Unknown retained case: {case_name!r}")
    case = CASES[case_name]
    artifact_id = case["artifactId"]
    stage = case["stage"]
    run = json.loads(run_file.read_text())
    artifact_data = json.loads(artifact_file.read_text())
    artifacts = artifact_data.get("artifacts", [artifact_data])
    matches = [item for item in artifacts if item.get("id") == artifact_id]
    require(len(matches), 1, "artifact metadata match count")
    artifact = matches[0]
    require(run.get("id"), RUN_ID, "run ID")
    require(run.get("run_attempt"), ATTEMPT, "run attempt")
    require(run.get("head_sha"), SOURCE_SHA, "source SHA")
    require(artifact.get("id"), artifact_id, "artifact ID")
    require(artifact.get("name"), case["artifactName"], "artifact name")
    require(artifact.get("size_in_bytes"), case["bytes"], "artifact size")
    require(artifact.get("digest"), "sha256:" + case["sha256"], "artifact metadata digest")
    require(artifact.get("expired"), False, "artifact expiry state")
    workflow = artifact.get("workflow_run") or {}
    require(workflow.get("id"), RUN_ID, "artifact workflow run ID")
    require(workflow.get("head_sha"), SOURCE_SHA, "artifact source SHA")
    require(zip_file.stat().st_size, case["bytes"], "retained ZIP bytes")
    digest = hashlib.sha256()
    with zip_file.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    require(digest.hexdigest(), case["sha256"], "retained ZIP SHA-256")

    extracted = output / "extracted"
    extracted.mkdir()
    result_prefix = stage + ".xcresult/"
    xcodebuild_log = stage + "-xcodebuild.log"
    count = 0
    seen = set()
    with zipfile.ZipFile(zip_file) as archive:
        for member in archive.infolist():
            name = member.filename
            if not safe_member(name) or name in seen:
                raise ValueError(f"Unsafe or duplicate ZIP path: {name!r}")
            seen.add(name)
            if stat.S_ISLNK(member.external_attr >> 16):
                raise ValueError(f"ZIP symlink refused: {name!r}")
            if not (name.startswith(result_prefix) or name == xcodebuild_log or
                    name in case.get("extraFiles", ()) or
                    (name.startswith(stage + "-") and name.endswith((".log", ".txt"))
                     and "/" not in name)):
                continue
            destination = extracted.joinpath(*pathlib.PurePosixPath(name).parts)
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(member) as source, destination.open("xb") as target:
                shutil.copyfileobj(source, target)
            count += 1
    result = extracted / result_prefix.rstrip("/")
    if not (result / "Info.plist").is_file() or not (result / "database.sqlite3").is_file():
        raise ValueError(f"Exact {stage}.xcresult bundle missing or incomplete")
    if not (extracted / xcodebuild_log).is_file():
        raise ValueError(f"Retained {stage} xcodebuild log missing")
    record = {
        "purpose": "retained run-26 diagnostics only; no test execution or acceptance claim",
        "runId": RUN_ID, "runAttempt": ATTEMPT, "sourceSha": SOURCE_SHA,
        "case": case_name, "artifactId": artifact_id, "artifactName": case["artifactName"],
        "artifactBytes": case["bytes"], "artifactSha256": digest.hexdigest(),
        "extractedFileCount": count, "stage": stage,
        "source": "GitHub Actions artifact metadata and retained ZIP",
    }
    (output / "verified-source.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps(record, indent=2))


def self_test():
    assert safe_member("installed-extension.xcresult/Info.plist")
    for path in ("/absolute", "../escape", "bundle/../escape", "bundle\\bad", ""):
        assert not safe_member(path), path
    assert set(CASES) == {"iphone220", "ipad90"}
    assert CASES["iphone220"]["stage"] != CASES["ipad90"]["stage"]
    print("run26 ZIP path guard self-test passed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif len(sys.argv) == 6:
        try:
            verify_extract(sys.argv[1], *(pathlib.Path(arg) for arg in sys.argv[2:]))
        except (OSError, ValueError, zipfile.BadZipFile) as error:
            raise SystemExit(str(error))
    else:
        raise SystemExit("usage: decode-run26-evidence.py CASE RUN_JSON ARTIFACT_JSON RAW_ZIP OUTPUT_DIR")
