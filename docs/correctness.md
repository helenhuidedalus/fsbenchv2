# Correctness Suites

fs-bench includes two POSIX/filesystem-correctness test suites that run once
(not N times) and emit pass/skip/fail counts rather than latency numbers.

## pjdfstest

**Source**: `vendor/pjdfstest/` (git submodule → github.com/pjd/pjdfstest)  
**Runner**: `bench/correctness/pjdfstest.sh`  
**How it runs**: `prove -r vendor/pjdfstest/tests` with `TMPDIR` set to the
target path.

**What it tests**: POSIX filesystem semantics — `open`, `mkdir`, `rename`,
`unlink`, `link`, `symlink`, `chmod`, `chown`, `truncate`, `stat`, and their
error conditions. Each test is a Perl TAP test that exercises one syscall and
checks that the filesystem returns the POSIX-mandated result.

**What gets skipped**:

| Reason | Tests affected |
|--------|---------------|
| No root | `chown`, `chflags`, sticky-bit tests |
| No hardlink support | `link` tests (some cloud FSes disallow cross-dir hardlinks) |
| No device files | `mknod` tests |
| No extended attributes | `getfattr`/`setfattr` tests |

A run without root will skip roughly 20–30% of tests. Results are still useful
for checking rename correctness, stat accuracy, and error codes.

## xfstests

**Source**: `vendor/xfstests/` (git submodule → git.kernel.org/xfstests-dev)  
**Runner**: `bench/correctness/xfstests.sh`  
**How it runs**: `./check -g quick` with `FSTYP=generic`, `TEST_DIR=<target>`,
`SCRATCH_MNT=<scratch>`.

**What it tests**: The `generic` group covers filesystem-agnostic correctness:
`O_CREAT`, `O_EXCL`, `O_APPEND`, `fcntl` locks, `mmap` coherence, directory
operations under concurrent access, and `fallocate`/`punch_hole` if supported.

**What gets skipped**:

| Reason | Tests affected |
|--------|---------------|
| No root | Most tests (xfstests requires root) |
| No scratch block device | Tests that require a raw device for `SCRATCH_DEV` |
| No `fallocate` support | Preallocate/punch-hole tests |
| No ACL support | ACL/xattr tests |

**Scratch directory**: `XFSTESTS_SCRATCH_DIR` must be a path on the same
filesystem type as `TARGET` but a different directory. `xfstests.sh` creates
a sibling directory automatically if the env var is not set.

## Interpreting results

- **passed**: test ran and returned TAP `ok` / xfstests `PASSED`.
- **skipped**: test determined at runtime it cannot run (missing privilege,
  unsupported feature). Skips are expected and not failures.
- **failed**: test ran, filesystem returned wrong result. Any non-zero failure
  count is worth investigating before publishing numbers — a filesystem that
  fails POSIX correctness tests may produce silently wrong outputs for real
  workloads.

## Vendor setup

Both suites live as git submodules:

```
git submodule update --init vendor/pjdfstest vendor/xfstests
```

Build artifacts (configure, Makefiles, binaries) are ignored via `.gitignore`.
The suites are built on first run by their respective runner scripts.

Pinned SHAs live in `.gitmodules` — update them intentionally and re-test
before committing a bump.
