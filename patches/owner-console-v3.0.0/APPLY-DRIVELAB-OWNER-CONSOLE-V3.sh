#!/usr/bin/env bash
set -Eeuo pipefail

PATCH_VERSION="3.0.0"
BASE_URL="https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/owner-console-v3.0.0"
APP_ROOT="/opt/drivelab-license"
PACKAGE_ROOT="$APP_ROOT/drivelab_license"
DATA_ROOT="/var/lib/drivelab-license"
ENV_FILE="/etc/drivelab-license/license.env"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d /tmp/drivelab-owner-v3.XXXXXX)"
STAGE="$WORK/stage"
DOWNLOADS="$WORK/downloads"
BACKUP_ROOT="/var/backups/drivelab-owner-console-v3/$STAMP"
LOG="$BACKUP_ROOT/install.log"
CHANGED=0

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this installer with sudo." >&2
    exit 1
fi

mkdir -p "$DOWNLOADS" "$STAGE" "$BACKUP_ROOT"
touch "$LOG"
chmod 0600 "$LOG"
exec > >(tee -a "$LOG") 2>&1

echo
echo "============================================================"
echo "DRIVELAB OWNER CONSOLE V${PATCH_VERSION} GUARDED INSTALLER"
echo "============================================================"
echo "Backup: $BACKUP_ROOT"
echo

for command in curl python3 systemctl tar; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Required command is missing: $command" >&2
        exit 1
    }
done

for path in \
    "$PACKAGE_ROOT/admin_app.py" \
    "$PACKAGE_ROOT/owner_console.py" \
    "$PACKAGE_ROOT/admin_ops.py" \
    "$PACKAGE_ROOT/admin_metrics.py" \
    "$PACKAGE_ROOT/release_admin.py" \
    "$APP_ROOT/.venv/bin/python" \
    "$DATA_ROOT/licenses.db" \
    "$ENV_FILE"
do
    [[ -e "$path" ]] || {
        echo "Required live file was not found: $path" >&2
        exit 1
    }
done

if grep -q 'DriveLab Owner Control Center v3.0.0' "$PACKAGE_ROOT/admin_app.py"; then
    echo "Owner Console v3.0.0 is already installed. No file was changed."
    exit 0
fi

grep -q '# DriveLab Owner Console v2' "$PACKAGE_ROOT/admin_app.py" || {
    echo "The expected Owner Console v2 anchor is missing from admin_app.py." >&2
    exit 1
}
grep -q '# DriveLab admin reliability and operations pages v1.0.3' "$PACKAGE_ROOT/admin_app.py" || {
    echo "The expected admin operations anchor is missing from admin_app.py." >&2
    exit 1
}
grep -q 'DL_ADMIN_METRICS_V1' "$PACKAGE_ROOT/owner_console.py" || {
    echo "The exact History & Trends-enabled owner_console.py was not found." >&2
    exit 1
}
grep -q 'ADMIN_OPS_VERSION = "1.0.4"' "$PACKAGE_ROOT/admin_ops.py" || {
    echo "The exact admin operations v1.0.4 source was not found." >&2
    exit 1
}

echo "===== DOWNLOADING OWNER CONSOLE V3 PAYLOAD ====="
for file in \
    owner_control_center.py \
    drivelab-owner-ops-worker \
    drivelab-owner-ops.path \
    drivelab-owner-ops.service
do
    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 3 \
        --connect-timeout 15 \
        "$BASE_URL/$file" \
        --output "$DOWNLOADS/$file"
    [[ -s "$DOWNLOADS/$file" ]] || {
        echo "Downloaded payload is empty: $file" >&2
        exit 1
    }
done

python3 -m py_compile \
    "$DOWNLOADS/owner_control_center.py" \
    "$DOWNLOADS/drivelab-owner-ops-worker"

systemd-analyze verify \
    "$DOWNLOADS/drivelab-owner-ops.path" \
    "$DOWNLOADS/drivelab-owner-ops.service" \
    >/dev/null

echo "Payload syntax and systemd validation passed."

echo
echo "===== STAGING CURRENT SOURCE ====="
mkdir -p "$STAGE/drivelab_license" "$STAGE/tests"
cp -a "$PACKAGE_ROOT/." "$STAGE/drivelab_license/"
if [[ -d "$APP_ROOT/tests" ]]; then
    cp -a "$APP_ROOT/tests/." "$STAGE/tests/"
fi
cp -a "$DOWNLOADS/owner_control_center.py" "$STAGE/drivelab_license/owner_control_center.py"

python3 - "$STAGE" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

stage = Path(sys.argv[1])
package = stage / "drivelab_license"
admin_app_path = package / "admin_app.py"
owner_path = package / "owner_console.py"
ops_path = package / "admin_ops.py"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one anchor but found {count}")
    return text.replace(old, new, 1)

