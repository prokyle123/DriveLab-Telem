#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="3.0.0"
APP_ROOT="/opt/drivelab-license"
PACKAGE_ROOT="$APP_ROOT/drivelab_license"
VENV_PYTHON="$APP_ROOT/.venv/bin/python"
ENV_FILE="/etc/drivelab-license/license.env"
STAGING_PARENT="/var/lib/drivelab-owner-staging"
BACKUP_PARENT="/var/backups/drivelab-owner-console-v3-safe"
STAMP="$(date +%Y%m%d-%H%M%S)"
CHANGED=0
BACKUP_ROOT=""

SOURCE_NAMES=(
    admin_app.py
    owner_console.py
    admin_ops.py
    owner_control_center.py
)

HELPER_TARGETS=(
    /usr/local/sbin/drivelab-owner-test-runner.py
    /usr/local/sbin/drivelab-owner-ops-worker
)

UNIT_TARGETS=(
    /etc/systemd/system/drivelab-owner-ops.path
    /etc/systemd/system/drivelab-owner-ops.service
)

fail() {
    echo "ERROR: $*" >&2
    return 1
}

backup_file() {
    local target="$1"
    local destination_dir="$2"
    local name="$3"
    mkdir -p "$destination_dir"
    if [[ -e "$target" || -L "$target" ]]; then
        cp -a "$target" "$destination_dir/$name"
        touch "$destination_dir/$name.existed"
    else
        touch "$destination_dir/$name.missing"
    fi
}

restore_file() {
    local target="$1"
    local backup_dir="$2"
    local name="$3"
    if [[ -f "$backup_dir/$name.existed" ]]; then
        rm -f "$target"
        cp -a "$backup_dir/$name" "$target"
    else
        rm -f "$target"
    fi
}

restore_database() {
    local backup_database="$1"
    local live_database="$2"
    python3 - "$backup_database" "$live_database" <<'PY'
import sqlite3
import sys

source = sqlite3.connect(sys.argv[1], timeout=30)
target = sqlite3.connect(sys.argv[2], timeout=30)
try:
    source.backup(target)
finally:
    target.close()
    source.close()
PY
}

restore_from_backup() {
    local backup="$1"
    [[ -d "$backup" ]] || fail "Backup directory does not exist: $backup"
    [[ -f "$backup/state.env" ]] || fail "Backup state file is missing: $backup/state.env"

    set +u
    # shellcheck disable=SC1090
    source "$backup/state.env"
    set -u

    echo
    echo "============================================================"
    echo "RESTORING DRIVELAB OWNER CONSOLE FROM BACKUP"
    echo "============================================================"
    echo "Backup: $backup"
    echo

    systemctl stop drivelab-license-admin.service 2>/dev/null || true
    systemctl disable --now drivelab-owner-ops.path 2>/dev/null || true

    for name in "${SOURCE_NAMES[@]}"; do
        restore_file "$PACKAGE_ROOT/$name" "$backup/source" "$name"
    done

    restore_file "/usr/local/sbin/drivelab-owner-test-runner.py" "$backup/helpers" "drivelab-owner-test-runner.py"
    restore_file "/usr/local/sbin/drivelab-owner-ops-worker" "$backup/helpers" "drivelab-owner-ops-worker"
    restore_file "/etc/systemd/system/drivelab-owner-ops.path" "$backup/units" "drivelab-owner-ops.path"
    restore_file "/etc/systemd/system/drivelab-owner-ops.service" "$backup/units" "drivelab-owner-ops.service"

    if [[ -f "$backup/licenses-before.db" ]]; then
        restore_database "$backup/licenses-before.db" "$LIVE_DB"
    fi

    systemctl daemon-reload

    if [[ "${PATH_WAS_ENABLED:-0}" == "1" ]] && [[ -f /etc/systemd/system/drivelab-owner-ops.path ]]; then
        systemctl enable drivelab-owner-ops.path >/dev/null
    else
        systemctl disable drivelab-owner-ops.path >/dev/null 2>&1 || true
    fi

    if [[ "${PATH_WAS_ACTIVE:-0}" == "1" ]] && [[ -f /etc/systemd/system/drivelab-owner-ops.path ]]; then
        systemctl start drivelab-owner-ops.path
    fi

    if [[ "${ADMIN_WAS_ACTIVE:-1}" == "1" ]]; then
        systemctl start drivelab-license-admin.service
        for _attempt in $(seq 1 30); do
            systemctl is-active --quiet drivelab-license-admin.service && break
            sleep 1
        done
        systemctl is-active --quiet drivelab-license-admin.service
    fi

    echo
    echo "RESTORE COMPLETED"
    echo "The previous Owner Console source, database, helper files, and unit state were restored."
}

