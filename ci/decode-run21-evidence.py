#!/usr/bin/env python3
"""Verify and safely extract one of two pinned retained run-21 XCTest bundles."""

import hashlib
import json
import pathlib
import shutil
import stat
import sys
import zipfile

RUN_ID = 38660719039
ATTEMPT = 1
SOURCE_SHA = "b0ee7ea823d736e625aca40e527dfabd131f4f09"
CASES = {
    "ipad90": {
        "artifactId": 11938853295,
        "artifactName": "ios-simulator-ipad-height-90-38660719039-1",
        "sha256": "d8c7f4c5836a196315bc60a5e6a4958f68b5ccfc107f41377d4a3c4f0b2ac177",
        "bytes": 143516546,
        "stage": "installed-adaptive-ax",
    },
    "iphone220": {
        "artifactId": 11939791339,
        "artifactName": "ios-simulator-iphone-height-220-38660719039-1",
        "sha256": "614cf355a988b90fd067d944498c2e74aef9684d0676bcf49cad22d63074e2da",
        "bytes": 190655787,
        "stage": "installed-height-ax220",
    },
}


def die(message):
    raise SystemExit(message)


def require(actual, expected, label):
    if actual != expected:
        die(f"{label}: expected {expected!r}, got {actual!r}")


def safe_member(name):
    path = pathlib.PurePosixPath(name)
    return (name and not name.startswith("/") and "\\" not in name
            and all(part not in ("", ".", "..") for part in path.parts))


def verify_extract(case_name, run_file, artifact_file, zip_file, output):
    if case_name not in CASES:
        die(f"Unknown pinned case: {case_name!r}")
    case = CASES[case_name]
    artifact_id = case["artifactId"]
    stage = case["stage"]
    result_prefix = stage + ".xcresult/"
    xcodebuild_log = stage + "-xcodebuild.log"
    run = json.loads(run_file.read_text())
    artifact_data = json.loads(artifact_file.read_text())
    artifact = artifact_data.get("artifacts", [artifact_data])
    artifact = [item for item in artifact if item.get("id") == artifact_id]
    require(len(artifact), 1, "artifact metadata match count")
    artifact = artifact[0]
    require(run.get("id"), RUN_ID, "run ID")
    require(run.get("run_attempt"), ATTEMPT, "run attempt")
    require(run.get("head_sha"), SOURCE_SHA, "source SHA")
    require(artifact.get("id"), artifact_id, "artifact ID")
    require(artifact.get("name"), case["artifactName"], "artifact name")
    require(artifact.get("size_in_bytes"), case["bytes"], "artifact size")
    require(artifact.get("digest"), "sha256:" + case["sha256"], "GitHub artifact digest")
    require(artifact.get("expired"), False, "artifact expiry state")
    workflow = artifact.get("workflow_run") or {}
    require(workflow.get("id"), RUN_ID, "artifact workflow run ID")
    require(workflow.get("head_sha"), SOURCE_SHA, "artifact source SHA")
    size = zip_file.stat().st_size
    require(size, case["bytes"], "downloaded ZIP size")
    digest = hashlib.sha256()
    with zip_file.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    require(digest.hexdigest(), case["sha256"], "downloaded ZIP SHA-256")

    extracted = output / "extracted"
    extracted.mkdir()
    count = 0
    seen = set()
    with zipfile.ZipFile(zip_file) as archive:
        for member in archive.infolist():
            name = member.filename
            if not safe_member(name):
                die(f"Unsafe ZIP path: {name!r}")
            if name in seen:
                die(f"Duplicate ZIP path: {name!r}")
            seen.add(name)
            mode = member.external_attr >> 16
            if stat.S_ISLNK(mode):
                die(f"ZIP symlink refused: {name!r}")
            if not (name.startswith(result_prefix) or name == xcodebuild_log or
                    (name.startswith(stage + "-") and name.endswith((".log", ".txt")) and "/" not in name)):
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
        die("The exact installed-adaptive-ax.xcresult bundle is missing or incomplete")
    if not (extracted / xcodebuild_log).is_file():
        die(f"The retained {stage} xcodebuild log is missing")
    record = {
        "purpose": "retained run-21 diagnostic decoding only; no test execution or acceptance claim",
        "case": case_name,
        "runId": RUN_ID,
        "runAttempt": ATTEMPT,
        "sourceSha": SOURCE_SHA,
        "artifactId": artifact_id,
        "artifactName": case["artifactName"],
        "artifactBytes": size,
        "artifactSha256": digest.hexdigest(),
        "extractedFileCount": count,
        "stage": stage,
        "source": "GitHub Actions artifact metadata and retained ZIP",
    }
    (output / "verified-source.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 6:
        die("usage: decode-run21-evidence.py CASE RUN_JSON ARTIFACT_JSON RAW_ZIP OUTPUT_DIR")
    verify_extract(sys.argv[1], *(pathlib.Path(arg) for arg in sys.argv[2:]))
