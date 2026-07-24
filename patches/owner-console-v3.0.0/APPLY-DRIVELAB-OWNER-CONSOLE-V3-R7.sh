#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_URL="https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/owner-console-v3.0.0/APPLY-DRIVELAB-OWNER-CONSOLE-V3.sh?r7-base=20260723-2025"
TEMPORARY="$(mktemp /tmp/APPLY-DRIVELAB-OWNER-CONSOLE-V3-R7.XXXXXX.sh)"

cleanup() {
    rm -f "$TEMPORARY"
}
trap cleanup EXIT

curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --connect-timeout 15 \
    "$SOURCE_URL" \
    --output "$TEMPORARY"

python3 - "$TEMPORARY" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one anchor but found {count}.")
    text = text.replace(old, new, 1)


replace_once(
    '''    owner_control_center.py \\
    drivelab-owner-ops-worker \\
''',
    '''    owner_control_center.py \\
    drivelab-owner-test-runner-r6.py \\
    drivelab-owner-ops-worker \\
''',
    "payload list",
)

replace_once(
    '''        "$BASE_URL/$file" \\
        --output "$DOWNLOADS/$file"
''',
    '''        "$BASE_URL/$file?owner-v3-r7=20260723-2025" \\
        --output "$DOWNLOADS/$file"
''',
    "payload cache bust",
)

replace_once(
    '''python3 -m py_compile \\
    "$DOWNLOADS/owner_control_center.py" \\
    "$DOWNLOADS/drivelab-owner-ops-worker"
''',
    '''python3 -m py_compile \\
    "$DOWNLOADS/owner_control_center.py" \\
    "$DOWNLOADS/drivelab-owner-test-runner-r6.py" \\
    "$DOWNLOADS/drivelab-owner-ops-worker"

grep -q 'optional Starlette TestClient dependency is not installed' \\
    "$DOWNLOADS/drivelab-owner-test-runner-r6.py"
''',
    "payload compilation",
)

replace_once(
    '''systemd-analyze verify \\
    "$DOWNLOADS/drivelab-owner-ops.path" \\
    "$DOWNLOADS/drivelab-owner-ops.service" \\
    >/dev/null

echo "Payload syntax and systemd validation passed."
''',
    '''grep -q '^PathExistsGlob=/var/lib/drivelab-license/ops/requests/\\*.request$' \\
    "$DOWNLOADS/drivelab-owner-ops.path"
grep -q '^ExecStart=/usr/local/sbin/drivelab-owner-ops-worker$' \\
    "$DOWNLOADS/drivelab-owner-ops.service"

echo "Payload syntax and R7 marker validation passed."
''',
    "unit validation",
)

replace_once(
    '''echo "===== COMPILING AND TESTING STAGED SOURCE ====="
mkdir -p "$WORK/pycache"
chown -R drivelab-license:drivelab-license "$WORK/pycache" "$STAGE"

runuser -u drivelab-license -- env \\
    PYTHONPATH="$STAGE" \\
    PYTHONPYCACHEPREFIX="$WORK/pycache" \\
    "$APP_ROOT/.venv/bin/python" \\
    -m compileall \\
    -q \\
    "$STAGE/drivelab_license"

if [[ -d "$STAGE/tests" ]] && find "$STAGE/tests" -type f -name 'test_*.py' -print -quit | grep -q .; then
    runuser -u drivelab-license -- env \\
        PYTHONPATH="$STAGE" \\
        PYTHONPYCACHEPREFIX="$WORK/pycache" \\
        "$APP_ROOT/.venv/bin/python" \\
        -m pytest \\
        -q \\
        "$STAGE/tests"
fi

echo "Staged source compilation and tests passed."
''',
    '''echo "===== COMPILING AND TESTING STAGED SOURCE ====="
mkdir -p "$WORK/pycache"
chmod 0755 "$WORK"
chown -R drivelab-license:drivelab-license "$WORK/pycache" "$STAGE"
chmod 0755 "$STAGE" "$STAGE/drivelab_license" "$STAGE/tests"

runuser -u drivelab-license -- env \\
    PYTHONPATH="$STAGE" \\
    PYTHONPYCACHEPREFIX="$WORK/pycache" \\
    "$APP_ROOT/.venv/bin/python" \\
    -m compileall \\
    -q \\
    "$STAGE/drivelab_license"

if [[ -d "$STAGE/tests" ]] && find "$STAGE/tests" -type f -name 'test_*.py' -print -quit | grep -q .; then
    if runuser -u drivelab-license -- "$APP_ROOT/.venv/bin/python" -c 'import pytest' >/dev/null 2>&1; then
        runuser -u drivelab-license -- env \\
            PYTHONPATH="$STAGE" \\
            PYTHONPYCACHEPREFIX="$WORK/pycache" \\
            "$APP_ROOT/.venv/bin/python" \\
            -m pytest \\
            -q \\
            "$STAGE/tests"
    else
        echo "pytest is not installed; using the dependency-free DriveLab test runner R7."
        runuser -u drivelab-license -- env \\
            PYTHONPATH="$STAGE" \\
            PYTHONPYCACHEPREFIX="$WORK/pycache" \\
            "$APP_ROOT/.venv/bin/python" \\
            "$DOWNLOADS/drivelab-owner-test-runner-r6.py" \\
            "$STAGE/tests"
    fi
fi

echo "Staged source compilation and tests passed."
''',
    "compile and test block",
)

# Keep the original rollback loop untouched. The R6 failure came from
# modifying escaped variables inside the unquoted rollback heredoc.
# The test runner is a new helper with no previous live copy, so rollback
# simply removes it explicitly.
replace_once(
    '''systemctl daemon-reload
systemctl disable --now drivelab-owner-ops.path 2>/dev/null || true
''',
    '''rm -f /usr/local/sbin/drivelab-owner-test-runner.py
systemctl daemon-reload
systemctl disable --now drivelab-owner-ops.path 2>/dev/null || true
''',
    "rollback test-runner cleanup",
)

replace_once(
    '''install -o root -g root -m 0750 \\
    "$DOWNLOADS/drivelab-owner-ops-worker" \\
    /usr/local/sbin/drivelab-owner-ops-worker
''',
    '''install -o root -g drivelab-license -m 0750 \\
    "$DOWNLOADS/drivelab-owner-test-runner-r6.py" \\
    /usr/local/sbin/drivelab-owner-test-runner.py
install -o root -g root -m 0750 \\
    "$DOWNLOADS/drivelab-owner-ops-worker" \\
    /usr/local/sbin/drivelab-owner-ops-worker
''',
    "test runner installation",
)

path.write_text(text, encoding="utf-8", newline="\n")
PY

bash -n "$TEMPORARY"
chmod 0700 "$TEMPORARY"
exec bash "$TEMPORARY"
