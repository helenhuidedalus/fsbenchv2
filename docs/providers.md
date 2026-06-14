# Providers

Each provider is a ~30-line shell file in `providers/` that implements the
four-function contract documented in `providers/common.sh`. The test code never
changes — only the provider glue does.

## Adding a provider

1. Create `providers/<name>.sh` implementing `vm_create`, `vm_exec`,
   `vm_copy_out`, and `vm_destroy`.
2. Add its Python module name to `PYMOD` and its API key env var to `KEYVAR`
   in `run.sh`.
3. Add the key to `.env.example` with an empty value.
4. Test with `bash run.sh <name>`.

> **Important**: provider glue must be verified against the provider's current
> SDK docs before trusting a run. SDK method names and signatures change; a
> benchmark built on stale or guessed calls produces numbers that look real but
> aren't.

## Daytona

| Item | Value |
|------|-------|
| SDK | `pip install daytona` |
| Key | `DAYTONA_API_KEY` |
| Workspace | `/home/user` (default) |
| Orphan backstop | tag `fs-bench=1` on create; `--cleanup` finds by tag |
| Docs | https://pypi.org/project/daytona/ |

## e2b

| Item | Value |
|------|-------|
| SDK | `pip install e2b` |
| Key | `E2B_API_KEY` |
| Workspace | `/home/user` |
| Orphan backstop | `Sandbox.create(timeout=900)` — 15-min hard cap |
| Docs | https://e2b.dev/docs |

## Modal

| Item | Value |
|------|-------|
| SDK | `pip install modal` |
| Keys | `MODAL_TOKEN_ID`, `MODAL_TOKEN_SECRET` |
| Sandbox ID | `sb.object_id`; reconnect via `modal.Sandbox.from_id(id)` |
| Orphan backstop | `Sandbox.create(timeout=900)` — 15-min hard cap |
| Exec | `sb.exec("bash", "-c", cmd)` → `ContainerProcess`; read after `proc.wait()` |
| Copy out | `sb.filesystem.copy_to_local(remote, local)` |
| Destroy | `sb.terminate()` — idempotent (no-op if already terminated) |
| Docs | https://modal.com/docs/reference/modal.Sandbox |

## Tensorlake

| Item | Value |
|------|-------|
| SDK | `pip install tensorlake` |
| Key | `TENSORLAKE_API_KEY` |
| VM type | Firecracker MicroVM; boots <1s; supports suspend/resume |
| Sandbox ID | Named at create time (`"fs-bench-<hex>"`); reconnect via `Sandbox.connect(name)` |
| Orphan backstop | `Sandbox.create(timeout_secs=900)` — 15-min hard cap |
| Exec | `sb.run("sh", ["-lc", cmd])` → result with `.stdout`, `.returncode` |
| Copy out | `bytes(sb.read_file(path))` |
| Destroy | `sb.terminate()` — irreversible |
| Docs | https://docs.tensorlake.ai/sandboxes/introduction |