admin_app = read(admin_app_path)
owner = read(owner_path)
ops = read(ops_path)

install_anchor = '''install_admin_ops(
    app,
    settings,
    db,
    authenticated,
    require_auth,
    require_csrf,
)
'''
install_block = install_anchor + '''

# DriveLab Owner Control Center v3.0.0
from .owner_control_center import install_owner_control_center

install_owner_control_center(
    app,
    settings,
    db,
    authenticated,
    require_auth,
    require_csrf,
)
'''
admin_app = replace_once(
    admin_app,
    install_anchor,
    install_block,
    "admin_app Owner Control Center registration",
)

metrics_import = '''from .admin_metrics import (
    METRICS_STYLE,
    ensure_metrics_schema,
    load_metrics_dashboard,
    record_metrics_snapshot,
    render_metrics_dashboard,
)
'''
metrics_with_control = metrics_import + '''from .owner_control_center import dashboard_alert_html
'''
owner = replace_once(
    owner,
    metrics_import,
    metrics_with_control,
    "owner_console control-center import",
)

owner_nav = '''            "<a href='/'>Dashboard</a>"
            "<a href='/owner/operations'>Operations</a>"
'''
owner_nav_new = '''            "<a href='/'>Dashboard</a>"
            "<a href='/owner/control-center'>Control Center</a>"
            "<a href='/owner/activity'>Activity</a>"
            "<a href='/owner/customers'>Customers</a>"
            "<a href='/owner/operations'>Operations</a>"
'''
owner = replace_once(owner, owner_nav, owner_nav_new, "owner_console navigation")
owner = replace_once(
    owner,
    "        content = [notice_html(notice)]\n",
    "        content = [notice_html(notice)]\n        content.append(dashboard_alert_html(settings, db))\n",
    "owner_console dashboard alert",
)

ops_nav = '''        "<a href='/'>Dashboard</a>"
        "<a href='/owner/operations'>Operations</a>"
'''
ops_nav_new = '''        "<a href='/'>Dashboard</a>"
        "<a href='/owner/control-center'>Control Center</a>"
        "<a href='/owner/activity'>Activity</a>"
        "<a href='/owner/customers'>Customers</a>"
        "<a href='/owner/operations'>Operations</a>"
'''
ops = replace_once(ops, ops_nav, ops_nav_new, "admin_ops navigation")

required = {
    "admin_app.py": ["DriveLab Owner Control Center v3.0.0", "install_owner_control_center("],
    "owner_console.py": ["dashboard_alert_html", "/owner/control-center", "/owner/activity", "/owner/customers"],
    "admin_ops.py": ["/owner/control-center", "/owner/activity", "/owner/customers"],
}
values = {
    "admin_app.py": admin_app,
    "owner_console.py": owner,
    "admin_ops.py": ops,
}
for name, markers in required.items():
    for marker in markers:
        if marker not in values[name]:
            raise RuntimeError(f"{name} validation failed: {marker}")

write(admin_app_path, admin_app)
write(owner_path, owner)
write(ops_path, ops)
PY

echo "Source patch staged successfully."

echo
echo "===== COMPILING AND TESTING STAGED SOURCE ====="
mkdir -p "$WORK/pycache"
chown -R drivelab-license:drivelab-license "$WORK/pycache" "$STAGE"

runuser -u drivelab-license -- env \
    PYTHONPATH="$STAGE" \
    PYTHONPYCACHEPREFIX="$WORK/pycache" \
    "$APP_ROOT/.venv/bin/python" \
    -m compileall \
    -q \
    "$STAGE/drivelab_license"

if [[ -d "$STAGE/tests" ]] && find "$STAGE/tests" -type f -name 'test_*.py' -print -quit | grep -q .; then
    runuser -u drivelab-license -- env \
        PYTHONPATH="$STAGE" \
        PYTHONPYCACHEPREFIX="$WORK/pycache" \
        "$APP_ROOT/.venv/bin/python" \
        -m pytest \
        -q \
        "$STAGE/tests"
fi

echo "Staged source compilation and tests passed."

echo
echo "===== CREATING VERIFIED PRE-INSTALL BACKUP ====="
systemctl start drivelab-admin-backup-v2.service
systemctl is-failed --quiet drivelab-admin-backup-v2.service && {
    echo "The verified pre-install backup service failed." >&2
    exit 1
}

mkdir -p "$BACKUP_ROOT/files" "$BACKUP_ROOT/systemd"
for file in admin_app.py owner_console.py admin_ops.py; do
    cp -a "$PACKAGE_ROOT/$file" "$BACKUP_ROOT/files/$file"
done
if [[ -f "$PACKAGE_ROOT/owner_control_center.py" ]]; then
    cp -a "$PACKAGE_ROOT/owner_control_center.py" "$BACKUP_ROOT/files/owner_control_center.py"
    touch "$BACKUP_ROOT/files/owner_control_center.preexisting"
