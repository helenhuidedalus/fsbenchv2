# Filesystem Benchmark

Reproducible benchmarks measuring filesystem performance for cloud dev
environment workloads. Tests metadata ops, rename/link/symlink, fsync,
concurrent I/O, git ops, npm install, tar extraction, and fio across
filesystem backends.

## Methodology

**npm install** is the headline metric. It exercises the exact operation
mix (create, write, rename, stat, readdir) that dominates developer
experience in cloud IDEs. Everything else is diagnostic.

### Test matrix

| Test | What it measures |
|---|---|
| **1K creates** | Raw metadata write: `open(O_CREAT) + write + close` |
| **1K stats** | Warm metadata read: `stat()` on recent files |
| **1K reads** | Warm data read: small-file `cat` |
| **100 mkdirs** | Directory creation throughput |
| **1K renames** | Same-dir `rename(2)` (npm's temp-then-rename pattern) |
| **1K cross-dir renames** | Cross-directory `rename(2)` (harder on some FS) |
| **1K hardlinks** | `link(2)` throughput (pnpm content-addressed store) |
| **1K symlinks** | `symlink(2)` throughput |
| **1K create+fsync** | Per-file `fdatasync` latency with p50/p99 |
| **4-way concurrent create** | Lock contention under parallel metadata writes |
| **ls -la (1000)** | Single large directory listing |
| **find -type f** | Recursive tree walk |
| **npm install cold** | End-to-end: registry fetch + filesystem writes |
| **npm install warm** | Second install (no registry, pure FS) |
| **git clone (local)** | Bulk metadata create + data write (2000 files) |
| **git status** | `lstat()` every tracked file |
| **tar extract** | Bulk mixed-size write (~4800 files, 90 MiB) |
| **fio 4K randread** | Random read IOPS (IDE random access proxy) |
| **fio 4K randwrite+fsync** | Random write IOPS with durability |
| **fio 1M seqwrite** | Sequential write throughput |

### Test conditions

- **Workload**: `npm install typescript eslint prettier` (~1300 files)
- **Runs**: cold (first) and warm (second, same session)
- **Node**: v22+
- **fio**: optional (skipped if not installed)
- **Single-tenant**: no concurrent VMs or heavy I/O

### What this does not measure

Filesystem overhead only. npm's registry fetch is constant across
backends. The microbenchmarks isolate FS cost from network cost.

## Quick start

```bash
# On any Linux host with node/npm:
bash bench/fs-bench.sh /path/to/mount --baseline

# Skip slow tests:
BENCH_SKIP_FIO=1 BENCH_SKIP_TAR=1 bash bench/fs-bench.sh /path --baseline

# Inside a DHV guest with virtiofs:
mount -t virtiofs <tag> /mnt
bash bench/fs-bench.sh /mnt --baseline
```

Output is columnar (kubectl-style). Each section has a header and
aligned columns.

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `BENCH_SKIP_NPM` | 0 | Skip npm install tests |
| `BENCH_SKIP_TAR` | 0 | Skip tar extraction |
| `BENCH_SKIP_GIT` | 0 | Skip git operations |
| `BENCH_SKIP_FIO` | 0 | Skip fio tests |
| `BENCH_CONCURRENCY` | 4 | Parallel create workers |

## Results

Results are dated files in `results/`. Each file records host, kernel,
backend, and full benchmark output.

| Date | Backend | npm install | 1K creates | Notes |
|---|---|---|---|---|
| 2026-04-21 | S3 Files (EFS) | 6555ms | 8099ms | c8i.4xlarge, managed NFS over S3 |
| 2026-04-21 | Local ext4 | 1687ms | -- | Same host, baseline |

## Backends tested

| Backend | What it is |
|---|---|
| Local ext4 | Baseline. Native kernel FS on EBS/NVMe. |
| S3 Files | AWS managed NFS backed by S3 (EFS engine). |
| virtiofsd passthrough | Stock virtiofsd serving host ext4 dir via virtio-fs. |
| dedalus-fs | Custom FUSE daemon (SQLite + Foyer + S3). |

## Adding a new backend

1. Mount the filesystem.
2. Run `bash bench/fs-bench.sh /mount --baseline`.
3. Save output to `results/YYYY-MM-DD-<backend>.txt`.
4. Update the results table.

## Scripts

| Script | Purpose |
|---|---|
| `bench/fs-bench.sh` | Core benchmark. Runs on any mounted filesystem. |
| `bench/setup-s3files.sh` | Provision S3 Files (bucket, IAM, FS, mount target). |
| `bench/setup-virtiofsd.sh` | Launch virtiofsd + DHV guest with passthrough. |

## References

- [live-vm-migrations](https://github.com/dedalus-labs/live-vm-migrations): Migration benchmarks (same methodology)
- [containers-bench](https://github.com/dedalus-labs/containers-bench): Container provider benchmarks
- [mdtest](https://github.com/LLNL/mdtest): IO500 metadata benchmark (industry standard)
- [fio](https://github.com/axboe/fio): Flexible I/O tester
