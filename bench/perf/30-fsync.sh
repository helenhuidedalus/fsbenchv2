#!/usr/bin/env bash
# 30-fsync.sh: fsync latency — 1000 create+fdatasync ops per iteration.
# Reports total time p50/p99 across iterations + per-op p50/p99 (µs).
# Contract: run_test <target_dir> <label> <N>
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

run_test() {
    local target="$1" label="${2:-fsync}" N="${3:-10}"

    hdr "FSYNC LATENCY  (N=$N, 1K creat+fdatasync per iteration)"
    printf "  %-22s%-16s%-16s%-16s%-16s\n" \
        "" "total p50" "total p99" "per-op p50 (µs)" "per-op p99 (µs)"
    sep

    local totals=() per_p50s=() per_p99s=()

    for iter in $(seq 1 "$N"); do
        local result
        result=$(python3 -c "
import os, time
base = '$target/.bench-fsync-$$-$iter'
samples = []
for i in range(1000):
    fd = os.open(f'{base}-{i}', os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
    os.write(fd, b'x' * 128)
    t0 = time.monotonic_ns()
    os.fdatasync(fd)
    t1 = time.monotonic_ns()
    os.close(fd)
    samples.append(t1 - t0)
    os.unlink(f'{base}-{i}')
samples.sort()
n = len(samples)
total_ms = int(sum(samples) / 1e6)
p50_us  = int(samples[min(int(n * 0.50), n-1)] / 1000)
p99_us  = int(samples[min(int(n * 0.99), n-1)] / 1000)
print(total_ms, p50_us, p99_us)
" 2>/dev/null || echo "0 0 0")
        read -r tot p50 p99 <<< "$result"
        totals+=("$tot")
        per_p50s+=("$p50")
        per_p99s+=("$p99")
    done

    read -r tot_p50 tot_p99 <<< "$(printf '%s\n' "${totals[@]}"   | summarize)"
    read -r op_p50  _       <<< "$(printf '%s\n' "${per_p50s[@]}" | summarize)"
    read -r op_p99  _       <<< "$(printf '%s\n' "${per_p99s[@]}" | summarize)"

    row "$label" "${tot_p50}ms" "${tot_p99}ms" "${op_p50}µs" "${op_p99}µs"
}

run_test "$@"
