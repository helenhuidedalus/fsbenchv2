#!/usr/bin/env bash
# 90-fio.sh: fio I/O benchmarks — 4K randread, 4K randwrite+fsync, 1M seqwrite.
# fio tests are long-running; N is ignored — run once each (30s per job).
# Contract: run_test <target_dir> <label> <N>
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

run_test() {
    local target="$1" label="${2:-fio}" _N="${3:-1}"

    if ! command -v fio &>/dev/null || [ "${BENCH_SKIP_FIO:-}" = "1" ]; then
        hdr "FIO  (skipped — fio not found)"
        return
    fi

    hdr "FIO  (30s each)"
    printf "  %-22s%-16s%-16s%-16s\n" "" "4K randread" "4K rw+fsync" "1M seqwrite"
    sep

    local w="$target/.bench-fio-$$"
    mkdir -p "$w"

    local rr rw sw

    rr=$(fio --name=rr --directory="$w" --rw=randread --bs=4k \
        --numjobs=4 --size=256M --runtime=30 --time_based \
        --group_reporting --output-format=json 2>/dev/null \
        | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"{d['jobs'][0]['read']['iops']:.0f} IOPS\")
" 2>/dev/null || echo "N/A")

    rw=$(fio --name=rw --directory="$w" --rw=randwrite --bs=4k \
        --numjobs=4 --size=256M --runtime=30 --time_based \
        --fsync=1 --group_reporting --output-format=json 2>/dev/null \
        | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"{d['jobs'][0]['write']['iops']:.0f} IOPS\")
" 2>/dev/null || echo "N/A")

    sw=$(fio --name=sw --directory="$w" --rw=write --bs=1M \
        --numjobs=1 --size=1G --runtime=30 --time_based \
        --group_reporting --output-format=json 2>/dev/null \
        | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f\"{d['jobs'][0]['write']['bw'] / 1024:.0f} MiB/s\")
" 2>/dev/null || echo "N/A")

    row "$label" "$rr" "$rw" "$sw"
    rm -rf "$w"
}

run_test "$@"
