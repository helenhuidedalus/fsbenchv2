# fs-bench Specification — v2

## 1. Scope and Objective

**Objective.** A reproducible benchmark that measures a sandbox filesystem's
correctness and performance *as a user actually experiences it inside the cloud
sandbox VM*, for providers that do not expose a filesystem API. The benchmark
runs entirely inside the guest, so the test and timer never cross the VM
boundary — it measures filesystem cost as felt by developer tooling, not
control-plane or exec round-trip latency.

**What it tests.** In addition to two heavyweight POSIX/filesystem-correctness
suites (xfstests and pjdfstest), the benchmark tests: metadata ops
(create/stat/read/mkdir), rename/link/symlink, fsync latency (p50/p99),
concurrent I/O, directory listing, git operations, npm install, tar extraction,
fio (random read, random write+fsync, sequential write), per-machine **wake
time**, and an explicitly broken-out **agent install time**.

**What it explicitly does not do.**

- *No filesystem adapters.* The original repo carried `run-dedalus-fs.sh`,
  `setup-s3files.sh`, and `setup-virtiofsd.sh` to mount/provision specific
  backends. Those are not part of the v2 benchmark flow. This benchmark assumes
  the sandbox provider has already mounted its own filesystem; we point the
  tests at a path on it and measure what's there.
- *No FS-cost isolation modeling beyond the guest.* We measure the whole
  in-guest stack (overlay / virtio-fs / whatever the provider uses) as a
  single observable, because that's what the user feels.
- *No network-cost claims.* npm's registry fetch is roughly constant across
  providers; the microbenchmarks isolate FS cost from it, and cold-vs-warm npm
  separates fetch from pure-FS writes.

## 2. Benchmark Design

**Core model.** One executable, `run.sh`, that a user runs after exporting
provider API keys. It creates a sandbox VM via the provider's API/CLI, clones
this benchmark repo into the guest, runs the test suite inside the guest's
shell, pulls results back, and tears the VM down.

**Repetition.** Every test runs `N=10` times by default, configurable via
`BENCH_N`. Results report median plus p50/p99. Running N times makes
single-VM noise tractable; the first iteration of npm/git is always cold, so
cold and warm are reported as distinct series rather than averaged together.

**Fairness via randomized scheduling.** The GitHub Actions `schedule:` cron
fires on a coarse fixed cadence. The first step of the job sleeps a random
offset (`sleep $((RANDOM % WINDOW_SECONDS))`) so the real start time is
uniformly distributed across the window. This prevents any provider from
optimizing for a known slot.

**Provider keys.** Environment variables are the mechanism. For local/manual
runs, exporting in the terminal (or a git-ignored `.env` loaded by `run.sh`)
is fine. For CI, keys come from GitHub Actions encrypted secrets injected as
env vars — never a committed `.env`. A `.env.example` documents the required
variable names with empty values.

## 3. Methodology

### 3.1 Repository structure

See `README.md` for the current layout. Key points:

- `bench/fs-bench.sh` is a thin orchestrator that calls each numbered module.
- `bench/lib.sh` holds all shared timing/formatting logic.
- `bench/perf/` contains numbered modules run N times with p50/p99 output.
- `bench/correctness/` contains pass/fail suites run once.
- `vendor/` holds pinned upstream sources as git submodules.
- `providers/` holds thin per-provider SDK glue (~30 lines each).

### 3.2 Test modularization

Each file in `bench/perf/` exposes one function:

```bash
run_test <target_dir> <label> <N>
```

The orchestrator calls each module as a subprocess:
`bash bench/perf/10-metadata.sh "$TARGET" "$LABEL" "$N"`

Each module runs its operation N times, collects millisecond samples, calls
`summarize()` from `lib.sh` to get p50/p99, and prints a columnar row.

### 3.3 Agent install time

