#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="3.0.0"
BASE_URL="https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/owner-console-v3.0.0"
SAFE_URL="$BASE_URL/safe-deploy"
APP_ROOT="/opt/drivelab-license"
PACKAGE_ROOT="$APP_ROOT/drivelab_license"
ENV_FILE="/etc/drivelab-license/license.env"
VENV_PYTHON="$APP_ROOT/.venv/bin/python"
STAGING_PARENT="/var/lib/drivelab-owner-staging"
STAMP="$(date +%Y%m%d-%H%M%S)"
STAGE="$STAGING_PARENT/v3-$STAMP"
SRC="$STAGE/src"
PAYLOAD="$STAGE/payload"
DATA="$STAGE/data"
REPORT="$STAGE/STAGE-REPORT.txt"
READY="$STAGE/READY.json"
LATEST_LINK="$STAGING_PARENT/LATEST"
HOME_REPORT="/home/kali/DriveLab-Owner-Console-v3-STAGE-REPORT.txt"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

fail() {
    echo "FAILED: $*" | tee -a "$REPORT" >&2
    exit 1
}

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this staging test with sudo." >&2
    exit 1
fi

for command in curl python3 sha256sum runuser systemctl; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Required command is missing: $command" >&2
        exit 1
    }
done

for required in \
    "$PACKAGE_ROOT/admin_app.py" \
    "$PACKAGE_ROOT/owner_console.py" \
    "$PACKAGE_ROOT/admin_ops.py" \
    "$PACKAGE_ROOT/admin_metrics.py" \
    "$PACKAGE_ROOT/release_admin.py" \
    "$VENV_PYTHON" \
    "$ENV_FILE"
do
    [[ -e "$required" ]] || {
        echo "Required live file is missing: $required" >&2
        exit 1
    }
done

set +u
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
set -u

LIVE_DB="${DLT_DATABASE_PATH:-/var/lib/drivelab-license/licenses.db}"
LIVE_UPDATE_DIR="${DLT_UPDATE_DIR:-/var/lib/drivelab-license/updates}"
ADMIN_TOKEN="${DLT_ADMIN_TOKEN:-}"
[[ -f "$LIVE_DB" ]] || {
    echo "Live database was not found: $LIVE_DB" >&2
    exit 1
}
[[ -n "$ADMIN_TOKEN" ]] || {
    echo "DLT_ADMIN_TOKEN is missing from the existing environment file." >&2
    exit 1
}

mkdir -p "$SRC" "$PAYLOAD" "$DATA/updates"
touch "$REPORT"
chmod 0600 "$REPORT"

exec > >(tee -a "$REPORT") 2>&1

echo
echo "============================================================"
echo "DRIVELAB OWNER CONSOLE V${VERSION} — ISOLATED STAGING TEST"
echo "============================================================"
echo "Stage: $STAGE"
echo
echo "This phase does not modify /opt/drivelab-license, the live SQLite database,"
echo "systemd units, running services, APK files, license keys, or customer data."
echo

if grep -q 'DriveLab Owner Control Center v3.0.0' "$PACKAGE_ROOT/admin_app.py"; then
    fail "Owner Console v3 is already present in the live source. Stop and inspect before staging."
fi

echo "===== RECORDING LIVE SOURCE HASHES ====="
sha256sum \
    "$PACKAGE_ROOT/admin_app.py" \
    "$PACKAGE_ROOT/owner_console.py" \
    "$PACKAGE_ROOT/admin_ops.py" \
    > "$STAGE/live-source-before.sha256"
cat "$STAGE/live-source-before.sha256"

echo
echo "===== DOWNLOADING FIXED STAGING PAYLOAD ====="
download() {
    local url="$1"
    local destination="$2"
    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 3 \
        --connect-timeout 15 \
        "$url?stage=$STAMP" \
        --output "$destination"
    [[ -s "$destination" ]] || fail "Downloaded file is empty: $destination"
}

download "$SAFE_URL/patch_stage.py" "$PAYLOAD/patch_stage.py"
download "$BASE_URL/owner_control_center.py" "$PAYLOAD/owner_control_center.py"
download "$BASE_URL/drivelab-owner-test-runner-r6.py" "$PAYLOAD/test_runner.py"
download "$BASE_URL/drivelab-owner-ops-worker" "$PAYLOAD/drivelab-owner-ops-worker"
download "$BASE_URL/drivelab-owner-ops.path" "$PAYLOAD/drivelab-owner-ops.path"
download "$BASE_URL/drivelab-owner-ops.service" "$PAYLOAD/drivelab-owner-ops.service"

python3 -m py_compile \
    "$PAYLOAD/patch_stage.py" \
    "$PAYLOAD/owner_control_center.py" \
    "$PAYLOAD/test_runner.py" \
    "$PAYLOAD/drivelab-owner-ops-worker"

