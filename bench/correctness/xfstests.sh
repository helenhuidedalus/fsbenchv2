#!/usr/bin/env bash
# correctness/xfstests.sh: Run xfstests -g quick (generic group only) against TARGET.
# Requires: root, xfsprogs, a scratch block device or second directory.
# Outputs a single summary row: xfstests | passed | skipped | failed | notes
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$BENCH_DIR/.." && pwd)"
source "$BENCH_DIR/lib.sh"

TARGET="${1:?target required}"
VENDOR="$REPO_ROOT/vendor/xfstests"

_skip() { row "xfstests" "-" "-" "-" "$1"; }

if [ ! -f "$VENDOR/check" ]; then
    _skip "vendor/xfstests not initialised (git submodule update --init)"
    exit 0
fi

if ! have_root; then
    _skip "root required for xfstests"
    exit 0
fi

# xfstests needs a scratch device/dir distinct from TEST_DIR.
SCRATCH_DIR="${XFSTESTS_SCRATCH_DIR:-}"
if [ -z "$SCRATCH_DIR" ]; then
    SCRATCH_DIR="$(dirname "$TARGET")/.xfstests-scratch-$$"
    mkdir -p "$SCRATCH_DIR"
    _cleanup_scratch=1
fi

# Build if not already built.
if [ ! -x "$VENDOR/check" ]; then
    echo "  Building xfstests..." >&2
    (cd "$VENDOR" && make -j"$(nproc 2>/dev/null || echo 2)" >/dev/null 2>&1) || {
        _skip "build failed — see vendor/xfstests for details"
        exit 0
    }
fi

XFSTESTS_OUT=$(cd "$VENDOR" && \
    TEST_DIR="$TARGET" \
    SCRATCH_MNT="$SCRATCH_DIR" \
    FSTYP="${XFSTESTS_FSTYP:-generic}" \
    ./check -g quick 2>&1 || true)

[ "${_cleanup_scratch:-}" = "1" ] && rm -rf "$SCRATCH_DIR"

passed=$(echo "$XFSTESTS_OUT"  | grep -c '^Passed' || echo 0)
skipped=$(echo "$XFSTESTS_OUT" | grep -c 'not run'  || echo 0)
failed=$(echo "$XFSTESTS_OUT"  | grep -c '^FAILED'  || echo 0)

notes=""
[ "$failed" -gt 0 ] && notes="FAILURES — check results file"

row "xfstests" "$passed" "$skipped" "$failed" "$notes"