rollback_on_error() {
    local status=$?
    trap - ERR INT TERM
    set +e
    if [[ "$CHANGED" == "1" ]] && [[ -n "$BACKUP_ROOT" ]]; then
        echo
        echo "PROMOTION FAILED — AUTOMATICALLY RESTORING THE PREVIOUS CONSOLE" >&2
        restore_from_backup "$BACKUP_ROOT" || true
    fi
    exit "$status"
}

if [[ "${1:-}" == "--restore" ]]; then
    [[ "$EUID" -eq 0 ]] || {
        echo "Run restore mode with sudo." >&2
        exit 1
    }
    [[ -n "${2:-}" ]] || {
        echo "Usage: sudo bash PROMOTE-TESTED-STAGE.sh --restore /path/to/backup" >&2
        exit 1
    }
    restore_from_backup "$(readlink -f "$2")"
    exit 0
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this promotion script with sudo." >&2
    exit 1
fi

for command in curl python3 sha256sum runuser systemctl readlink diff; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Required command is missing: $command" >&2
        exit 1
    }
done

STAGE_INPUT="${1:-$STAGING_PARENT/LATEST}"
STAGE="$(readlink -f "$STAGE_INPUT")"
[[ -d "$STAGE" ]] || {
    echo "Staged directory does not exist: $STAGE_INPUT" >&2
    exit 1
}
case "$STAGE" in
    "$STAGING_PARENT"/v3-*) ;;
    *)
        echo "Refusing a stage outside $STAGING_PARENT: $STAGE" >&2
        exit 1
        ;;
esac

SRC="$STAGE/src"
PAYLOAD="$STAGE/payload"
READY="$STAGE/READY.json"

for required in \
    "$READY" \
    "$STAGE/live-source-after.sha256" \
    "$STAGE/staged-source.sha256" \
    "$STAGE/payload.sha256" \
    "$SRC/drivelab_license/admin_app.py" \
    "$SRC/drivelab_license/owner_console.py" \
    "$SRC/drivelab_license/admin_ops.py" \
    "$SRC/drivelab_license/owner_control_center.py" \
    "$PAYLOAD/test_runner.py" \
    "$PAYLOAD/drivelab-owner-ops-worker" \
    "$PAYLOAD/drivelab-owner-ops.path" \
    "$PAYLOAD/drivelab-owner-ops.service" \
    "$ENV_FILE" \
    "$VENV_PYTHON"
