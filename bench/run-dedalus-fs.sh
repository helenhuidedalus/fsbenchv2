#!/usr/bin/env bash
# Mount dedalus-fs locally and run fs-bench against it.
#
# dedalus-fs is a FUSE (Filesystem in Userspace) daemon. It stores file
# data as content-addressed chunks in S3 and file metadata (names,
# permissions, sizes, timestamps) in a local SQLite database. The
# storage daemon ships a `mount-helper` binary that exposes this
# filesystem at a local mountpoint via /dev/fuse.
#
# No VM, no snapshot bake, no guest-agent. The bench measures only
# filesystem cost, not virtio-fs or VM overhead.
#
# Prereqs:
#   - dm-workspace clone at $WS (default: ~/dm-workspace)
#   - Rust toolchain (cargo) available to the invoking user
#   - AWS credentials on the SDK default provider chain (instance role,
#     environment variables, or ~/.aws/credentials)
#   - S3 bucket with Put/Get/DeleteObject permissions
#   - Linux with /dev/fuse and fusermount (Ubuntu: apt install fuse3)
#
# Usage:
#   sudo bash run-dedalus-fs.sh                   # build + mount + bench
#   sudo bash run-dedalus-fs.sh --skip-build      # reuse existing binary
#   sudo bash run-dedalus-fs.sh --bucket my-bench # override S3 bucket
#   sudo bash run-dedalus-fs.sh --unmount         # tear down
set -euo pipefail

# Under sudo, $HOME is /root. Resolve the invoking user's home instead.
USER_HOME=$(eval echo ~"${SUDO_USER:-$USER}")
WS=${WS:-$USER_HOME/dm-workspace}
BUCKET=${BUCKET:-dcs-s3files-bench}
FS_ID=${FS_ID:-bench-fs}
MOUNTPOINT=/mnt/dedalus-fs
DATA_DIR=/tmp/sd-fuse-data
CACHE_DIR=/tmp/sd-fuse-cache
CONFIG=/tmp/sd-fuse-mount.toml
MOUNT_HELPER="$WS/target/release/mount-helper"

SKIP_BUILD=false
UNMOUNT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=true; shift ;;
    --bucket)     BUCKET="$2"; shift 2 ;;
    --unmount)    UNMOUNT=true; shift ;;
    *)            echo "unknown: $1"; exit 1 ;;
  esac
done

if $UNMOUNT; then
  echo "==> unmount"
  fusermount -u -z "$MOUNTPOINT" 2>/dev/null || true
  pkill -9 -f mount-helper 2>/dev/null || true
  echo "    done"
  exit 0
fi

if ! $SKIP_BUILD; then
  echo "==> build mount-helper"
  sudo -u "${SUDO_USER:-$USER}" bash -lc \
    "cd $WS && cargo build --release -p dm-storage-daemon --features fusedev --bin mount-helper 2>&1 | tail -3"
  echo "    done"
fi

echo "==> preflight"
[ -x "$MOUNT_HELPER" ]          || { echo "FATAL: $MOUNT_HELPER missing"; exit 1; }
[ -c /dev/fuse ]                || { echo "FATAL: /dev/fuse missing (apt install fuse3)"; exit 1; }
command -v fusermount >/dev/null || { echo "FATAL: fusermount missing"; exit 1; }
echo "    ok"

echo "==> cleaning stale mount/state"
fusermount -u -z "$MOUNTPOINT" 2>/dev/null || true
pkill -9 -f mount-helper 2>/dev/null || true
rm -rf "$DATA_DIR" "$CACHE_DIR"
mkdir -p "$MOUNTPOINT" "$DATA_DIR" "$CACHE_DIR"

cat > "$CONFIG" <<EOF
[data]
dir = "$DATA_DIR"

[storage]
mode = "s3"
fs-id = "$FS_ID"
bucket = "$BUCKET"
region = "us-west-2"
endpoint-url = ""

[cache]
ram-mib = 1024
disk-dir = "$CACHE_DIR"
disk-gib = 10
EOF

echo "==> mount dedalus-fs at $MOUNTPOINT (S3: $BUCKET)"
nohup "$MOUNT_HELPER" --config "$CONFIG" "$MOUNTPOINT" > /tmp/mount-helper.log 2>&1 &
for _ in $(seq 1 20); do
  mount | grep -q "$MOUNTPOINT" && break
  sleep 0.5
done
if ! mount | grep -q "$MOUNTPOINT"; then
  echo "FATAL: mount did not appear"
  tail -20 /tmp/mount-helper.log
  exit 1
fi
echo "    mounted"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
echo "==> fs-bench $MOUNTPOINT"
bash "$SCRIPT_DIR/fs-bench.sh" "$MOUNTPOINT"

echo ""
echo "==> done. to unmount: sudo bash $(basename "$0") --unmount"
echo "    mount log: /tmp/mount-helper.log"