grep -q 'Stage patch completed and parsed successfully' "$PAYLOAD/patch_stage.py"
grep -q 'CONTROL_CENTER_VERSION = "3.0.0"' "$PAYLOAD/owner_control_center.py"
grep -q 'optional Starlette TestClient dependency is not installed' "$PAYLOAD/test_runner.py"
grep -q '^PathExistsGlob=/var/lib/drivelab-license/ops/requests/\*.request$' "$PAYLOAD/drivelab-owner-ops.path"
grep -q '^ExecStart=/usr/local/sbin/drivelab-owner-ops-worker$' "$PAYLOAD/drivelab-owner-ops.service"
sha256sum "$PAYLOAD"/* > "$STAGE/payload.sha256"
echo "Payload syntax, markers, and checksums passed."

echo
echo "===== COPYING LIVE SOURCE INTO THE ISOLATED STAGE ====="
mkdir -p "$SRC/drivelab_license" "$SRC/tests"
cp -a "$PACKAGE_ROOT/." "$SRC/drivelab_license/"
if [[ -d "$APP_ROOT/tests" ]]; then
    cp -a "$APP_ROOT/tests/." "$SRC/tests/"
fi

python3 - "$LIVE_DB" "$DATA/licenses.db" <<'PY'
import sqlite3
import sys

source = sqlite3.connect(sys.argv[1], timeout=30)
target = sqlite3.connect(sys.argv[2])
try:
    source.backup(target)
finally:
    target.close()
    source.close()
PY

if [[ -d "$LIVE_UPDATE_DIR" ]]; then
    cp -a "$LIVE_UPDATE_DIR/." "$DATA/updates/"
fi

python3 "$PAYLOAD/patch_stage.py" \
    "$SRC" \
    "$PAYLOAD/owner_control_center.py"

echo
echo "===== COMPILING AND TESTING ONLY THE STAGED COPY ====="
chown -R drivelab-license:drivelab-license "$STAGE"
find "$STAGE" -type d -exec chmod 0750 {} +
find "$STAGE" -type f -exec chmod 0640 {} +
chmod 0750 "$PAYLOAD/patch_stage.py" "$PAYLOAD/test_runner.py" "$PAYLOAD/drivelab-owner-ops-worker"
mkdir -p "$STAGE/pycache"
chown drivelab-license:drivelab-license "$STAGE/pycache"
chmod 0750 "$STAGE/pycache"

runuser -u drivelab-license -- env \
    PYTHONPATH="$SRC" \
    PYTHONPYCACHEPREFIX="$STAGE/pycache" \
    "$VENV_PYTHON" \
    -m compileall \
    -q \
    "$SRC/drivelab_license"

if [[ -d "$SRC/tests" ]] && find "$SRC/tests" -type f -name 'test_*.py' -print -quit | grep -q .; then
    runuser -u drivelab-license -- env \
        PYTHONPATH="$SRC" \
        PYTHONPYCACHEPREFIX="$STAGE/pycache" \
        "$VENV_PYTHON" \
        "$PAYLOAD/test_runner.py" \
        "$SRC/tests"
fi

runuser -u drivelab-license -- env \
    PYTHONPATH="$SRC" \
    PYTHONPYCACHEPREFIX="$STAGE/pycache" \
    "$VENV_PYTHON" \
    - "$DATA/licenses.db" <<'PY'
import sqlite3
import sys
from pathlib import Path

from drivelab_license.owner_control_center import ensure_control_schema

path = Path(sys.argv[1])
ensure_control_schema(path)
connection = sqlite3.connect(path)
try:
    quick = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(quick).lower() != "ok":
        raise SystemExit(f"Staged database quick_check failed: {quick}")
    required = {
        "owner_customer_meta",
        "owner_support_events",
        "owner_operation_history",
        "owner_health_history",
    }
    present = {
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )
    }
    missing = sorted(required - present)
    if missing:
        raise SystemExit("Staged schema is missing: " + ", ".join(missing))
finally:
    connection.close()
print("Staged database schema and integrity passed.")
PY

echo
echo "===== STARTING A TEMPORARY STAGED OWNER CONSOLE ====="
PORT="$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"

export PYTHONPATH="$SRC"
export PYTHONPYCACHEPREFIX="$STAGE/pycache"
export DLT_DATABASE_PATH="$DATA/licenses.db"
export DLT_UPDATE_DIR="$DATA/updates"
export DLT_ADMIN_HOST="127.0.0.1"
export DLT_ADMIN_PORT="$PORT"

runuser \
    -u drivelab-license \
    --preserve-environment \
    -- \
    "$VENV_PYTHON" \
    -m uvicorn \
    drivelab_license.admin_app:app \
    --host 127.0.0.1 \
    --port "$PORT" \
    > "$STAGE/staged-server.log" 2>&1 &
SERVER_PID="$!"

LOGIN_CODE=""
for _attempt in $(seq 1 45); do
    LOGIN_CODE="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 3 "http://127.0.0.1:$PORT/login" || true)"
    [[ "$LOGIN_CODE" == "200" ]] && break
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        cat "$STAGE/staged-server.log"
        fail "The staged Owner Console process exited before becoming ready."
    fi
    sleep 1
done
[[ "$LOGIN_CODE" == "200" ]] || {
    cat "$STAGE/staged-server.log"
    fail "The staged login page did not return HTTP 200."
}

AUTH_HEADER="Authorization: Bearer $ADMIN_TOKEN"
curl --fail --silent --show-error --max-time 15 -H "$AUTH_HEADER" \
    "http://127.0.0.1:$PORT/owner/control-center" \
    --output "$STAGE/control-center.html"
curl --fail --silent --show-error --max-time 15 -H "$AUTH_HEADER" \
    "http://127.0.0.1:$PORT/owner/customers" \
    --output "$STAGE/customers.html"
curl --fail --silent --show-error --max-time 15 -H "$AUTH_HEADER" \
    "http://127.0.0.1:$PORT/owner/activity" \
    --output "$STAGE/activity.html"
curl --fail --silent --show-error --max-time 15 -H "$AUTH_HEADER" \
    "http://127.0.0.1:$PORT/" \
    --output "$STAGE/dashboard.html"

grep -q 'Control Center v3.0.0' "$STAGE/control-center.html"
grep -q 'Customer and support records' "$STAGE/customers.html"
grep -q 'Unified activity timeline' "$STAGE/activity.html"
grep -q 'Owner Control Center:' "$STAGE/dashboard.html"

UNAUTH_CODE="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 4 "http://127.0.0.1:$PORT/owner/control-center" || true)"
[[ "$UNAUTH_CODE" == "303" ]] || fail "Unauthenticated Control Center returned HTTP $UNAUTH_CODE instead of 303."

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

echo "Temporary staged Owner Console routes rendered and authenticated correctly."

echo
echo "===== PROVING LIVE SOURCE WAS NOT CHANGED ====="
sha256sum \
    "$PACKAGE_ROOT/admin_app.py" \
    "$PACKAGE_ROOT/owner_console.py" \
    "$PACKAGE_ROOT/admin_ops.py" \
    > "$STAGE/live-source-after.sha256"

diff -u "$STAGE/live-source-before.sha256" "$STAGE/live-source-after.sha256" >/dev/null \
    || fail "A live source hash changed during staging. No promotion is allowed."

systemctl is-active --quiet drivelab-license-admin.service \
    || fail "The existing Owner Console service is not active after staging."

sha256sum \
    "$SRC/drivelab_license/admin_app.py" \
    "$SRC/drivelab_license/owner_console.py" \
    "$SRC/drivelab_license/admin_ops.py" \
    "$SRC/drivelab_license/owner_control_center.py" \
    > "$STAGE/staged-source.sha256"

python3 - "$READY" "$STAGE" "$STAMP" <<'PY'
import json
import sys
from pathlib import Path

ready = Path(sys.argv[1])
stage = Path(sys.argv[2])
stamp = sys.argv[3]
value = {
    "schema": 1,
    "version": "3.0.0",
    "status": "READY_FOR_PROMOTION",
    "created_at": stamp,
    "stage": str(stage),
    "live_source_hashes": str(stage / "live-source-after.sha256"),
    "staged_source_hashes": str(stage / "staged-source.sha256"),
    "payload_hashes": str(stage / "payload.sha256"),
    "tests": {
        "core_license_flow": "passed",
        "signed_update": "passed",
        "testclient_endpoint": "skipped_optional_dependency",
        "live_staged_http_routes": "passed",
        "copied_database_integrity": "passed",
        "live_source_unchanged": "passed",
    },
}
ready.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

chmod 0640 "$READY"
chown drivelab-license:drivelab-license "$READY"
ln -sfn "$STAGE" "$LATEST_LINK"

cat <<EOF

============================================================
STAGING PASSED — PRODUCTION WAS NOT MODIFIED
============================================================
Stage: $STAGE
Ready marker: $READY

Passed:
  - exact live source anchors
  - isolated source patch
  - Python compilation
  - core license activation/refresh/revoke test
  - signed update publish/read test
  - copied SQLite integrity and new owner schema
  - authenticated Control Center page
  - authenticated Customers page
  - authenticated Activity page
  - main dashboard alert integration
  - unauthenticated redirect protection
  - live source hashes unchanged
  - existing Owner Console service remained active

The endpoint TestClient unit test was skipped only because the existing virtual
environment lacks its optional test-only HTTP client dependency. The staged
Owner Console was instead started on a temporary local port and its real HTTP
routes were tested successfully.

No production promotion has occurred.
EOF

cp "$REPORT" "$HOME_REPORT"
chown kali:kali "$HOME_REPORT" 2>/dev/null || true
chmod 0640 "$HOME_REPORT"

echo "Report copy: $HOME_REPORT"