do
    [[ -e "$required" ]] || {
        echo "Required promotion input is missing: $required" >&2
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
ADMIN_TOKEN="${DLT_ADMIN_TOKEN:-}"
ADMIN_HOST="${DLT_ADMIN_HOST:-127.0.0.1}"
ADMIN_PORT="${DLT_ADMIN_PORT:-8788}"
if [[ "$ADMIN_HOST" == "0.0.0.0" || "$ADMIN_HOST" == "::" || "$ADMIN_HOST" == "[::]" || -z "$ADMIN_HOST" ]]; then
    ADMIN_HOST="127.0.0.1"
fi
ADMIN_BASE="http://$ADMIN_HOST:$ADMIN_PORT"

[[ -f "$LIVE_DB" ]] || {
    echo "Live database does not exist: $LIVE_DB" >&2
    exit 1
}
[[ -n "$ADMIN_TOKEN" ]] || {
    echo "The existing admin token is missing from $ENV_FILE" >&2
    exit 1
}

python3 - "$READY" "$STAGE" <<'PY'
import json
import sys
import time
from pathlib import Path

ready_path = Path(sys.argv[1])
stage = Path(sys.argv[2]).resolve()
value = json.loads(ready_path.read_text(encoding="utf-8"))
if value.get("schema") != 1:
    raise SystemExit("READY.json has an unsupported schema.")
if value.get("version") != "3.0.0":
    raise SystemExit("READY.json does not describe Owner Console 3.0.0.")
if value.get("status") != "READY_FOR_PROMOTION":
    raise SystemExit("The staged package is not marked READY_FOR_PROMOTION.")
if Path(value.get("stage", "")).resolve() != stage:
    raise SystemExit("READY.json points to a different staging directory.")
required = {
    "core_license_flow": "passed",
    "signed_update": "passed",
    "live_staged_http_routes": "passed",
    "copied_database_integrity": "passed",
    "live_source_unchanged": "passed",
}
tests = value.get("tests") or {}
for key, expected in required.items():
    if tests.get(key) != expected:
        raise SystemExit(f"Required staged test did not pass: {key}")
age = time.time() - ready_path.stat().st_mtime
if age > 24 * 3600:
    raise SystemExit("The READY marker is older than 24 hours. Run staging again.")
print("READY marker and required staged tests verified.")
PY

echo
echo "============================================================"
echo "DRIVELAB OWNER CONSOLE V${VERSION} — TESTED-STAGE PROMOTION"
echo "============================================================"
echo "Stage: $STAGE"
echo "Owner Console: $ADMIN_BASE"
echo

echo "===== VERIFYING THE EXACT TESTED STAGE ====="
sha256sum --check "$STAGE/staged-source.sha256"
sha256sum --check "$STAGE/payload.sha256"
sha256sum --check "$STAGE/live-source-after.sha256"

grep -q 'DriveLab Owner Control Center v3.0.0' "$SRC/drivelab_license/admin_app.py"
grep -q 'CONTROL_CENTER_VERSION = "3.0.0"' "$SRC/drivelab_license/owner_control_center.py"
grep -q 'optional Starlette TestClient dependency is not installed' "$PAYLOAD/test_runner.py"
grep -q '^PathExistsGlob=/var/lib/drivelab-license/ops/requests/\*.request$' "$PAYLOAD/drivelab-owner-ops.path"
grep -q '^ExecStart=/usr/local/sbin/drivelab-owner-ops-worker$' "$PAYLOAD/drivelab-owner-ops.service"

mkdir -p "$STAGE/promotion-pycache"
chown -R drivelab-license:drivelab-license "$STAGE/promotion-pycache"
chmod 0750 "$STAGE/promotion-pycache"
runuser -u drivelab-license -- env \
    PYTHONPATH="$SRC" \
    PYTHONPYCACHEPREFIX="$STAGE/promotion-pycache" \
    "$VENV_PYTHON" \
    -m compileall \
    -q \
    "$SRC/drivelab_license"

echo "Tested source, payload, live-source baseline, and Python compilation verified."

echo
echo "===== VERIFYING CURRENT PRODUCTION HEALTH ====="
systemctl is-active --quiet drivelab-license-admin.service
curl --fail --silent --show-error --max-time 8 "$ADMIN_BASE/login" >/dev/null
curl --fail --silent --show-error --max-time 8 http://127.0.0.1:8787/v1/health >/dev/null
curl --fail --silent --show-error --max-time 8 http://127.0.0.1:8790/healthz >/dev/null
python3 - "$LIVE_DB" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1], timeout=30)
try:
    result = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(result).lower() != "ok":
        raise SystemExit(f"Live database quick_check failed before promotion: {result}")
finally:
    connection.close()
print("Current production health and database integrity passed.")
PY

echo
echo "===== CREATING COMPLETE PRE-PROMOTION BACKUP ====="
BACKUP_ROOT="$BACKUP_PARENT/$STAMP"
mkdir -p "$BACKUP_ROOT/source" "$BACKUP_ROOT/helpers" "$BACKUP_ROOT/units"
chmod 0700 "$BACKUP_ROOT"

ADMIN_WAS_ACTIVE=0
PATH_WAS_ACTIVE=0
PATH_WAS_ENABLED=0
systemctl is-active --quiet drivelab-license-admin.service && ADMIN_WAS_ACTIVE=1 || true
systemctl is-active --quiet drivelab-owner-ops.path && PATH_WAS_ACTIVE=1 || true
systemctl is-enabled --quiet drivelab-owner-ops.path && PATH_WAS_ENABLED=1 || true

for name in "${SOURCE_NAMES[@]}"; do
    backup_file "$PACKAGE_ROOT/$name" "$BACKUP_ROOT/source" "$name"
done
backup_file "/usr/local/sbin/drivelab-owner-test-runner.py" "$BACKUP_ROOT/helpers" "drivelab-owner-test-runner.py"
backup_file "/usr/local/sbin/drivelab-owner-ops-worker" "$BACKUP_ROOT/helpers" "drivelab-owner-ops-worker"
backup_file "/etc/systemd/system/drivelab-owner-ops.path" "$BACKUP_ROOT/units" "drivelab-owner-ops.path"
backup_file "/etc/systemd/system/drivelab-owner-ops.service" "$BACKUP_ROOT/units" "drivelab-owner-ops.service"

