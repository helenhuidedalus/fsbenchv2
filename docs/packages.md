# npm Packages

Single source of truth for all packages installed by `bench/perf/60-npm.sh`.

Packages under **Agent Packages** are installed as a separate timed step so
the output surfaces `agent install` time independently from the base toolchain
install. This makes the agent-install cost visible without burying it in the
aggregate npm time.

---

## Base Packages

Installed first; measured as `cold` (npm cache cleared) and `warm` (cache
populated, fresh `node_modules`).

- typescript
- eslint
- prettier

---

## Agent Packages

Installed after the base toolchain in the same `node_modules` tree.  
Timed separately and reported as the `agent install` column.

- @anthropic-ai/sdk
- openai
- openclaw
- ai
- @google/genai
- langchain

---

## Notes

- No version pins by default; `latest` is intentional so results reflect
  current package sizes. Pin a version (e.g. `typescript@5.4.5`) in this
  file to lock reproducibility for a specific run window.
- To add or remove a package, edit this file only — the harness reads it
  at runtime via `awk`.
- Packages that pull in native addons (`.node` bindings) will show higher
  install times on filesystems with poor metadata throughput; this is
  intentional signal.
