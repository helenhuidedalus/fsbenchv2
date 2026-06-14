#!/usr/bin/env bash
# TOP-LEVEL orchestrator: runs the perf suite then the correctness suite.
# Usage: bash bench/fs-bench.sh <target_dir>
# Env:   BENCH_N=10  (iterations per test, default 10)
#        BENCH_SKIP_NPM / BENCH_SKIP_TAR / BENCH_SKIP_GIT / BENCH_SKIP_FIO
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BENCH_DIR/lib.sh"

TARGET="${1:?Usage: fs-bench.sh <target_dir>}"
N="${BENCH_N:-10}"

if ! touch "$TARGET/.bench-write-test-$$" 2>/dev/null; then
    echo "ERROR: $TARGET is not writable" >&2
    exit 1
fi
rm -f "$TARGET/.bench-write-test-$$"

# ── System info ───────────────────────────────────────────────────────
echo ""
echo "  FS-BENCH  v2"
sep
row "Host"     "$(hostname)"
row "Kernel"   "$(uname -r)"
row "Date"     "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
row "Node"     "$(node --version 2>/dev/null || echo N/A)"
row "npm"      "$(npm --version 2>/dev/null || echo N/A)"
row "fio"      "$(fio --version 2>/dev/null || echo N/A)"
row "git"      "$(git --version 2>/dev/null | awk '{print $3}' || echo N/A)"
row "python3"  "$(python3 --version 2>/dev/null | awk '{print $2}' || echo N/A)"
row "Target"   "$TARGET"
row "N"        "$N"
# Verify target FS type for baseline awareness
row "FS-type"  "$(df -T "$TARGET" 2>/dev/null | awk 'NR==2{print $2}' || echo N/A)"
sep

# ── Perf suite ────────────────────────────────────────────────────────
for module in "$BENCH_DIR"/perf/[0-9][0-9]-*.sh; do
    [ -f "$module" ] || continue
    label="$(basename "$module" .sh | sed 's/^[0-9]*-//')"
    bash "$module" "$TARGET" "$label" "$N"
done

# ── Correctness suite ─────────────────────────────────────────────────
bash "$BENCH_DIR/correctness/runner.sh" "$TARGET"

echo ""
sep
echo "  Done."
echo ""
