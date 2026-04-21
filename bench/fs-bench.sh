#!/usr/bin/env bash
# fs-bench: filesystem benchmark for cloud dev environment workloads.
#
# Measures npm install, git ops, metadata throughput, rename, hardlink,
# fsync, concurrent I/O, fio, and tar extraction. Output is columnar
# and machine-parseable.
#
# Prerequisites: node/npm, git, fio (optional), curl
# Usage:
#   bash fs-bench.sh /path/to/mount              # one target
#   bash fs-bench.sh /path/to/mount --baseline    # also ext4 on /tmp
#
# Environment:
#   BENCH_SKIP_NPM=1     skip npm tests
#   BENCH_SKIP_TAR=1     skip tar extraction
#   BENCH_SKIP_GIT=1     skip git tests
#   BENCH_SKIP_FIO=1     skip fio tests
#   BENCH_CONCURRENCY=4  parallel create workers (default 4)
set -euo pipefail

TARGET="${1:?Usage: fs-bench.sh /path/to/mount [--baseline]}"
BASELINE=false
[ "${2:-}" = "--baseline" ] && BASELINE=true
CONC="${BENCH_CONCURRENCY:-4}"

NODE_TAR="${NODE_TAR_URL:-https://nodejs.org/dist/v22.12.0/node-v22.12.0-linux-x64.tar.xz}"
NODE_TAR_CACHE="/tmp/fs-bench-node.tar.xz"

# ── Helpers ──────────────────────────────────────────────────────────
now_ms() { date +%s%3N; }
ms_since() { echo $(( $(now_ms) - $1 )); }

COL="%-22s"
sep() { printf '%0.s─' {1..78}; echo; }

hdr() {
    echo ""
    echo "  $1"
    sep
}

row() {
    # row label val1 [val2 ...]
    local label="$1"; shift
    printf "  $COL" "$label"
    for v in "$@"; do printf "%-16s" "$v"; done
    echo ""
}

# ── System info ──────────────────────────────────────────────────────
echo ""
echo "  FS-BENCH"
sep
row "Host"      "$(hostname)"
row "Kernel"    "$(uname -r)"
row "Instance"  "$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo unknown)"
row "Date"      "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
row "Node"      "$(node --version 2>/dev/null || echo N/A)"
row "npm"       "$(npm --version 2>/dev/null || echo N/A)"
row "fio"       "$(fio --version 2>/dev/null || echo N/A)"
row "git"       "$(git --version 2>/dev/null | awk '{print $3}' || echo N/A)"
row "Target"    "$TARGET"
[ "$BASELINE" = true ] && row "Baseline" "/tmp (local)"
sep

TARGETS=("$TARGET")
LABELS=("target")
if [ "$BASELINE" = true ]; then
    TARGETS+=("/tmp")
    LABELS+=("ext4")
fi

# ── 1. Metadata microbenchmarks ──────────────────────────────────────
hdr "METADATA OPS"
printf "  $COL%-16s%-16s%-16s%-16s\n" "" "1K creates" "1K stats" "1K reads" "100 mkdirs"
sep

for idx in "${!TARGETS[@]}"; do
    dir="${TARGETS[$idx]}"
    lbl="${LABELS[$idx]}"
    w="$dir/.bench-micro-$$"
    mkdir -p "$w"

    t=$(now_ms); for i in $(seq 1 1000); do echo x > "$w/f$i"; done
    c_ms=$(ms_since "$t")

    t=$(now_ms); for i in $(seq 1 1000); do stat "$w/f$i" >/dev/null; done
    s_ms=$(ms_since "$t")

    t=$(now_ms); for i in $(seq 1 1000); do cat "$w/f$i" >/dev/null; done
    r_ms=$(ms_since "$t")

    t=$(now_ms); for i in $(seq 1 100); do mkdir "$w/d$i"; done
    m_ms=$(ms_since "$t")

    row "$lbl" "${c_ms}ms" "${s_ms}ms" "${r_ms}ms" "${m_ms}ms"
    rm -rf "$w"
done

# ── 2. Rename + hardlink + symlink ───────────────────────────────────
hdr "RENAME / LINK / SYMLINK"
printf "  $COL%-16s%-16s%-16s%-16s\n" "" "1K renames" "1K xdir-ren" "1K hardlinks" "1K symlinks"
sep

