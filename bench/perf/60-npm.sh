#!/usr/bin/env bash
# 60-npm.sh: npm install timing — base packages + agent packages as separate metrics.
# Package list read from docs/packages.md (single source of truth).
# Cold = npm cache cleared; warm = npm cache intact, fresh node_modules.
# Contract: run_test <target_dir> <label> <N>
set -euo pipefail
BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
source "$BENCH_DIR/lib.sh"

PACKAGES_MD="$REPO_ROOT/docs/packages.md"

_parse_pkgs() {
    local section="$1"  # "Base" or "Agent"
    awk "/^## ${section} Packages/{found=1; next} /^##/{found=0} found && /^- /{print substr(\$0,3)}" \
        "$PACKAGES_MD" 2>/dev/null | tr '\n' ' '
}

run_test() {
    local target="$1" label="${2:-npm}" N="${3:-10}"

    if ! command -v npm &>/dev/null || [ "${BENCH_SKIP_NPM:-}" = "1" ]; then
        hdr "NPM INSTALL  (skipped)"
        return
    fi

    local base_pkgs agent_pkgs
    base_pkgs=$(_parse_pkgs "Base")
    agent_pkgs=$(_parse_pkgs "Agent")

    # Fallback if packages.md is absent.
    [ -z "${base_pkgs// /}" ]  && base_pkgs="typescript eslint prettier"

    hdr "NPM INSTALL  (N=$N)"
    printf "  %-22s%-16s%-16s%-16s%-16s%-16s\n" \
        "" "cold p50" "cold p99" "warm p50" "agent p50" "files"
    sep

    local cold_samples=() warm_samples=() agent_samples=()
    local files=0

    for iter in $(seq 1 "$N"); do
        local w="$target/.bench-npm-$$-$iter"
        mkdir -p "$w"
        cd "$w"
        npm init -y >/dev/null 2>&1

        # Cold: clear npm cache to measure full download+write path.
        npm cache clean --force >/dev/null 2>&1 || true
        local t; t=$(now_ms)
        npm install $base_pkgs >/dev/null 2>&1
        cold_samples+=("$(ms_since "$t")")

        [ "$iter" -eq "$N" ] && files=$(find node_modules -type f 2>/dev/null | wc -l | tr -d ' ')

        rm -rf node_modules package-lock.json
        npm init -y >/dev/null 2>&1

        # Warm: npm cache populated, only FS writes.
        t=$(now_ms)
        npm install $base_pkgs >/dev/null 2>&1
        warm_samples+=("$(ms_since "$t")")

        # Agent install: timed as a separate step.
        if [ -n "${agent_pkgs// /}" ]; then
            t=$(now_ms)
            npm install $agent_pkgs >/dev/null 2>&1
            agent_samples+=("$(ms_since "$t")")
        fi

        cd /tmp && rm -rf "$w"
    done

    read -r cold_p50 cold_p99 <<< "$(printf '%s\n' "${cold_samples[@]}" | summarize)"
    read -r warm_p50 _        <<< "$(printf '%s\n' "${warm_samples[@]}" | summarize)"

    local agent_p50="N/A"
    [ ${#agent_samples[@]} -gt 0 ] && {
        read -r agent_p50 _ <<< "$(printf '%s\n' "${agent_samples[@]}" | summarize)"
        agent_p50="${agent_p50}ms"
    }

    row "$label" "${cold_p50}ms" "${cold_p99}ms" "${warm_p50}ms" "$agent_p50" "$files"
}

run_test "$@"
