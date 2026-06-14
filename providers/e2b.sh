#!/usr/bin/env bash
# providers/e2b.sh — e2b provider implementation.
# SDK: pip install e2b  |  Key: E2B_API_KEY
# Verify against: https://e2b.dev/docs before trusting a run.
# Sandboxes self-destruct after `timeout` seconds (orphan backstop).

vm_create() {
    python3 - <<'PY'
from e2b import Sandbox

sb = Sandbox.create(timeout=900)   # 15-min cap = orphan self-destruct
print(sb.sandbox_id)
PY
}

vm_exec() {
    local id="$1" cmd="$2"
    python3 - "$id" "$cmd" <<'PY'
import sys
from e2b import Sandbox

sb = Sandbox.connect(sys.argv[1])
r = sb.commands.run(sys.argv[2], timeout=0)
print(r.stdout)
if r.stderr:
    print(r.stderr, file=__import__("sys").stderr)
PY
}

vm_copy_out() {
    local id="$1" src="$2" dst="$3"
    python3 - "$id" "$src" "$dst" <<'PY'
import sys
from e2b import Sandbox

sb = Sandbox.connect(sys.argv[1])
data = sb.files.read(sys.argv[2])
with open(sys.argv[3], "w") as f:
    f.write(data)
PY
}

vm_destroy() {
    local id="$1"
    python3 - "$id" <<'PY'
import sys
from e2b import Sandbox

try:
    Sandbox.connect(sys.argv[1]).kill()
except Exception:
    pass
PY
}