`bench/perf/60-npm.sh` installs a package set defined in `docs/packages.md`.
Among those packages are AI agent SDKs (marked `[agent]` in the Agent Packages
section). The benchmark times the agent install(s) separately and surfaces the
number as its own column in the output.

`docs/packages.md` is the single source of truth: it lists every package and
marks which entries are agents so the harness and a reader agree on what
"agent install time" includes.

### 3.4 Test conditions

- Each test runs `N=10` times (`BENCH_N` overrides).
- Scratch dirs are created per-iteration and removed after.
- Node v22+, git, fio (optional, skipped if absent).
- `run.sh` verifies target writability and FS type with `df -T` before
  trusting any baseline comparison.

### 3.5 Provider SDK contract

```bash
# vm_create               -> echoes a VM/sandbox id on stdout
# vm_exec   <id> <cmd>    -> runs cmd in the guest, streams stdout/stderr
# vm_copy_out <id> <src> <dst> -> pulls a guest path to local dst
# vm_destroy <id>         -> destroys the VM; must be idempotent, never error
```

Each `providers/<name>.sh` implements these four functions by shelling out to
tiny Python one-liners using the provider's real SDK.

## 4. Execution Environment

### 4.1 Manual / Local

```bash
bash run.sh daytona e2b
```

Provisions VMs in parallel, clones the repo into each guest, runs
`bench/fs-bench.sh <workspace>`, saves to `results/`, tears down.

### 4.2 Scheduled CI

`.github/workflows/benchmark.yml` triggers on a fixed cron, sleeps a random
offset for fairness, reads keys from encrypted Actions secrets, runs `run.sh`,
commits new results files.

### 4.3 Teardown / orphan backstop

- Teardown is trap-based in `run-one.sh` (fires on EXIT, INT, TERM).
- `bash run.sh --cleanup` lists and kills orphaned sandboxes by the `fs-bench`
  tag applied at create time.
- Provider-side max lifetime is set at create time (e.g. e2b `timeout=900`).

## 5. Metrics

| Metric | Type | Unit | Notes |
|--------|------|------|-------|
| wake time | one-time | ms | host: `vm_create` → first exec; guest: `/proc/uptime` |
| 1K creates | p50/p99 | ms | 1000 file creates per iteration |
| 1K stats | p50 | ms | 1000 `stat()` calls |
| 1K reads | p50 | ms | 1000 small-file reads |
| 100 mkdirs | p50 | ms | 100 directory creates |
| 1K renames | p50 | ms | same-dir rename |
| 1K xdir renames | p50 | ms | cross-directory rename |
| 1K hardlinks | p50 | ms | `link(2)`; N/A if unsupported |
| 1K symlinks | p50 | ms | `symlink(2)` |
| fsync total | p50/p99 | ms | wall time for 1000 create+fdatasync |
| fsync per-op | p50/p99 | µs | per-operation fdatasync latency |
| concurrent create | p50/p99 | ms | N-way parallel 1000-file create |
| ls -la | p50/p99 | ms | single listing of 1000-file dir |
| find -type f | p50/p99 | ms | recursive find on 1000-file dir |
| npm cold | p50/p99 | ms | cold install (cache cleared) |
| npm warm | p50 | ms | warm install (cache populated) |
| agent install | p50 | ms | agent package(s) install time |
| git clone | p50/p99 | ms | local clone of ~2000-file repo |
| git status | p50/p99 | ms | status on cloned repo |
| tar extraction | p50/p99 | ms | Node v22 tarball (~4800 files) |
| fio 4K randread | one-time | IOPS | 4 jobs × 256 MiB, 30s |
| fio 4K rw+fsync | one-time | IOPS | 4 jobs × 256 MiB + fsync, 30s |
| fio 1M seqwrite | one-time | MiB/s | 1 job × 1 GiB, 30s |
| pjdfstest | one-time | pass/skip/fail | POSIX correctness |
| xfstests | one-time | pass/skip/fail | generic FS correctness |