fi
for file in \
    /usr/local/sbin/drivelab-owner-ops-worker \
    /etc/systemd/system/drivelab-owner-ops.path \
    /etc/systemd/system/drivelab-owner-ops.service
do
    if [[ -f "$file" ]]; then
        cp -a "$file" "$BACKUP_ROOT/systemd/$(basename "$file")"
        touch "$BACKUP_ROOT/systemd/$(basename "$file").preexisting"
    fi
done

python3 - "$DATA_ROOT/licenses.db" "$BACKUP_ROOT/licenses-before-owner-v3.db" <<'PY'
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
chmod 0600 "$BACKUP_ROOT/licenses-before-owner-v3.db"

cat > "$BACKUP_ROOT/ROLLBACK.sh" <<ROLLBACK
#!/usr/bin/env bash
set -Eeuo pipefail
[[ \"\\${EUID}\" -eq 0 ]] || { echo \"Run with sudo.\" >&2; exit 1; }
systemctl stop drivelab-license-admin.service || true
install -o root -g drivelab-license -m 0640 \"$BACKUP_ROOT/files/admin_app.py\" \"$PACKAGE_ROOT/admin_app.py\"
install -o root -g drivelab-license -m 0640 \"$BACKUP_ROOT/files/owner_console.py\" \"$PACKAGE_ROOT/owner_console.py\"
install -o root -g drivelab-license -m 0640 \"$BACKUP_ROOT/files/admin_ops.py\" \"$PACKAGE_ROOT/admin_ops.py\"
if [[ -f \"$BACKUP_ROOT/files/owner_control_center.preexisting\" ]]; then
    install -o root -g drivelab-license -m 0640 \"$BACKUP_ROOT/files/owner_control_center.py\" \"$PACKAGE_ROOT/owner_control_center.py\"
else
    rm -f \"$PACKAGE_ROOT/owner_control_center.py\"
fi
for name in drivelab-owner-ops-worker drivelab-owner-ops.path drivelab-owner-ops.service; do
    case \"\\$name\" in
        drivelab-owner-ops-worker) destination=\"/usr/local/sbin/\\$name\" ;;
        *) destination=\"/etc/systemd/system/\\$name\" ;;
    esac
    if [[ -f \"$BACKUP_ROOT/systemd/\\$name.preexisting\" ]]; then
        install -o root -g root -m \"\$( [[ \"\\$name\" == drivelab-owner-ops-worker ]] && echo 0750 || echo 0644 )\" \"$BACKUP_ROOT/systemd/\\$name\" \"\\$destination\"
    else
        rm -f \"\\$destination\"
    fi
done
systemctl daemon-reload
systemctl disable --now drivelab-owner-ops.path 2>/dev/null || true
systemctl restart drivelab-license-admin.service
for attempt in \$(seq 1 30); do
    systemctl is-active --quiet drivelab-license-admin.service && break
    sleep 1
done
echo \"Owner Console source and units restored from $BACKUP_ROOT\"
echo \"The additive owner_* SQLite tables are intentionally retained; they do not alter licensing or activation behavior.\"
ROLLBACK
chmod 0700 "$BACKUP_ROOT/ROLLBACK.sh"

sha256sum \
    "$BACKUP_ROOT/files/admin_app.py" \
    "$BACKUP_ROOT/files/owner_console.py" \
    "$BACKUP_ROOT/files/admin_ops.py" \
    "$BACKUP_ROOT/licenses-before-owner-v3.db" \
    > "$BACKUP_ROOT/SHA256SUMS.txt"

rollback_now() {
    local status=$?
    if [[ "$CHANGED" -eq 1 ]]; then
        echo
echo "INSTALLATION FAILED — RESTORING PREVIOUS OWNER CONSOLE" >&2
        bash "$BACKUP_ROOT/ROLLBACK.sh" || true
    fi
    exit "$status"
}
trap rollback_now ERR

echo
echo "===== INSTALLING OWNER CONSOLE V3 ====="
CHANGED=1
install -o root -g drivelab-license -m 0640 \
    "$STAGE/drivelab_license/owner_control_center.py" \
    "$PACKAGE_ROOT/owner_control_center.py"
install -o root -g drivelab-license -m 0640 \
    "$STAGE/drivelab_license/admin_app.py" \
    "$PACKAGE_ROOT/admin_app.py"
install -o root -g drivelab-license -m 0640 \
    "$STAGE/drivelab_license/owner_console.py" \
    "$PACKAGE_ROOT/owner_console.py"
install -o root -g drivelab-license -m 0640 \
    "$STAGE/drivelab_license/admin_ops.py" \
    "$PACKAGE_ROOT/admin_ops.py"

install -o root -g root -m 0750 \
    "$DOWNLOADS/drivelab-owner-ops-worker" \
    /usr/local/sbin/drivelab-owner-ops-worker
install -o root -g root -m 0644 \
    "$DOWNLOADS/drivelab-owner-ops.path" \
    /etc/systemd/system/drivelab-owner-ops.path
install -o root -g root -m 0644 \
    "$DOWNLOADS/drivelab-owner-ops.service" \
    /etc/systemd/system/drivelab-owner-ops.service

mkdir -p "$DATA_ROOT/ops/requests" "$DATA_ROOT/ops/results" "$DATA_ROOT/ops/pycache"
chown -R drivelab-license:drivelab-license "$DATA_ROOT/ops"
chmod 0750 "$DATA_ROOT/ops" "$DATA_ROOT/ops/requests" "$DATA_ROOT/ops/results" "$DATA_ROOT/ops/pycache"

cat > "$DATA_ROOT/ops/owner-console-v3.json" <<JSON
{
  "installed_at": $(date +%s),
  "version": "$PATCH_VERSION",
  "backup": "$BACKUP_ROOT"
}
JSON
chown drivelab-license:drivelab-license "$DATA_ROOT/ops/owner-console-v3.json"
chmod 0640 "$DATA_ROOT/ops/owner-console-v3.json"

systemctl daemon-reload
systemctl enable --now drivelab-owner-ops.path
systemctl restart drivelab-license-admin.service

echo
echo "===== VALIDATING LIVE SERVICES ====="
for attempt in $(seq 1 35); do
    if systemctl is-active --quiet drivelab-license-admin.service; then
        break
    fi
    sleep 1
done
systemctl is-active --quiet drivelab-license-admin.service
systemctl is-active --quiet drivelab-license-api.service
systemctl is-active --quiet drivelab-owner-ops.path

readarray -t ADMIN_ADDRESS < <(python3 - "$ENV_FILE" <<'PY'
import sys

values = {}
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    values[key.strip()] = value.strip().strip('"').strip("'")
host = values.get("DLT_ADMIN_HOST", "127.0.0.1")
if host in {"0.0.0.0", "::", "[::]", ""}:
    host = "127.0.0.1"
port = values.get("DLT_ADMIN_PORT", "8788")
print(host)
print(port)
PY
)
ADMIN_HOST="${ADMIN_ADDRESS[0]}"
ADMIN_PORT="${ADMIN_ADDRESS[1]}"
ADMIN_BASE="http://${ADMIN_HOST}:${ADMIN_PORT}"

for attempt in $(seq 1 35); do
    code="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 4 "$ADMIN_BASE/login" || true)"
    [[ "$code" == "200" ]] && break
    sleep 1
done
[[ "${code:-}" == "200" ]] || {
    echo "Owner Console login page did not become healthy at $ADMIN_BASE/login" >&2
    exit 1
}

control_code="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 4 "$ADMIN_BASE/owner/control-center" || true)"
[[ "$control_code" == "303" ]] || {
    echo "The unauthenticated Control Center route returned HTTP $control_code instead of 303." >&2
    exit 1
}

curl --fail --silent --show-error --max-time 6 \
    http://127.0.0.1:8787/v1/health \
    >/dev/null
curl --fail --silent --show-error --max-time 6 \
    http://127.0.0.1:8790/healthz \
    >/dev/null

if journalctl -u drivelab-license-admin.service --since "2 minutes ago" --no-pager | grep -Eq 'Traceback|SyntaxError|ImportError|ModuleNotFoundError'; then
    echo "A Python error appeared in the Owner Console journal after restart." >&2
    journalctl -u drivelab-license-admin.service --since "2 minutes ago" --no-pager
    exit 1
fi

python3 - "$DATA_ROOT/licenses.db" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
try:
    quick = connection.execute("PRAGMA quick_check").fetchone()[0]
    if str(quick).lower() != "ok":
        raise SystemExit(f"Database quick_check failed: {quick}")
    required = {
        "owner_customer_meta",
        "owner_support_events",
        "owner_operation_history",
        "owner_health_history",
    }
    present = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    missing = sorted(required - present)
    if missing:
        raise SystemExit(f"Owner Console schema is missing: {', '.join(missing)}")
finally:
    connection.close()
PY

CHANGED=0
trap - ERR

echo
echo "============================================================"
echo "DRIVELAB OWNER CONSOLE V${PATCH_VERSION} INSTALLED SUCCESSFULLY"
echo "============================================================"
echo "Owner Console: $ADMIN_BASE"
echo "Control Center: $ADMIN_BASE/owner/control-center"
echo "Activity: $ADMIN_BASE/owner/activity"
echo "Customers: $ADMIN_BASE/owner/customers"
echo "Backup and rollback: $BACKUP_ROOT"
echo
echo "The Android app, licenses, activation keys, production APK, signed update feed, RaceLink data, and public website content were not changed."
