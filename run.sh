#!/usr/bin/env bash
# run.sh: Preflight all providers then fan them out in parallel.
# Usage:
#   bash run.sh <provider>...          # run one or more providers
#   bash run.sh --cleanup              # destroy any orphaned fs-bench sandboxes
# Env:
#   BENCH_N=10      iterations per test (default 10)
#   BENCH_REPO=...  git URL of this repo (used inside guest)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load local keys if present; CI injects them as env vars instead.
[ -f "$REPO_ROOT/.env" ] && { set -a; source "$REPO_ROOT/.env"; set +a; }

# ── Cleanup mode ──────────────────────────────────────────────────────
if [ "${1:-}" = "--cleanup" ]; then
    echo "==> cleanup: destroying orphaned fs-bench sandboxes"
    for pfile in "$REPO_ROOT"/providers/[a-z]*.sh; do
        p="$(basename "$pfile" .sh)"
        [ "$p" = "common" ] && continue
        source "$REPO_ROOT/providers/common.sh"
        source "$pfile"
        if declare -f vm_cleanup_orphans &>/dev/null; then
            echo "  $p: running vm_cleanup_orphans"
            vm_cleanup_orphans || true
        else
            echo "  $p: no vm_cleanup_orphans defined (skipping)"
        fi
    done
    echo "==> done"
    exit 0
fi

PROVIDERS=("$@")
[ ${#PROVIDERS[@]} -eq 0 ] && { echo "usage: run.sh <provider>..."; exit 1; }

# ── Per-provider metadata (bash 3.2 compatible — no associative arrays) ──
provider_keyvar() {
    case "$1" in
        daytona)    echo DAYTONA_API_KEY ;;
        e2b)        echo E2B_API_KEY ;;
        modal)      echo MODAL_TOKEN_ID ;;
        tensorlake) echo TENSORLAKE_API_KEY ;;
        *)          echo "" ;;
    esac
}

provider_pymod() {
    case "$1" in
        daytona)    echo daytona ;;
        e2b)        echo e2b ;;
        modal)      echo modal ;;
        tensorlake) echo tensorlake ;;
        *)          echo "" ;;
    esac
}

preflight() {
    local p="$1" ok=0
    local keyvar pymod key
    keyvar="$(provider_keyvar "$p")"
    pymod="$(provider_pymod "$p")"

    [ -f "$REPO_ROOT/providers/$p.sh" ] \
        || { echo "  ✗ $p: providers/$p.sh missing"; ok=1; }
    [ -n "$keyvar" ] \
        || { echo "  ✗ $p: unknown provider (valid: daytona e2b modal tensorlake)"; return 1; }
    python3 -c "import $pymod" 2>/dev/null \
        || { echo "  ✗ $p: python module '$pymod' not installed  →  pip install $pymod"; ok=1; }
    key="${!keyvar:-}"
    [ -n "$key" ] \
        || { echo "  ✗ $p: \$$keyvar not set (add to .env or export it)"; ok=1; }
    return $ok
}

echo "==> preflight"
fail=0
for p in "${PROVIDERS[@]}"; do
    [ -n "$(provider_keyvar "$p")" ] \
        || { echo "  ✗ unknown provider: $p  (valid: daytona e2b modal tensorlake)"; fail=1; continue; }
    preflight "$p" && echo "  ✓ $p" || fail=1
done
[ "$fail" -ne 0 ] && { echo "preflight failed — fix the above and retry"; exit 1; }

# ── Fan out ───────────────────────────────────────────────────────────
echo "==> running ${#PROVIDERS[@]} provider(s) in parallel"
mkdir -p "$REPO_ROOT/results"
pids=()
for p in "${PROVIDERS[@]}"; do
    ( bash "$REPO_ROOT/run-one.sh" "$p" ) &
    pids+=($!)
done

rc=0
for pid in "${pids[@]}"; do wait "$pid" || rc=1; done

echo "==> done (exit $rc). results in results/"
exit $rc
