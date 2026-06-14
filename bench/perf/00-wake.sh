#!/usr/bin/env bash
# 00-wake.sh: Machine wake time — uptime since boot + time-to-first-FS-op.
# N is ignored; uptime is a one-time machine property.
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

run_test() {
    local target="$1" label="${2:-wake}" _N="${3:-1}"

    hdr "WAKE TIME"
    printf "  %-22s%-16s%-16s\n" "" "uptime" "first-FS-op"
    sep

    local uptime_ms="N/A"
    if [ -f /proc/uptime ]; then
        uptime_ms="$(awk '{printf "%dms", $1 * 1000}' /proc/uptime)"
    fi

    local t; t=$(now_ms)
    echo x > "$target/.bench-wake-$$"
    rm -f "$target/.bench-wake-$$"
    local ready_ms; ready_ms=$(ms_since "$t")

    row "$label" "$uptime_ms" "${ready_ms}ms"
}

run_test "$@"
