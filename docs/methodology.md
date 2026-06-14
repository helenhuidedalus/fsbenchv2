# Methodology

## What this benchmark measures

fs-bench measures filesystem performance **as experienced by developer tooling
running inside a cloud sandbox VM**. Every timer crosses no VM boundary — the
test process and the clock live in the same guest. This means results include
the full in-guest stack: overlay layers, virtiofs transport, network-attached
backing stores — everything the user's code actually pays for.

## Repetition and statistics

Every perf test runs `N=10` iterations by default (`BENCH_N` overrides).
Each iteration creates a fresh scratch directory under the target path and
removes it afterward so iterations don't share warm OS page-cache or dentry
state.

Reported statistics:

| Stat | Meaning |
|------|---------|
| p50  | Median across N iterations — "typical" performance |
| p99  | 99th percentile across N iterations — tail behavior |

For tests that produce a latency distribution within a single iteration (fsync:
1000 samples per run), the p50/p99 are first computed per-iteration, then the
median of those values is reported across N iterations.

## Cold vs warm (npm, git)

For npm install, "cold" means the npm cache was explicitly cleared before the
run; "warm" means the cache was populated from the cold run and only FS writes
remain. The cold/warm split isolates network+FS cost from pure-FS write cost.

For git, each iteration builds a fresh source repo and clones it, so every
clone is a cold FS write. Git status is measured on the freshly-cloned repo.

## Wake time

`bench/perf/00-wake.sh` records `/proc/uptime` (time since guest boot) and the
latency of the first write to the target path. `run-one.sh` also measures
host-side wake time: the elapsed wall-clock from `vm_create()` returning to the
first successful `vm_exec()`. Both are reported so readers can distinguish
"time for provider to start the VM" from "time from boot to FS ready."

## Fairness via randomized scheduling

The GitHub Actions workflow fires on a fixed cron cadence but then sleeps a
uniform random offset (0–60 min) before touching any provider. This prevents
any provider from pre-warming capacity for a known benchmark slot. See
`scheduler/random-delay.sh` and `.github/workflows/benchmark.yml`.

## Correctness suites (root, scratch device)

Correctness suites (pjdfstest, xfstests) run once and are never included in
the N-iteration perf aggregate. They require:

- **pjdfstest**: `autoreconf`, `make`, `prove` (perl). Root improves coverage
  but is not required — tests that need elevated privileges are skipped with a
  note.
- **xfstests**: root required; a scratch directory distinct from `TEST_DIR`.
  Set `XFSTESTS_SCRATCH_DIR` to a path on the same filesystem but different
  subtree. Only the `-g quick -t generic` group runs — no device-specific tests
  that would require a raw block device.

See `docs/correctness.md` for what each suite tests and what commonly gets
skipped.

## What this benchmark does not measure

- Provider control-plane latency (API round-trip to create a sandbox). That
  cost is real but is reported separately as "wake time," not mixed into FS
  numbers.
- Network cost of npm registry fetches. The cold/warm split surfaces it
  implicitly: `cold − warm ≈ registry fetch time`.
- Filesystem-adapter-specific optimizations. No adapter code exists. We point
  the tests at the provider's default workspace mount and measure what's there.
