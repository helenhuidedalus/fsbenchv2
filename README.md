# Filesystem Benchmark

Reproducible benchmarks measuring filesystem performance for cloud dev
environment workloads. Tests metadata ops, install workloads, and bulk
extraction across filesystem backends.

## Methodology

**npm install** is the primary workload. It exercises the exact
operation mix (create, write, rename, stat, readdir) that dominates
developer experience in cloud IDEs. Per-op microbenchmarks provide
diagnostic detail.

Each benchmark measures:

| Test | What it measures |
|---|---|
| **npm install** | End-to-end: npm resolver + registry fetch + filesystem writes. The user-visible number. |
| **1000 creates** | Raw metadata throughput: `open(O_CREAT) + write + close` per file. |
| **1000 stats** | Warm metadata read: `stat()` on recently created files. |
| **1000 reads** | Warm data read: `cat` on small files (inode lookup + page cache or backend fetch). |
| **100 mkdirs** | Directory creation throughput. |
| **tar extract** | Bulk write: ~4800 files, 90 MiB. Mixed file sizes. |
| **npm warm** | Second npm install after `rm -rf node_modules`. Tests cache / dedup behavior. |

### Test conditions

- **Workload**: `npm install typescript eslint prettier` (~1300 files)
- **Runs**: cold (first run) and warm (second run, same session)
- **Node**: v22+ (system or nvm)
- **No concurrent load**: single-tenant, no other VMs or heavy I/O

### What this does not measure

These benchmarks measure filesystem overhead, not network or compute.
npm's registry fetch time is included in the npm install number but is
constant across backends. The microbenchmarks (creates, stats, reads)
isolate filesystem-only cost.

## Quick start

```bash
# On any Linux host with node/npm installed:
sudo bash bench/fs-bench.sh /path/to/mount

# To also run the ext4 baseline:
sudo bash bench/fs-bench.sh /path/to/mount --baseline

# Inside a DHV guest with virtiofs:
mount -t virtiofs <tag> /mnt
bash bench/fs-bench.sh /mnt --baseline
```

Output is tab-separated to stdout, machine-parseable. Human-readable
summary at the end.

## Results

Results are dated files in `results/`. Each file records the host,
kernel, backend, and full benchmark output.

| Date | Backend | npm install | 1000 creates | Notes |
|---|---|---|---|---|
| 2026-04-21 | S3 Files (EFS) | 6555ms | 8099ms | c8i.4xlarge, managed NFS over S3 |
| 2026-04-21 | Local ext4 | 1687ms | -- | Same host, baseline |

## Backends tested

| Backend | What it is | How to mount |
|---|---|---|
| Local ext4 | Baseline. Native kernel filesystem on EBS or NVMe. | `--baseline` flag (uses /tmp) |
| S3 Files | AWS managed NFS backed by S3 (EFS engine). | `mount -t s3files <fsid>:/ /mnt` |
| virtiofsd passthrough | Stock virtiofsd serving a host ext4 dir to a DHV guest. | `virtiofsd --shared-dir /path && dhv --fs tag=X,socket=Y` |
| dedalus-fs | Our custom FUSE daemon (SQLite + Foyer + S3). | Storage daemon + DHV guest |
| NFS (FSx ONTAP) | AWS managed NFS. Legacy backend. | `mount -t nfs ...` |

## Adding a new backend

1. Mount the filesystem at some path.
2. Run `bash bench/fs-bench.sh /path/to/mount --baseline`.
3. Save output to `results/YYYY-MM-DD-<backend>.txt`.
4. Update the results table in this README.

## Scripts

| Script | Purpose |
|---|---|
| `bench/fs-bench.sh` | Core benchmark. Runs on any mounted filesystem. |
| `bench/setup-s3files.sh` | Provisions S3 Files (bucket, IAM, filesystem, mount target). |
| `bench/setup-virtiofsd.sh` | Launches virtiofsd + DHV guest with passthrough mount. |

## References

- [storage.md](https://github.com/dedalus-labs/dedalus/blob/dev/apps/cloud/apps/dcs/storage.md): DCS storage architecture
- [tiered-filesystem.mdx](https://github.com/dedalus-labs/dedalus/blob/dev/docs/src/dcs/internals/tiered-filesystem.mdx): Tiered data-path spec
- [live-vm-migrations](https://github.com/dedalus-labs/live-vm-migrations): Migration benchmarks (same methodology)
- [containers-bench](https://github.com/dedalus-labs/containers-bench): Container provider benchmarks
