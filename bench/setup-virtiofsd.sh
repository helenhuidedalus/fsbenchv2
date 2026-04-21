#!/usr/bin/env bash
# Launch stock virtiofsd + DHV guest with passthrough mount.
# Injects networking + benchmark into rootfs via rc.local.
# Results appear at $SHARE/results.txt on the host.
#
# Usage: sudo bash setup-virtiofsd.sh
set -euo pipefail

DHV="${DHV:-/home/ubuntu/dhv/target/release/dedalus-hypervisor}"
KERNEL="${KERNEL:-/home/ubuntu/dedalus-kernel/vmlinux-6.16.9}"
ROOTFS="${ROOTFS:-/home/ubuntu/guest/rootfs.raw}"
SHARE="/tmp/virtiofs-bench-share"
SOCK="/tmp/virtiofs-bench.sock"
API_SOCK="/tmp/virtiofs-bench-api.sock"
ROOTFS_COPY="/tmp/bench-rootfs-v2.raw"
SERIAL_LOG="/tmp/bench-serial-v2.log"
TAP="tap-bench"
HOST_IFACE="ens5"

pkill -9 -f "dedalus-hypervisor.*bench" 2>/dev/null || true
pkill -9 -f "virtiofsd.*bench" 2>/dev/null || true
sleep 1
rm -rf "$SHARE" "$SOCK" "$API_SOCK" "$SERIAL_LOG" "$ROOTFS_COPY"
mkdir -p "$SHARE"

echo "Copying rootfs..."
cp "$ROOTFS" "$ROOTFS_COPY"

echo "Injecting rc.local..."
LOOP=$(losetup -fP --show "$ROOTFS_COPY")
mkdir -p /tmp/rootfs-edit && mount "${LOOP}p1" /tmp/rootfs-edit

# Copy bench script into shared dir
cp "$(dirname "$0")/fs-bench.sh" "$SHARE/fs-bench.sh"

cat > /tmp/rootfs-edit/etc/rc.local << 'EOF'
#!/bin/bash
for dev in enp0s3 eth0 ens3; do
    ip addr add 192.168.200.2/24 dev "$dev" 2>/dev/null && ip link set "$dev" up && break
done
ip route add default via 192.168.200.1 2>/dev/null
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
mkdir -p /mnt/bench
mount -t virtiofs benchfs /mnt/bench 2>/dev/null
if [ -x /mnt/bench/fs-bench.sh ]; then
    bash /mnt/bench/fs-bench.sh /mnt/bench --baseline > /mnt/bench/results.txt 2>&1
fi
EOF
chmod +x /tmp/rootfs-edit/etc/rc.local
sync && umount /tmp/rootfs-edit && losetup -d "$LOOP"

ip link del "$TAP" 2>/dev/null || true
ip tuntap add dev "$TAP" mode tap
ip addr add 192.168.200.1/24 dev "$TAP"
ip link set "$TAP" up
iptables -t nat -C POSTROUTING -s 192.168.200.0/24 -o "$HOST_IFACE" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s 192.168.200.0/24 -o "$HOST_IFACE" -j MASQUERADE
sysctl -q -w net.ipv4.ip_forward=1

virtiofsd --socket-path="$SOCK" --shared-dir="$SHARE" \
    --cache=always --thread-pool-size=4 --log-level=error &
sleep 1 && chmod 666 "$SOCK"

"$DHV" --api-socket "$API_SOCK" --kernel "$KERNEL" \
    --disk path="$ROOTFS_COPY" --cpus boot=4 \
    --memory size=4096M,shared=on \
    --net "tap=$TAP,mac=12:34:56:78:9a:bc" \
    --fs "tag=benchfs,socket=$SOCK,num_queues=1,queue_size=1024" \
    --cmdline "console=ttyS0 root=/dev/vda1 rw" \
    --serial file="$SERIAL_LOG" --console off &
DHV_PID=$!

echo "Waiting for results at $SHARE/results.txt ..."
for i in $(seq 1 360); do
    if grep -q "Done" "$SHARE/results.txt" 2>/dev/null; then
        cat "$SHARE/results.txt"; break
    fi
    [ $((i % 30)) -eq 0 ] && echo "  ...${i}s"
    sleep 1
done
grep -q "Done" "$SHARE/results.txt" 2>/dev/null || { echo "Timed out."; tail -20 "$SERIAL_LOG"; }
kill "$DHV_PID" 2>/dev/null || true
pkill -9 -f "virtiofsd.*bench" 2>/dev/null || true
