#!/usr/bin/env bash
# Shared utilities for all fs-bench test modules.
# Source this file at the top of every bench/perf/*.sh and bench/correctness/*.sh.

# GNU date supports %3N (milliseconds); BSD/macOS date does not.
# Python 3 is already required by the benchmark, so use it unconditionally.
now_ms() { python3 -c "import time; print(int(time.time()*1000))"; }
ms_since() { echo $(( $(now_ms) - $1 )); }

COL="%-22s"

sep() { printf '%0.s─' {1..78}; echo; }

hdr() {
    echo ""
    echo "  $1"
    sep
}

row() {
    local label="$1"; shift
    printf "  $COL" "$label"
    for v in "$@"; do printf "%-16s" "$v"; done
    echo ""
}

# summarize: read whitespace-separated integers from stdin, print "p50 p99" (integers)
summarize() {
    python3 -c "
import sys
vals = sorted(float(x) for x in sys.stdin.read().split() if x.strip())
if not vals:
    print('N/A N/A')
else:
    n = len(vals)
    p = lambda pct: vals[min(int(n * pct / 100), n - 1)]
    print(f'{p(50):.0f} {p(99):.0f}')
"
}

have_root() { [ "$(id -u)" -eq 0 ]; }