for idx in "${!TARGETS[@]}"; do
    dir="${TARGETS[$idx]}"
    lbl="${LABELS[$idx]}"
    w="$dir/.bench-link-$$"
    mkdir -p "$w/a" "$w/b"
    for i in $(seq 1 1000); do echo x > "$w/a/f$i"; done

    # same-dir rename
    t=$(now_ms); for i in $(seq 1 1000); do mv "$w/a/f$i" "$w/a/r$i"; done
    ren_ms=$(ms_since "$t")

    # cross-dir rename
    t=$(now_ms); for i in $(seq 1 1000); do mv "$w/a/r$i" "$w/b/f$i"; done
    xren_ms=$(ms_since "$t")

    # hardlinks
    t=$(now_ms)
    hl_ms="N/A"
    if ln "$w/b/f1" "$w/b/hl1" 2>/dev/null; then
        rm "$w/b/hl1"
        for i in $(seq 1 1000); do ln "$w/b/f$i" "$w/b/hl$i"; done
        hl_ms="$(ms_since "$t")ms"
    fi

    # symlinks
    t=$(now_ms); for i in $(seq 1 1000); do ln -s "$w/b/f$i" "$w/b/sl$i"; done
    sl_ms=$(ms_since "$t")

    row "$lbl" "${ren_ms}ms" "${xren_ms}ms" "$hl_ms" "${sl_ms}ms"
    rm -rf "$w"
done

# ── 3. fsync latency ─────────────────────────────────────────────────
hdr "FSYNC LATENCY"
printf "  $COL%-16s%-16s%-16s\n" "" "1K creat+fsync" "p50 (us)" "p99 (us)"
sep

