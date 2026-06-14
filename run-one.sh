#!/usr/bin/env bash
# run-one.sh: Single-provider flow — create → exec → collect → destroy.
# Teardown is trap-based so the VM dies on any exit path (success, error, Ctrl-C).
# Usage: bash run-one.sh <provider>
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="${1:?Usage: run-one.sh <provider>}"

source "$REPO_ROOT/providers/common.sh"
source "$REPO_ROOT/providers/$P.sh"
verify_contract "$P"

VM_ID=""
cleanup() {
    [ -n "$VM_ID" ] && vm_destroy "$VM_ID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$REPO_ROOT/results"
OUT="$REPO_ROOT/results/$(date -u +%F)-$P.txt"
OUT_CORRECTNESS="$REPO_ROOT/results/$(date -u +%F)-$P-correctness.txt"

echo "[$P] creating sandbox..."
t_create=$(date +%s%3N)
VM_ID="$(vm_create)"
wake_ms=$(( $(date +%s%3N) - t_create ))
echo "[$P] sandbox $VM_ID ready in ${wake_ms}ms"

# Write wake time as the first line so it survives alongside bench output.
{
    echo "  wake_time  ${wake_ms}ms  # host-measured: vm_create → ready"
    echo ""
} > "$OUT"

BENCH_REPO="${BENCH_REPO:-https://github.com/dedaluslabs/fs-bench}"
WORKSPACE="${BENCH_WORKSPACE:-/home/user}"
BENCH_N="${BENCH_N:-10}"

echo "[$P] installing prerequisites..."
vm_exec "$VM_ID" "
    set -e
    command -v git    || (apt-get update -qq && apt-get install -y git curl)    || true
    command -v node   || (apt-get install -y nodejs npm)                         || true
    command -v python3 || (apt-get install -y python3)                           || true
" >> "$OUT" 2>&1 || true

echo "[$P] cloning benchmark repo..."
vm_exec "$VM_ID" "
    set -e
    [ -d /tmp/fs-bench ] && rm -rf /tmp/fs-bench
    git clone --depth=1 $BENCH_REPO /tmp/fs-bench
" >> "$OUT" 2>&1

echo "[$P] running perf suite..."
vm_exec "$VM_ID" "
    set -e
    cd /tmp/fs-bench
    BENCH_N=$BENCH_N bash bench/fs-bench.sh $WORKSPACE
" >> "$OUT" 2>&1

echo "[$P] running correctness suite..."
vm_exec "$VM_ID" "
    set -e
    cd /tmp/fs-bench
    BENCH_N=1 bash bench/correctness/runner.sh $WORKSPACE
" >> "$OUT_CORRECTNESS" 2>&1 || true

echo "[$P] done → $OUT"
