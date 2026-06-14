#!/usr/bin/env bash
# 10-metadata.sh: Metadata microbenchmarks — 1K creates/stats/reads, 100 mkdirs.
# Contract: run_test <target_dir> <label> <N>
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

run_test() {
    local target="$1" label="${2:-metadata}" N="${3:-10}"

    hdr "METADATA OPS  (N=$N, reporting p50/p99 across iterations)"
    printf "  %-22s%-16s%-16s%-16s%-16s%-16s\n" \
        "" "1K-creates p50" "p99" "1K-stats p50" "1K-reads p50" "100-mkdirs p50"
    sep

    local creates=() stats_t=() reads=() mkdirs=()

    for iter in $(seq 1 "$N"); do
        local w="$target/.bench-meta-$$-$iter"
        mkdir -p "$w"

        local t
        t=$(now_ms)
        for i in $(seq 1 1000); do printf x > "$w/f$i"; done
        creates+=("$(ms_since "$t")")

        t=$(now_ms)
        for i in $(seq 1 1000); do stat "$w/f$i" >/dev/null; done
        stats_t+=("$(ms_since "$t")")

        t=$(now_ms)
        for i in $(seq 1 1000); do cat "$w/f$i" >/dev/null; done
        reads+=("$(ms_since "$t")")

        t=$(now_ms)
        for i in $(seq 1 100); do mkdir "$w/d$i"; done
        mkdirs+=("$(ms_since "$t")")

        rm -rf "$w"
    done

    read -r c_p50 c_p99 <<< "$(printf '%s\n' "${creates[@]}"  | summarize)"
    read -r s_p50 _     <<< "$(printf '%s\n' "${stats_t[@]}"  | summarize)"
    read -r r_p50 _     <<< "$(printf '%s\n' "${reads[@]}"    | summarize)"
    read -r m_p50 _     <<< "$(printf '%s\n' "${mkdirs[@]}"   | summarize)"

    row "$label" "${c_p50}ms" "${c_p99}ms" "${s_p50}ms" "${r_p50}ms" "${m_p50}ms"
}

run_test "$@"
