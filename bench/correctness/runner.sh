#!/usr/bin/env bash
# correctness/runner.sh: Dispatch pjdfstest and xfstests; aggregate results.
# Correctness suites run ONCE (not N times) and emit pass/skip/fail counts.
# Some suites require root — each sub-runner checks and skips if absent.
# Usage: bash bench/correctness/runner.sh <target_dir>
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

TARGET="${1:?Usage: runner.sh <target_dir>}"

hdr "CORRECTNESS SUITES  (run once; may require root)"
printf "  %-22s%-12s%-12s%-12s%-16s\n" "" "passed" "skipped" "failed" "notes"
sep

for suite in "$BENCH_DIR"/correctness/pjdfstest.sh "$BENCH_DIR"/correctness/xfstests.sh; do
    [ -f "$suite" ] && bash "$suite" "$TARGET"
done

sep
