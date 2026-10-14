#!/bin/bash
# Native macOS Foundation microbenchmark. Run from any directory on macOS.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-$repo/ci-artifacts/lookup-benchmark}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This benchmark requires native macOS Foundation and Apple clang" >&2
    exit 2
fi
export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
if [[ ! -d "$DEVELOPER_DIR" ]]; then
    echo "Required Xcode 26.2 is unavailable: $DEVELOPER_DIR" >&2
    exit 2
fi

# Actions' default depth-one checkout omits the pinned comparison commits.
if git -C "$repo" rev-parse --is-shallow-repository | grep -qx true; then
    git -C "$repo" fetch --no-tags --unshallow origin
fi

resources="$tmp/Corpus.bundle/Contents/Resources"
mkdir -p "$resources"
cp "$repo/FreeShiamyKeyboard/Resources/freeshiamy.cin" "$resources/"
cp "$repo/FreeShiamyKeyboard/Resources/cht_spells.cin" "$resources/"
cat > "$tmp/Corpus.bundle/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.freeshiamy.lookupbenchmark</string><key>CFBundleName</key><string>Corpus</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>
EOF

{
    printf 'platform\t%s\n' "$(sw_vers -productVersion)"
    printf 'architecture\t%s\n' "$(uname -m)"
    printf 'compiler\t%s\n' "$(xcrun clang --version | head -n 1)"
    printf 'xcode\t%s\n' "$(xcodebuild -version | tr '\n' ' ')"
    printf 'macos_sdk\t%s\n' "$(xcrun --sdk macosx --show-sdk-version)"
    printf 'flags\t%s\n' '-O2 -fobjc-arc -framework Foundation'
    printf 'current_commit\t%s\n' "$(git -C "$repo" rev-parse HEAD)"
    printf 'current_tree\t%s\n' "$(git -C "$repo" rev-parse HEAD^{tree})"
    printf 'worktree_dirty\t%s\n' "$(if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then echo yes; else echo no; fi)"
    printf 'master_commit\t%s\n' "$(git -C "$repo" rev-parse 2d449c3)"
    printf 'master_tree\t%s\n' "$(git -C "$repo" rev-parse 2d449c3^{tree})"
    printf 'preopt_commit\t%s\n' "$(git -C "$repo" rev-parse 00ccc553d45aa4ec5bc96f04f977bed365e2a719)"
    printf 'preopt_tree\t%s\n' "$(git -C "$repo" rev-parse 00ccc553d45aa4ec5bc96f04f977bed365e2a719^{tree})"
    shasum -a 256 "$resources"/*.cin "$repo/Benchmarks/lookup_benchmark.m"
} > "$output/identity.txt"

for variant in master preopt optimized; do
    source_dir="$tmp/$variant"
    mkdir -p "$source_dir"
    case "$variant" in
        master) ref=2d449c3 ;;
        preopt) ref=00ccc553d45aa4ec5bc96f04f977bed365e2a719 ;;
        optimized) ref=current ;;
    esac
    for file in FSHCandidate.h FSHCandidate.m FSHCinParser.h FSHCinParser.m FSHShiamyEngine.h FSHShiamyEngine.m; do
        if [[ "$ref" == current ]]; then
            cp "$repo/Shared/$file" "$source_dir/$file"
        else
            git -C "$repo" show "$ref:Shared/$file" > "$source_dir/$file"
        fi
    done
    shasum -a 256 "$source_dir"/* > "$output/$variant-sources.sha256"
    xcrun clang -O2 -fobjc-arc -framework Foundation -I "$source_dir" \
        "$repo/Benchmarks/lookup_benchmark.m" \
        "$source_dir/FSHCandidate.m" "$source_dir/FSHCinParser.m" \
        "$source_dir/FSHShiamyEngine.m" -o "$tmp/$variant-benchmark"
    shasum -a 256 "$tmp/$variant-benchmark" > "$output/$variant-binary.sha256"
done

# Interleave variants to reduce thermal/time-of-run bias. Every call below
# starts a fresh process and constructs its first engine; disk caches may be warm.
for variant in master preopt optimized; do
    : > "$output/$variant-measurements.tsv"
done
for round in 1 2 3; do
    for variant in master preopt optimized; do
        "$tmp/$variant-benchmark" "$tmp/Corpus.bundle" --measure \
            >> "$output/$variant-measurements.tsv"
    done
done
for variant in master preopt optimized; do
    "$tmp/$variant-benchmark" "$tmp/Corpus.bundle" --verify "$output/$variant-results.bin" \
        > "$output/$variant-verification.tsv"
    shasum -a 256 "$output/$variant-results.bin" > "$output/$variant-results.sha256"
done

if cmp -s "$output/preopt-results.bin" "$output/optimized-results.bin"; then
    echo 'preopt_vs_optimized_ordered_results_and_exact_counts=identical' | tee "$output/equivalence.txt"
else
    echo 'preopt_vs_optimized_ordered_results_and_exact_counts=DIFFERENT' | tee "$output/equivalence.txt" >&2
    exit 1
fi
echo 'master outputs may differ due to intentional parser/dedup fixes' >> "$output/equivalence.txt"

python3 - "$output" <<'PY' | tee "$output/summary.txt"
import pathlib, statistics, sys
root = pathlib.Path(sys.argv[1])
measurements = {}
for variant in ('master', 'preopt', 'optimized'):
    data = {}
    for line in (root / f'{variant}-measurements.tsv').read_text().splitlines():
        key, value = line.split('\t', 1)
        data.setdefault(key, []).append(float(value))
    measurements[variant] = data
    print(f'{variant}: fresh-process engine load median={statistics.median(data["load_ms"]):.3f} ms, '
          f'process resident_after_load median={statistics.median(data["resident_after_load_bytes"]) / 1048576:.2f} MiB, '
          f'peak_measurement_process median (load+corpus+queries)={statistics.median(data["peak_final_bytes"]) / 1048576:.2f} MiB, '
          f'queries={int(data["query_count"][0])}, checksum={int(data["checksum"][0])}')
    for batch in ('one', 'two', 'deep'):
        samples = sorted(data[f'sample_ms_{batch}'])
        p95 = samples[min(len(samples) - 1, int(.95 * len(samples) + .999999) - 1)]
        print(f'  {batch} batch: queries={int(data[f"batch_count_{batch}"][0])}, '
              f'median total={statistics.median(samples):.3f} ms, p95 total={p95:.3f} ms')
for batch in ('one', 'two', 'deep'):
    after = statistics.median(measurements['optimized'][f'sample_ms_{batch}'])
    for baseline in ('master', 'preopt'):
        before = statistics.median(measurements[baseline][f'sample_ms_{batch}'])
        print(f'{batch} optimized/{baseline} median batch-time ratio={after / before:.3f}')
for metric in ('load_ms', 'resident_after_load_bytes', 'peak_final_bytes'):
    after = statistics.median(measurements['optimized'][metric])
    for baseline in ('master', 'preopt'):
        before = statistics.median(measurements[baseline][metric])
        print(f'{metric} optimized/{baseline} median ratio={after / before:.3f}')
PY

echo "Artifacts: $output"
