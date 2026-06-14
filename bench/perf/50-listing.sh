#!/usr/bin/env bash
# 50-listing.sh: Directory listing — ls -la and find -type f on 1000-file dir.
# Contract: run_test <target_dir> <label> <N>
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

run_test() {
    local target="$1" label="${2:-listing}" N="${3:-10}"

    hdr "DIRECTORY LISTING  (1000 files, N=$N)"
    printf "  %-22s%-16s%-16s%-16s%-16s\n" \
        "" "ls-la p50" "ls-la p99" "find p50" "find p99"
    sep

    # Create the fixture once; iterate reads over the same dir.
    local fixture="$target/.bench-ls-fixture-$$"
    mkdir -p "$fixture"
    for i in $(seq 1 1000); do printf x > "$fixture/f$i"; done

    local ls_samples=() find_samples=()

    for iter in $(seq 1 "$N"); do
        local t
        t=$(now_ms); ls -la "$fixture" >/dev/null
        ls_samples+=("$(ms_since "$t")")

        t=$(now_ms); find "$fixture" -type f | wc -l >/dev/null
        find_samples+=("$(ms_since "$t")")
    done

    rm -rf "$fixture"

    read -r ls_p50 ls_p99     <<< "$(printf '%s\n' "${ls_samples[@]}"   | summarize)"
    read -r find_p50 find_p99 <<< "$(printf '%s\n' "${find_samples[@]}" | summarize)"

    row "$label" "${ls_p50}ms" "${ls_p99}ms" "${find_p50}ms" "${find_p99}ms"
}

run_test "$@"