python3 - "$LIVE_DB" "$BACKUP_ROOT/licenses-before.db" <<'PY'
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
chmod 0600 "$BACKUP_ROOT/licenses-before.db"

cat > "$BACKUP_ROOT/state.env" <<EOF
ADMIN_WAS_ACTIVE=$ADMIN_WAS_ACTIVE
PATH_WAS_ACTIVE=$PATH_WAS_ACTIVE
PATH_WAS_ENABLED=$PATH_WAS_ENABLED
LIVE_DB=$(printf '%q' "$LIVE_DB")
EOF
chmod 0600 "$BACKUP_ROOT/state.env"

cp -a "$0" "$BACKUP_ROOT/RESTORE-OWNER-CONSOLE.sh"
chmod 0700 "$BACKUP_ROOT/RESTORE-OWNER-CONSOLE.sh"

systemctl start drivelab-admin-backup-v2.service

sha256sum "$BACKUP_ROOT/licenses-before.db" "$BACKUP_ROOT/source"/* 2>/dev/null \
    | grep -v '\.existed$' \
    | grep -v '\.missing$' \
    > "$BACKUP_ROOT/BACKUP-SHA256.txt" || true

python3 - "$BACKUP_ROOT/licenses-before.db" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1])
try:
    result = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(result).lower() != "ok":
        raise SystemExit(f"Backup database quick_check failed: {result}")
finally:
    connection.close()
print("Complete source, service-file, and SQLite backup verified.")
PY

trap rollback_on_error ERR INT TERM

echo
echo "===== PROMOTING THE EXACT TESTED FILES ====="
CHANGED=1

install -o root -g drivelab-license -m 0640 \
    "$SRC/drivelab_license/admin_app.py" \
    "$PACKAGE_ROOT/admin_app.py"
install -o root -g drivelab-license -m 0640 \
    "$SRC/drivelab_license/owner_console.py" \
    "$PACKAGE_ROOT/owner_console.py"
install -o root -g drivelab-license -m 0640 \
    "$SRC/drivelab_license/admin_ops.py" \
    "$PACKAGE_ROOT/admin_ops.py"
install -o root -g drivelab-license -m 0640 \
    "$SRC/drivelab_license/owner_control_center.py" \
    "$PACKAGE_ROOT/owner_control_center.py"

install -o root -g drivelab-license -m 0750 \
    "$PAYLOAD/test_runner.py" \
    /usr/local/sbin/drivelab-owner-test-runner.py
install -o root -g root -m 0750 \
    "$PAYLOAD/drivelab-owner-ops-worker" \
    /usr/local/sbin/drivelab-owner-ops-worker
install -o root -g root -m 0644 \
    "$PAYLOAD/drivelab-owner-ops.path" \
    /etc/systemd/system/drivelab-owner-ops.path
install -o root -g root -m 0644 \
    "$PAYLOAD/drivelab-owner-ops.service" \
    /etc/systemd/system/drivelab-owner-ops.service

mkdir -p /var/lib/drivelab-license/ops/requests /var/lib/drivelab-license/ops/results /var/lib/drivelab-license/ops/pycache
chown -R drivelab-license:drivelab-license /var/lib/drivelab-license/ops
chmod 0750 /var/lib/drivelab-license/ops /var/lib/drivelab-license/ops/requests /var/lib/drivelab-license/ops/results /var/lib/drivelab-license/ops/pycache

PYTHONPATH="$APP_ROOT" "$VENV_PYTHON" - "$LIVE_DB" <<'PY'
import sqlite3
import sys
from pathlib import Path
from drivelab_license.owner_control_center import ensure_control_schema

path = Path(sys.argv[1])
ensure_control_schema(path)
connection = sqlite3.connect(path)
try:
    result = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(result).lower() != "ok":
        raise SystemExit(f"Database quick_check failed after schema installation: {result}")
finally:
    connection.close()
print("Owner Console schema installed and database integrity passed.")
PY

VALIDATION_SINCE="$(date '+%Y-%m-%d %H:%M:%S')"
systemctl daemon-reload
systemctl enable --now drivelab-owner-ops.path
systemctl restart drivelab-license-admin.service

for _attempt in $(seq 1 45); do
    systemctl is-active --quiet drivelab-license-admin.service && break
    sleep 1
done
systemctl is-active --quiet drivelab-license-admin.service
systemctl is-active --quiet drivelab-owner-ops.path

echo
echo "===== VALIDATING THE LIVE PROMOTION ====="
LOGIN_CODE=""
for _attempt in $(seq 1 45); do
    LOGIN_CODE="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 4 "$ADMIN_BASE/login" || true)"
    [[ "$LOGIN_CODE" == "200" ]] && break
    sleep 1
done
[[ "$LOGIN_CODE" == "200" ]] || fail "Owner Console login returned HTTP $LOGIN_CODE instead of 200."

AUTH_HEADER="Authorization: Bearer $ADMIN_TOKEN"
VALIDATION_DIR="$BACKUP_ROOT/live-validation"
mkdir -p "$VALIDATION_DIR"
chmod 0700 "$VALIDATION_DIR"

curl --fail --silent --show-error --max-time 20 -H "$AUTH_HEADER" \
    "$ADMIN_BASE/owner/control-center" \
    --output "$VALIDATION_DIR/control-center.html"
curl --fail --silent --show-error --max-time 20 -H "$AUTH_HEADER" \
    "$ADMIN_BASE/owner/customers" \
    --output "$VALIDATION_DIR/customers.html"
curl --fail --silent --show-error --max-time 20 -H "$AUTH_HEADER" \
    "$ADMIN_BASE/owner/activity" \
    --output "$VALIDATION_DIR/activity.html"
curl --fail --silent --show-error --max-time 20 -H "$AUTH_HEADER" \
    "$ADMIN_BASE/" \
    --output "$VALIDATION_DIR/dashboard.html"

grep -q 'Control Center v3.0.0' "$VALIDATION_DIR/control-center.html"
grep -q 'Customer and support records' "$VALIDATION_DIR/customers.html"
grep -q 'Unified activity timeline' "$VALIDATION_DIR/activity.html"
grep -q 'Owner Control Center:' "$VALIDATION_DIR/dashboard.html"

UNAUTH_CODE="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 "$ADMIN_BASE/owner/control-center" || true)"
[[ "$UNAUTH_CODE" == "303" ]] || fail "Unauthenticated Control Center returned HTTP $UNAUTH_CODE instead of 303."

curl --fail --silent --show-error --max-time 10 http://127.0.0.1:8787/v1/health >/dev/null
curl --fail --silent --show-error --max-time 10 http://127.0.0.1:8790/healthz >/dev/null

python3 - "$LIVE_DB" <<'PY'
import sqlite3
import sys
connection = sqlite3.connect(sys.argv[1], timeout=30)
try:
    result = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(result).lower() != "ok":
        raise SystemExit(f"Live database quick_check failed: {result}")
    required = {
        "owner_customer_meta",
        "owner_support_events",
        "owner_operation_history",
        "owner_health_history",
    }
    present = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    missing = sorted(required - present)
    if missing:
        raise SystemExit("Missing Owner Console tables: " + ", ".join(missing))
finally:
    connection.close()
print("Live database integrity and Owner Console schema passed.")
PY

if journalctl -u drivelab-license-admin.service --since "$VALIDATION_SINCE" --no-pager \
    | grep -Eq 'Traceback|SyntaxError|ImportError|ModuleNotFoundError|Application startup failed'; then
    journalctl -u drivelab-license-admin.service --since "$VALIDATION_SINCE" --no-pager
    fail "The Owner Console journal contains a Python startup/runtime error."
fi

cat > /var/lib/drivelab-license/ops/owner-console-v3.json <<EOF
{
  "version": "3.0.0",
  "installed_at": $(date +%s),
  "tested_stage": "$STAGE",
  "backup": "$BACKUP_ROOT"
}
EOF
chown drivelab-license:drivelab-license /var/lib/drivelab-license/ops/owner-console-v3.json
chmod 0640 /var/lib/drivelab-license/ops/owner-console-v3.json

ln -sfn "$BACKUP_ROOT" "$BACKUP_PARENT/LATEST-SUCCESSFUL"
CHANGED=0
trap - ERR INT TERM

echo
echo "============================================================"
echo "DRIVELAB OWNER CONSOLE V${VERSION} PROMOTED SUCCESSFULLY"
echo "============================================================"
echo "Control Center: $ADMIN_BASE/owner/control-center"
echo "Customers:      $ADMIN_BASE/owner/customers"
echo "Activity:       $ADMIN_BASE/owner/activity"
echo "Backup:         $BACKUP_ROOT"
echo
echo "Manual rollback command, only if ever needed:"
echo "sudo bash $BACKUP_ROOT/RESTORE-OWNER-CONSOLE.sh --restore $BACKUP_ROOT"
echo
echo "The Android APK, update feed, license keys, activation records, RaceLink data, and public website content were not modified."
