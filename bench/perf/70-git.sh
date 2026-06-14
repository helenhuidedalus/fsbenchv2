#!/usr/bin/env bash
# 70-git.sh: Git operations — local clone (~2000 files) and git status.
# Each iteration builds a fresh source repo so the clone is always cold FS writes.
# Contract: run_test <target_dir> <label> <N>
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

run_test() {
    local target="$1" label="${2:-git}" N="${3:-10}"

    if ! command -v git &>/dev/null || [ "${BENCH_SKIP_GIT:-}" = "1" ]; then
        hdr "GIT OPERATIONS  (skipped)"
        return
    fi

    hdr "GIT OPERATIONS  (N=$N, ~2000-file repo)"
    printf "  %-22s%-16s%-16s%-16s%-16s\n" \
        "" "clone p50" "clone p99" "status p50" "status p99"
    sep

    local clone_samples=() status_samples=()

    for iter in $(seq 1 "$N"); do
        local src="$target/.bench-git-src-$$-$iter"
        local dst="$target/.bench-git-dst-$$-$iter"

        mkdir -p "$src" && cd "$src"
        git init -q
        git config user.email "bench@fs-bench" && git config user.name "bench"
        mkdir -p src lib test
        for i in $(seq 1 500); do printf "// file %s\n" "$i" > "src/f$i.ts"; done
        for i in $(seq 1 500); do printf "// lib %s\n"  "$i" > "lib/l$i.ts"; done
        for i in $(seq 1 500); do printf "// test %s\n" "$i" > "test/t$i.ts"; done
        for i in $(seq 1 500); do printf "data %s\n"    "$i" > "d$i.txt"; done
        git add -A && git commit -q -m "init" 2>/dev/null

        local t
        t=$(now_ms); git clone -q "$src" "$dst" 2>/dev/null
        clone_samples+=("$(ms_since "$t")")

        cd "$dst"
        t=$(now_ms); git status >/dev/null 2>&1
        status_samples+=("$(ms_since "$t")")

        cd /tmp && rm -rf "$src" "$dst"
    done

    read -r cl_p50 cl_p99 <<< "$(printf '%s\n' "${clone_samples[@]}"  | summarize)"
    read -r st_p50 st_p99 <<< "$(printf '%s\n' "${status_samples[@]}" | summarize)"

    row "$label" "${cl_p50}ms" "${cl_p99}ms" "${st_p50}ms" "${st_p99}ms"
}

run_test "$@"
