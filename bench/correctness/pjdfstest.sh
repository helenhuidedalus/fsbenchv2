#!/usr/bin/env bash
# correctness/pjdfstest.sh: Build pjdfstest from vendor/ and run prove -r against TARGET.
# Requires: autoconf, automake, libtool, perl (prove), root recommended for full coverage.
# Outputs a single summary row: pjdfstest | passed | skipped | failed | notes
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
source "$BENCH_DIR/lib.sh"

TARGET="${1:?target required}"
VENDOR="$REPO_ROOT/vendor/pjdfstest"
BUILD="$VENDOR"

_skip() { row "pjdfstest" "-" "-" "-" "$1"; }

# Vendor source must be present (git submodule init).
if [ ! -f "$VENDOR/configure.ac" ]; then
    _skip "vendor/pjdfstest not initialised (git submodule update --init)"
    exit 0
fi

# Build once if binary is absent or stale.
if [ ! -x "$BUILD/pjdfstest" ]; then
    if ! command -v autoreconf &>/dev/null; then
        _skip "autoreconf not found (apt install autoconf automake libtool)"
        exit 0
    fi
    echo "  Building pjdfstest..." >&2
    (cd "$VENDOR" && autoreconf -ifs >/dev/null 2>&1 && ./configure >/dev/null 2>&1 && make -j"$(nproc 2>/dev/null || echo 2)" >/dev/null 2>&1) || {
        _skip "build failed — see vendor/pjdfstest for details"
        exit 0
    }
fi

if ! command -v prove &>/dev/null; then
    _skip "prove not found (apt install perl)"
    exit 0
fi

# pjdfstest needs TMPDIR pointing at the target filesystem.
PROVE_OUT=$(TMPDIR="$TARGET" prove -r "$VENDOR/tests" 2>&1 || true)

passed=$(echo "$PROVE_OUT" | grep -oP '\d+(?= ok)'      | paste -sd+ | bc 2>/dev/null || echo 0)
skipped=$(echo "$PROVE_OUT" | grep -oP '\d+(?= skipped)' | paste -sd+ | bc 2>/dev/null || echo 0)
failed=$(echo "$PROVE_OUT"  | grep -oP '\d+(?= failed)'  | paste -sd+ | bc 2>/dev/null || echo 0)

notes=""
have_root || notes="(no root — some tests skipped)"
[ "$failed" -gt 0 ] && notes="FAILURES — check results file"

row "pjdfstest" "$passed" "$skipped" "$failed" "$notes"
