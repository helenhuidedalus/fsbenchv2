#!/usr/bin/env bash
# providers/tensorlake.sh — Tensorlake provider implementation.
# SDK: pip install tensorlake  |  Key: TENSORLAKE_API_KEY
# Docs: https://docs.tensorlake.ai/sandboxes/introduction
# Tensorlake runs Firecracker MicroVMs; boots in <1s; supports suspend/resume.

vm_create() {
    python3 - <<'PY'
import secrets
from tensorlake.sandbox import Sandbox

# Use a named sandbox so vm_exec/vm_destroy can reconnect by name.
name = "fs-bench-" + secrets.token_hex(4)
Sandbox.create(
    name=name,
    cpus=2.0,
    memory_mb=2048,
    disk_mb=12000,
    timeout_secs=900,  # 15-min cap — orphan self-destruct backstop
)
print(name)
PY
}

vm_exec() {
    local id="$1" cmd="$2"
    python3 - "$id" "$cmd" <<'PY'
import sys
from tensorlake.sandbox import Sandbox

sb = Sandbox.connect(sys.argv[1])
result = sb.run("sh", ["-lc", sys.argv[2]])
if result.stdout:
    print(result.stdout, end="")
if result.stderr:
    print(result.stderr, end="", file=sys.stderr)
PY
}

vm_copy_out() {
    local id="$1" src="$2" dst="$3"
    python3 - "$id" "$src" "$dst" <<'PY'
import sys
from tensorlake.sandbox import Sandbox

sb = Sandbox.connect(sys.argv[1])
data = bytes(sb.read_file(sys.argv[2]))
with open(sys.argv[3], "wb") as f:
    f.write(data)
PY
}

vm_destroy() {
    local id="$1"
    python3 - "$id" <<'PY'
import sys
from tensorlake.sandbox import Sandbox

try:
    Sandbox.connect(sys.argv[1]).terminate()
except Exception:
    pass
PY
}
