#!/usr/bin/env bash
# random-delay.sh: Sleep a uniform random offset before the benchmark starts.
#
# Purpose: prevent any provider from pre-warming capacity for a known slot.
# Called as the first step of .github/workflows/benchmark.yml before run.sh.
#
# Usage:
#   bash scheduler/random-delay.sh [window_seconds]
#   window_seconds defaults to 3600 (1 hour).
#
# The GitHub Actions `schedule:` cron fires on a fixed cadence.  This script
# adds a random offset drawn from U[0, window_seconds] so the real start time
# is uniformly distributed across the window.
set -euo pipefail

WINDOW="${1:-3600}"

# $RANDOM is 0..32767; scale to [0, WINDOW].
delay=$(( RANDOM * WINDOW / 32767 ))

echo "random-delay: sleeping ${delay}s (window=${WINDOW}s)"
sleep "$delay"
echo "random-delay: done"