for idx in "${!TARGETS[@]}"; do
    dir="${TARGETS[$idx]}"
    lbl="${LABELS[$idx]}"

    result=$(python3 -c "
import os, time
path = '$dir/.bench-fsync-$$'
samples = []
for i in range(1000):
    fd = os.open(f'{path}-{i}', os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
    os.write(fd, b'x' * 128)
    t0 = time.monotonic_ns()
    os.fdatasync(fd)
    t1 = time.monotonic_ns()
    os.close(fd)
    samples.append(t1 - t0)
    os.unlink(f'{path}-{i}')
samples.sort()
total_ms = sum(samples) / 1e6
p50 = samples[499] / 1000
p99 = samples[989] / 1000
print(f'{total_ms:.0f}ms {p50:.0f}us {p99:.0f}us')
" 2>/dev/null || echo "N/A N/A N/A")

    row "$lbl" $result
done

# ── 4. Concurrent creates ────────────────────────────────────────────
hdr "CONCURRENT ${CONC}-WAY CREATE (1000 files total)"
printf "  $COL%-16s\n" "" "wall time"
sep

for idx in "${!TARGETS[@]}"; do
    dir="${TARGETS[$idx]}"
    lbl="${LABELS[$idx]}"
    w="$dir/.bench-conc-$$"
    mkdir -p "$w"

    per=$((1000 / CONC))
    t=$(now_ms)
    for j in $(seq 1 "$CONC"); do
        ( start=$(( (j-1) * per + 1 )); end=$((j * per))
          for i in $(seq "$start" "$end"); do echo x > "$w/f$i"; done
        ) &
    done
    wait
    conc_ms=$(ms_since "$t")

    row "$lbl" "${conc_ms}ms"
    rm -rf "$w"
done

# ── 5. Directory listing ─────────────────────────────────────────────
hdr "DIRECTORY LISTING"
printf "  $COL%-16s%-16s\n" "" "ls -la (1000)" "find -type f"
sep

for idx in "${!TARGETS[@]}"; do
    dir="${TARGETS[$idx]}"
    lbl="${LABELS[$idx]}"
    w="$dir/.bench-ls-$$"
    mkdir -p "$w"
    for i in $(seq 1 1000); do echo x > "$w/f$i"; done

    t=$(now_ms); ls -la "$w" >/dev/null; ls_ms=$(ms_since "$t")
    t=$(now_ms); find "$w" -type f | wc -l >/dev/null; find_ms=$(ms_since "$t")

    row "$lbl" "${ls_ms}ms" "${find_ms}ms"
    rm -rf "$w"
done

# ── 6. npm install ───────────────────────────────────────────────────
if [ "${BENCH_SKIP_NPM:-}" != "1" ] && command -v npm &>/dev/null; then
    hdr "NPM INSTALL (typescript eslint prettier)"
    printf "  $COL%-16s%-16s%-16s\n" "" "cold" "warm" "files"
    sep

    for idx in "${!TARGETS[@]}"; do
        dir="${TARGETS[$idx]}"
        lbl="${LABELS[$idx]}"
        w="$dir/.bench-npm-$$"
        mkdir -p "$w" && cd "$w"
        npm init -y >/dev/null 2>&1

        t=$(now_ms); npm install typescript eslint prettier >/dev/null 2>&1
        cold_ms=$(ms_since "$t")
        files=$(find node_modules -type f 2>/dev/null | wc -l)

        rm -rf node_modules package-lock.json
        npm init -y >/dev/null 2>&1
        t=$(now_ms); npm install typescript eslint prettier >/dev/null 2>&1
        warm_ms=$(ms_since "$t")

        row "$lbl" "${cold_ms}ms" "${warm_ms}ms" "$files"
        cd /tmp && rm -rf "$w"
    done
fi

# ── 7. git operations ────────────────────────────────────────────────
if [ "${BENCH_SKIP_GIT:-}" != "1" ] && command -v git &>/dev/null; then
    hdr "GIT OPERATIONS"
    printf "  $COL%-16s%-16s\n" "" "clone (local)" "status"
    sep

    for idx in "${!TARGETS[@]}"; do
        dir="${TARGETS[$idx]}"
        lbl="${LABELS[$idx]}"
        w="$dir/.bench-git-$$"

        # Create a source repo with ~2000 files
        src="$dir/.bench-git-src-$$"
        mkdir -p "$src" && cd "$src"
        git init -q
        mkdir -p src lib test
        for i in $(seq 1 500); do echo "// file $i" > "src/f$i.ts"; done
        for i in $(seq 1 500); do echo "// lib $i" > "lib/l$i.ts"; done
        for i in $(seq 1 500); do echo "// test $i" > "test/t$i.ts"; done
        for i in $(seq 1 500); do echo "data $i" > "d$i.txt"; done
        git add -A && git commit -q -m "init" 2>/dev/null

        # Clone
        t=$(now_ms); git clone -q "$src" "$w" 2>/dev/null; clone_ms=$(ms_since "$t")

        # Status
        cd "$w"
        t=$(now_ms); git status >/dev/null 2>&1; status_ms=$(ms_since "$t")

        row "$lbl" "${clone_ms}ms" "${status_ms}ms"
        cd /tmp && rm -rf "$w" "$src"
    done
fi

# ── 8. tar extraction ────────────────────────────────────────────────
if [ "${BENCH_SKIP_TAR:-}" != "1" ]; then
    hdr "TAR EXTRACTION (node v22, ~4800 files, 90 MiB)"
    printf "  $COL%-16s%-16s\n" "" "time" "files"
    sep

    [ ! -f "$NODE_TAR_CACHE" ] && curl -sLo "$NODE_TAR_CACHE" "$NODE_TAR"

    for idx in "${!TARGETS[@]}"; do
        dir="${TARGETS[$idx]}"
        lbl="${LABELS[$idx]}"
        w="$dir/.bench-tar-$$"
        mkdir -p "$w"

        t=$(now_ms); tar -xJf "$NODE_TAR_CACHE" -C "$w"; tar_ms=$(ms_since "$t")
        files=$(find "$w" -type f | wc -l)

        row "$lbl" "${tar_ms}ms" "$files"
        rm -rf "$w"
    done
fi

# ── 9. fio (optional) ────────────────────────────────────────────────
if [ "${BENCH_SKIP_FIO:-}" != "1" ] && command -v fio &>/dev/null; then
    hdr "FIO (30s each)"
    printf "  $COL%-16s%-16s%-16s\n" "" "4K randread" "4K rw+fsync" "1M seqwrite"
    sep

    for idx in "${!TARGETS[@]}"; do
        dir="${TARGETS[$idx]}"
        lbl="${LABELS[$idx]}"
        w="$dir/.bench-fio-$$"
        mkdir -p "$w"

        rr=$(fio --name=rr --directory="$w" --rw=randread --bs=4k \
            --numjobs=4 --size=256M --runtime=10 --time_based \
            --group_reporting --output-format=json 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d['jobs'][0]['read']['iops']:.0f} IOPS\")" 2>/dev/null || echo "N/A")

        rw=$(fio --name=rw --directory="$w" --rw=randwrite --bs=4k \
            --numjobs=4 --size=256M --runtime=10 --time_based \
            --fsync=1 --group_reporting --output-format=json 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d['jobs'][0]['write']['iops']:.0f} IOPS\")" 2>/dev/null || echo "N/A")

        sw=$(fio --name=sw --directory="$w" --rw=write --bs=1M \
            --numjobs=1 --size=1G --runtime=10 --time_based \
            --group_reporting --output-format=json 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d['jobs'][0]['write']['bw']/1024:.0f} MiB/s\")" 2>/dev/null || echo "N/A")

        row "$lbl" "$rr" "$rw" "$sw"
        rm -rf "$w"
    done
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
sep
echo "  Done."
echo ""
