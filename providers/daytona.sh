#!/usr/bin/env bash
# providers/daytona.sh — Daytona provider implementation.
# SDK: pip install daytona  |  Key: DAYTONA_API_KEY
# Verify against: https://pypi.org/project/daytona/ before trusting a run.

vm_create() {
    python3 - <<'PY'
import os, sys
from daytona import Daytona, CreateSandboxFromImageParams

d = Daytona()
params = CreateSandboxFromImageParams(labels={"fs-bench": "1"})
sb = d.create(params)
print(sb.id)
PY
}

vm_exec() {
    local id="$1" cmd="$2"
    python3 - "$id" "$cmd" <<'PY'
import sys
from daytona import Daytona

d = Daytona()
sb = d.get(sys.argv[1])
r = sb.process.exec(sys.argv[2])
print(r.result)
PY
}

vm_copy_out() {
    local id="$1" src="$2" dst="$3"
    python3 - "$id" "$src" "$dst" <<'PY'
import sys
from daytona import Daytona

d = Daytona()
sb = d.get(sys.argv[1])
data = sb.fs.download_file(sys.argv[2])
with open(sys.argv[3], "wb") as f:
    f.write(data)
PY
}

vm_destroy() {
    local id="$1"
    python3 - "$id" <<'PY'
import sys
from daytona import Daytona

d = Daytona()
try:
    d.delete(d.get(sys.argv[1]))
except Exception:
    pass
PY
}
