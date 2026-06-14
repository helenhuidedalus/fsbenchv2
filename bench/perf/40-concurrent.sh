#!/usr/bin/env bash
# 40-concurrent.sh: Concurrent N-way file creation — 1000 files split across workers.
# Contract: run_test <target_dir> <label> <N>
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

CONC="${BENCH_CONCURRENCY:-4}"

run_test() {
    local target="$1" label="${2:-concurrent}" N="${3:-10}"

    hdr "CONCURRENT ${CONC}-WAY CREATE  (1000 files, N=$N)"
    printf "  %-22s%-16s%-16s\n" "" "wall-time p50" "wall-time p99"
    sep

    local samples=()
    local per=$(( 1000 / CONC ))

    for iter in $(seq 1 "$N"); do
        local w="$target/.bench-conc-$$-$iter"
        mkdir -p "$w"

        local t; t=$(now_ms)
        for j in $(seq 1 "$CONC"); do
            (
                start=$(( (j-1) * per + 1 ))
                end=$(( j * per ))
                for i in $(seq "$start" "$end"); do printf x > "$w/f$i"; done
            ) &
        done
        wait
        samples+=("$(ms_since "$t")")

        rm -rf "$w"
    done

    read -r p50 p99 <<< "$(printf '%s\n' "${samples[@]}" | summarize)"
    row "$label" "${p50}ms" "${p99}ms"
}

run_test "$@"
