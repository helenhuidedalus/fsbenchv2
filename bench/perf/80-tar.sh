#!/usr/bin/env bash
# 80-tar.sh: Tar extraction — Node v22 tarball (~4800 files, ~90 MiB).
# Downloads once to /tmp cache; re-extracts N times to target.
# Contract: run_test <target_dir> <label> <N>
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

NODE_TAR="${NODE_TAR_URL:-https://nodejs.org/dist/v22.12.0/node-v22.12.0-linux-x64.tar.xz}"
NODE_TAR_CACHE="/tmp/fs-bench-node.tar.xz"

run_test() {
    local target="$1" label="${2:-tar}" N="${3:-10}"

    if [ "${BENCH_SKIP_TAR:-}" = "1" ]; then
        hdr "TAR EXTRACTION  (skipped)"
        return
    fi

    hdr "TAR EXTRACTION  (node v22, ~4800 files, ~90 MiB, N=$N)"
    printf "  %-22s%-16s%-16s%-16s%-16s\n" \
        "" "time p50" "time p99" "files" ""
    sep

    if [ ! -f "$NODE_TAR_CACHE" ]; then
        echo "  Downloading $(basename "$NODE_TAR") ..."
        curl -sLo "$NODE_TAR_CACHE" "$NODE_TAR" || {
            row "$label" "N/A (download failed)" "" ""
            return
        }
    fi

    local samples=()
    local files=0

    for iter in $(seq 1 "$N"); do
        local w="$target/.bench-tar-$$-$iter"
        mkdir -p "$w"

        local t; t=$(now_ms)
        tar -xJf "$NODE_TAR_CACHE" -C "$w"
        samples+=("$(ms_since "$t")")

        [ "$iter" -eq "$N" ] && files=$(find "$w" -type f | wc -l | tr -d ' ')

        rm -rf "$w"
    done

    read -r p50 p99 <<< "$(printf '%s\n' "${samples[@]}" | summarize)"
    row "$label" "${p50}ms" "${p99}ms" "$files" ""
}

run_test "$@"
