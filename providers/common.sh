#!/usr/bin/env bash
# providers/common.sh — Four-function provider contract.
#
# Every providers/<name>.sh must implement these four functions.
# Source this file to document and verify the contract at runtime.
#
# ┌──────────────────────────────────────────────────────────────┐
# │  vm_create                  → echoes sandbox id on stdout    │
# │  vm_exec   <id> <cmd>       → runs cmd in guest, streams out │
# │  vm_copy_out <id> <src> <dst> → copies guest path to local   │
# │  vm_destroy <id>            → destroys sandbox (idempotent)  │
# └──────────────────────────────────────────────────────────────┘
#
# Rules:
#   - vm_create must tag the sandbox with label "fs-bench" so that
#     `run.sh --cleanup` can find orphans by tag.
#   - vm_destroy must never error even if the sandbox is already gone.
#   - vm_exec should stream stdout/stderr so progress is visible.
#   - vm_copy_out is optional; prefer capturing vm_exec stdout directly.

# verify_contract: call after sourcing a provider file to ensure all
# four functions are defined.  Exits 1 with a clear message if any is missing.
verify_contract() {
    local p="${1:-unknown}" ok=0
    for fn in vm_create vm_exec vm_copy_out vm_destroy; do
        declare -f "$fn" >/dev/null 2>&1 || { echo "✗ $p: $fn not defined"; ok=1; }
    done
    return $ok
}
