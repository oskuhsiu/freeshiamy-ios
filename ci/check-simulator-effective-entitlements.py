#!/usr/bin/env python3
"""Read the arm64 Mach-O Simulator-effective __TEXT,__entitlements section."""

import hashlib
import json
import pathlib
import plistlib
import struct
import sys
import tempfile

MAGIC64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
MH_EXECUTE = 2
LC_SEGMENT_64 = 0x19
LC_BUILD_VERSION = 0x32
PLATFORM_IOSSIMULATOR = 7
GROUP_KEY = "com.apple.security.application-groups"
EXPECTED_GROUP = "group.osku.me.freeshiamy_ios"
HEADER = struct.Struct("<IiiIIIII")
SEGMENT = struct.Struct("<II16sQQQQiiII")
SECTION = struct.Struct("<16s16sQQIIIIIIII")
BUILD_VERSION = struct.Struct("<IIIIII")


def name(raw):
    return raw.split(b"\0", 1)[0]


def extract(raw):
    if len(raw) < HEADER.size:
        raise ValueError("Mach-O header truncated")
    magic, cpu, _, filetype, ncmds, sizeofcmds, _, _ = HEADER.unpack_from(raw)
    if magic != MAGIC64 or cpu != CPU_TYPE_ARM64 or filetype != MH_EXECUTE:
        raise ValueError("Expected thin little-endian arm64 MH_EXECUTE Mach-O")
    commands_end = HEADER.size + sizeofcmds
    if commands_end > len(raw) or ncmds > sizeofcmds // 8:
        raise ValueError("Mach-O load-command table exceeds file")
    cursor = HEADER.size
    matches = {b"__entitlements": [], b"__ents_der": []}
    platforms = []
    for _ in range(ncmds):
        if cursor + 8 > commands_end:
            raise ValueError("Mach-O load command truncated")
        command, command_size = struct.unpack_from("<II", raw, cursor)
        if command_size < 8 or cursor + command_size > commands_end:
            raise ValueError("Mach-O load command has invalid size")
        if command == LC_BUILD_VERSION:
            if command_size < BUILD_VERSION.size:
                raise ValueError("arm64 LC_BUILD_VERSION command truncated")
            platforms.append(BUILD_VERSION.unpack_from(raw, cursor)[2])
        if command == LC_SEGMENT_64:
            if command_size < SEGMENT.size:
                raise ValueError("arm64 segment command truncated")
            segment = SEGMENT.unpack_from(raw, cursor)
            segment_name = name(segment[2])
            file_offset, file_size, section_count = segment[5], segment[6], segment[9]
            if SEGMENT.size + section_count * SECTION.size > command_size:
                raise ValueError("arm64 section table truncated")
            for section_index in range(section_count):
                entry = SECTION.unpack_from(raw, cursor + SEGMENT.size + section_index * SECTION.size)
                section_name, section_segment = name(entry[0]), name(entry[1])
                if section_name not in matches or section_segment != b"__TEXT":
                    continue
                if segment_name != b"__TEXT":
                    raise ValueError("Entitlements section is in a non-__TEXT segment")
                size, offset = entry[3], entry[4]
                if (not size or offset < file_offset or offset + size > file_offset + file_size
                        or offset + size > len(raw)):
                    raise ValueError("Entitlements section bytes are outside the __TEXT file range")
                matches[section_name].append((offset, size, raw[offset:offset + size]))
        cursor += command_size
    if cursor != commands_end:
        raise ValueError("Mach-O load commands do not consume declared command table")
    if platforms != [PLATFORM_IOSSIMULATOR]:
        raise ValueError(f"Expected one iOS Simulator LC_BUILD_VERSION platform 7; found {platforms}")
    if len(matches[b"__entitlements"]) != 1 or len(matches[b"__ents_der"]) > 1:
        raise ValueError("Expected one __TEXT,__entitlements and at most one __TEXT,__ents_der section")
    return matches[b"__entitlements"][0], (matches[b"__ents_der"][0] if matches[b"__ents_der"] else None)


def parse_plist(raw):
    try:
        value = plistlib.loads(raw.rstrip(b"\0"))
    except (ValueError, TypeError, plistlib.InvalidFileException) as error:
        raise ValueError("Effective entitlements section is not a readable plist") from error
    if not isinstance(value, dict):
        raise ValueError("Effective entitlements plist is not a dictionary")
    return value


def group_is_exact(plist):
    return plist.get(GROUP_KEY) == [EXPECTED_GROUP]


