#!/usr/bin/env bash
# 20-rename-link.sh: Rename, cross-dir rename, hardlink, symlink — 1K each.
# Contract: run_test <target_dir> <label> <N>
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$BENCH_DIR/lib.sh"

run_test() {
    local target="$1" label="${2:-rename-link}" N="${3:-10}"

    hdr "RENAME / LINK / SYMLINK  (N=$N)"
    printf "  %-22s%-16s%-16s%-16s%-16s\n" \
        "" "1K-renames p50" "1K-xdir-ren p50" "1K-hardlinks p50" "1K-symlinks p50"
    sep

    local renames=() xrenames=() hardlinks=() symlinks=()

    for iter in $(seq 1 "$N"); do
        local w="$target/.bench-link-$$-$iter"
        mkdir -p "$w/a" "$w/b"
        for i in $(seq 1 1000); do printf x > "$w/a/f$i"; done

        local t
        # same-dir rename
        t=$(now_ms)
        for i in $(seq 1 1000); do mv "$w/a/f$i" "$w/a/r$i"; done
        renames+=("$(ms_since "$t")")

        # cross-dir rename
        t=$(now_ms)
        for i in $(seq 1 1000); do mv "$w/a/r$i" "$w/b/f$i"; done
        xrenames+=("$(ms_since "$t")")

        # hardlinks
        local hl_ms=0
        if ln "$w/b/f1" "$w/b/hl_probe" 2>/dev/null; then
            rm "$w/b/hl_probe"
            t=$(now_ms)
            for i in $(seq 1 1000); do ln "$w/b/f$i" "$w/b/hl$i"; done
            hl_ms=$(ms_since "$t")
        fi
        hardlinks+=("$hl_ms")

        # symlinks
        t=$(now_ms)
        for i in $(seq 1 1000); do ln -s "$w/b/f$i" "$w/b/sl$i"; done
        symlinks+=("$(ms_since "$t")")

        rm -rf "$w"
    done

    read -r ren_p50  _ <<< "$(printf '%s\n' "${renames[@]}"   | summarize)"
    read -r xren_p50 _ <<< "$(printf '%s\n' "${xrenames[@]}"  | summarize)"
    read -r hl_p50   _ <<< "$(printf '%s\n' "${hardlinks[@]}" | summarize)"
    read -r sl_p50   _ <<< "$(printf '%s\n' "${symlinks[@]}"  | summarize)"

    local hl_out="${hl_p50}ms"
    [ "$hl_p50" = "0" ] && hl_out="N/A"

    row "$label" "${ren_p50}ms" "${xren_p50}ms" "$hl_out" "${sl_p50}ms"
}

run_test "$@"
