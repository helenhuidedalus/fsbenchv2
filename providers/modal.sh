#!/usr/bin/env bash
# providers/modal.sh — Modal provider implementation.
# SDK: pip install modal  |  Keys: MODAL_TOKEN_ID + MODAL_TOKEN_SECRET
# Docs: https://modal.com/docs/reference/modal.Sandbox

vm_create() {
    python3 - <<'PY'
import modal

app = modal.App.lookup("fs-bench", create_if_missing=True)
sb = modal.Sandbox.create(
    app=app,
    timeout=900,   # 15-min cap — orphan self-destruct backstop
)
print(sb.object_id)
PY
}

vm_exec() {
    local id="$1" cmd="$2"
    python3 - "$id" "$cmd" <<'PY'
import sys, modal

sb = modal.Sandbox.from_id(sys.argv[1])
proc = sb.exec("bash", "-c", sys.argv[2])
proc.wait()
out = proc.stdout.read()
err = proc.stderr.read()
if out:
    print(out, end="")
if err:
    print(err, end="", file=sys.stderr)
PY
}

vm_copy_out() {
    local id="$1" src="$2" dst="$3"
    python3 - "$id" "$src" "$dst" <<'PY'
import sys, modal

sb = modal.Sandbox.from_id(sys.argv[1])
sb.filesystem.copy_to_local(sys.argv[2], sys.argv[3])
PY
}

vm_destroy() {
    local id="$1"
    python3 - "$id" <<'PY'
import sys, modal

try:
    modal.Sandbox.from_id(sys.argv[1]).terminate()
except Exception:
    pass
PY
}