def verify(executable, source_plist, output):
    source_raw = source_plist.read_bytes()
    source = parse_plist(source_raw)
    if not group_is_exact(source):
        raise ValueError("Source entitlements do not declare exactly the pinned App Group")
    binary = executable.read_bytes()
    (offset, size, payload), der = extract(binary)
    output.mkdir(parents=True, exist_ok=True)
    (output / "effective-entitlements-section.bin").write_bytes(payload)
    if der is not None:
        (output / "effective-entitlements-der-section.bin").write_bytes(der[2])
    effective = parse_plist(payload)
    xml = plistlib.dumps(effective, fmt=plistlib.FMT_XML, sort_keys=True)
    (output / "effective-entitlements.plist").write_bytes(xml)
    record = {
        "architecture": "arm64 thin Mach-O",
        "platform": "iOS Simulator (LC_BUILD_VERSION platform 7)",
        "executable": str(executable),
        "executableSha256": hashlib.sha256(binary).hexdigest(),
        "sourceEntitlements": str(source_plist),
        "sourceEntitlementsSha256": hashlib.sha256(source_raw).hexdigest(),
        "effectiveSectionOffset": offset,
        "effectiveSectionBytes": size,
        "effectiveSectionSha256": hashlib.sha256(payload).hexdigest(),
        "effectiveDerSectionOffset": der[0] if der is not None else None,
        "effectiveDerSectionBytes": der[1] if der is not None else None,
        "effectiveDerSectionSha256": hashlib.sha256(der[2]).hexdigest() if der is not None else None,
        "effectiveGroup": effective.get(GROUP_KEY),
        "expectedGroup": EXPECTED_GROUP,
        "effectiveGroupExact": group_is_exact(effective),
    }
    (output / "effective-identity.json").write_text(json.dumps(record, indent=2) + "\n")
    if not group_is_exact(effective):
        raise ValueError("Built executable's Simulator-effective App Group is missing or differs from source")
    print(json.dumps(record, indent=2))


def fake_macho(payload, *, section_name=b"__entitlements", offset_delta=0,
               cpu=CPU_TYPE_ARM64, platform=PLATFORM_IOSSIMULATOR, filetype=MH_EXECUTE,
               der=None):
    section_count = 2 if der is not None else 1
    section_offset = HEADER.size + SEGMENT.size + SECTION.size * section_count + BUILD_VERSION.size
    full_payload = b"\0" * offset_delta + payload
    if der is not None:
        full_payload += der
    segment = SEGMENT.pack(LC_SEGMENT_64, SEGMENT.size + SECTION.size * section_count,
                           b"__TEXT\0".ljust(16, b"\0"), 0, len(full_payload) + section_offset,
                           0, len(full_payload) + section_offset, 7, 5, section_count, 0)
    section = SECTION.pack(section_name.ljust(16, b"\0"), b"__TEXT\0".ljust(16, b"\0"),
                           0, len(payload), section_offset + offset_delta, 0, 0, 0, 0, 0, 0, 0)
    if der is not None:
        section += SECTION.pack(b"__ents_der\0".ljust(16, b"\0"),
                                b"__TEXT\0".ljust(16, b"\0"), 0, len(der),
                                section_offset + offset_delta + len(payload), 0, 0, 0, 0, 0, 0, 0)
    build_version = BUILD_VERSION.pack(LC_BUILD_VERSION, BUILD_VERSION.size, platform, 0, 0, 0)
    header = HEADER.pack(MAGIC64, cpu, 0, filetype, 2, len(segment) + len(section) + len(build_version), 0, 0)
    return header + segment + section + build_version + full_payload


def self_test():
    good = plistlib.dumps({GROUP_KEY: [EXPECTED_GROUP]}, fmt=plistlib.FMT_XML)
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        executable, source = root / "app", root / "source.entitlements"
        source.write_bytes(good)
        executable.write_bytes(fake_macho(good, der=b"synthetic DER"))
        verify(executable, source, root / "positive")
        assert (root / "positive" / "effective-entitlements-der-section.bin").read_bytes() == b"synthetic DER"
        failures = (
            ("missing section", fake_macho(good, section_name=b"__not_entitled")),
            ("wrong CPU", fake_macho(good, cpu=7)),
            ("wrong filetype", fake_macho(good, filetype=6)),
            ("device platform", fake_macho(good, platform=2)),
            ("truncated payload", fake_macho(good)[:-1]),
            ("wrong group", fake_macho(plistlib.dumps({GROUP_KEY: ["group.other"]}))),
            ("malformed plist", fake_macho(b"not a plist")),
        )
        for label, binary in failures:
            executable.write_bytes(binary)
            try:
                verify(executable, source, root / label)
            except ValueError:
                pass
            else:
                raise AssertionError(f"Synthetic {label} executable was accepted")
    print("arm64 Mach-O effective-entitlements self-tests passed")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif len(sys.argv) == 4:
        try:
            verify(*(pathlib.Path(arg) for arg in sys.argv[1:]))
        except (OSError, ValueError) as error:
            raise SystemExit(str(error))
    else:
        raise SystemExit("usage: check-simulator-effective-entitlements.py EXECUTABLE SOURCE_PLIST OUTPUT_DIR")
