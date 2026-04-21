#!/usr/bin/env bash
# Filesystem benchmark for cloud dev environment workloads.
#
# Measures: npm install, file creates, stats, reads, mkdirs, tar extract.
# Output: tab-separated table to stdout, human summary at the end.
#
# Prerequisites:
#   - node/npm in PATH
#   - curl (for tar download)
#   - write access to the target directory
#
# Usage:
#   bash fs-bench.sh /path/to/mount             # benchmark one mount
#   bash fs-bench.sh /path/to/mount --baseline   # also run ext4 baseline on /tmp
#
# Environment:
#   BENCH_RUNS=1          Number of npm install iterations (default 1)
#   BENCH_SKIP_TAR=1      Skip tar extraction test
#   BENCH_SKIP_NPM=1      Skip npm install test
#   NODE_TAR_URL=...      Override node tarball URL
set -euo pipefail

TARGET="${1:?Usage: fs-bench.sh /path/to/mount [--baseline]}"
BASELINE=false
[ "${2:-}" = "--baseline" ] && BASELINE=true

RUNS="${BENCH_RUNS:-1}"
NODE_TAR="${NODE_TAR_URL:-https://nodejs.org/dist/v22.12.0/node-v22.12.0-linux-x64.tar.xz}"
NODE_TAR_CACHE="/tmp/fs-bench-node.tar.xz"

# --- Helpers ---
now_ms() { date +%s%3N; }

ms_since() {
    local t1
    t1=$(now_ms)
    echo $((t1 - $1))
}

header() {
    echo ""
    echo "# $1"
    echo "# Host: $(hostname) $(uname -r)"
    echo "# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Node: $(node --version 2>/dev/null || echo N/A)"
    echo "# npm: $(npm --version 2>/dev/null || echo N/A)"
    echo "# Target: $2"
    echo "#"
}

# --- Microbenchmarks ---
run_micro() {
    local dir="$1"
    local prefix="$2"
    local work="$dir/.bench-micro-$$"
    mkdir -p "$work"

    # 1000 creates
    local t0
    t0=$(now_ms)
    for i in $(seq 1 1000); do echo "x" > "$work/f$i"; done
    local creates_ms
    creates_ms=$(ms_since "$t0")

    # 1000 stats (warm)
    t0=$(now_ms)
    for i in $(seq 1 1000); do stat "$work/f$i" >/dev/null; done
    local stats_ms
    stats_ms=$(ms_since "$t0")

    # 1000 reads (warm)
    t0=$(now_ms)
    for i in $(seq 1 1000); do cat "$work/f$i" >/dev/null; done
    local reads_ms
    reads_ms=$(ms_since "$t0")

    # 100 mkdirs
    t0=$(now_ms)
    for i in $(seq 1 100); do mkdir "$work/d$i"; done
    local mkdirs_ms
    mkdirs_ms=$(ms_since "$t0")

    printf "%-20s %-14s %-14s %-14s %-14s\n" \
        "$prefix" "${creates_ms}ms" "${stats_ms}ms" "${reads_ms}ms" "${mkdirs_ms}ms"

    rm -rf "$work"
}

# --- npm install ---
run_npm() {
    local dir="$1"
    local prefix="$2"
    local work="$dir/.bench-npm-$$"
    mkdir -p "$work"
    cd "$work"
    npm init -y >/dev/null 2>&1

    # Cold run
    local t0
    t0=$(now_ms)
    npm install typescript eslint prettier >/dev/null 2>&1
    local cold_ms
    cold_ms=$(ms_since "$t0")
    local files
    files=$(find node_modules -type f 2>/dev/null | wc -l)

    # Warm run
    rm -rf node_modules package-lock.json
    npm init -y >/dev/null 2>&1
    t0=$(now_ms)
    npm install typescript eslint prettier >/dev/null 2>&1
    local warm_ms
    warm_ms=$(ms_since "$t0")

    printf "%-20s %-14s %-14s %-14s\n" \
        "$prefix" "${cold_ms}ms" "${warm_ms}ms" "$files files"

    cd /tmp
    rm -rf "$work"
}

# --- tar extraction ---
run_tar() {
    local dir="$1"
    local prefix="$2"
    local work="$dir/.bench-tar-$$"
    mkdir -p "$work"

    # Download tarball if needed
    if [ ! -f "$NODE_TAR_CACHE" ]; then
        echo "# Downloading node tarball..." >&2
        curl -sLo "$NODE_TAR_CACHE" "$NODE_TAR"
    fi

    local t0
    t0=$(now_ms)
    tar -xJf "$NODE_TAR_CACHE" -C "$work"
    local tar_ms
    tar_ms=$(ms_since "$t0")
    local files
    files=$(find "$work" -type f | wc -l)

    printf "%-20s %-14s %-14s\n" \
        "$prefix" "${tar_ms}ms" "$files files"

    rm -rf "$work"
}

# --- Main ---
echo "# Filesystem Benchmark"
echo "# Host: $(hostname) $(uname -r)"
echo "# Instance: $(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo unknown)"
echo "# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# Node: $(node --version 2>/dev/null || echo N/A)"
echo "# npm: $(npm --version 2>/dev/null || echo N/A)"
echo "# Target: $TARGET"
if [ "$BASELINE" = true ]; then
    echo "# Baseline: /tmp (local ext4)"
fi
echo "#"
echo ""

# Microbenchmarks
printf "%-20s %-14s %-14s %-14s %-14s\n" \
    "BACKEND" "1K_CREATES" "1K_STATS" "1K_READS" "100_MKDIRS"
echo "---"

run_micro "$TARGET" "target"
if [ "$BASELINE" = true ]; then
    run_micro "/tmp" "ext4-baseline"
fi
echo ""

# npm install
if [ "${BENCH_SKIP_NPM:-}" != "1" ]; then
    printf "%-20s %-14s %-14s %-14s\n" \
        "BACKEND" "NPM_COLD" "NPM_WARM" "FILES"
    echo "---"

    run_npm "$TARGET" "target"
    if [ "$BASELINE" = true ]; then
        run_npm "/tmp" "ext4-baseline"
    fi
    echo ""
fi

# tar extraction
if [ "${BENCH_SKIP_TAR:-}" != "1" ]; then
    printf "%-20s %-14s %-14s\n" \
        "BACKEND" "TAR_EXTRACT" "FILES"
    echo "---"

    run_tar "$TARGET" "target"
    if [ "$BASELINE" = true ]; then
        run_tar "/tmp" "ext4-baseline"
    fi
    echo ""
fi

echo "# Done."
