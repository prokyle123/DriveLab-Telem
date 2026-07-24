from __future__ import annotations

import html
import json
import sqlite3
import time
from pathlib import Path
from typing import Any
from urllib.parse import quote

from fastapi import Cookie, Form, Header, HTTPException, Query
from fastapi.responses import HTMLResponse, RedirectResponse

from .lifecycle import ensure_lifecycle_schema


OWNER_LIFECYCLE_VERSION = "1.0.0"

STYLE = r"""
:root{color-scheme:dark;--bg:#0c1118;--panel:#131d28;--panel2:#172433;--line:#2d4055;--text:#edf5fc;--muted:#9fb0c2;--cyan:#50d8f2;--green:#67dda0;--amber:#ffc766;--red:#ff7280;--purple:#be8cff;--blue:#7ba7ff}
*{box-sizing:border-box}body{margin:0 auto;padding:22px;max-width:1750px;background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,Segoe UI,sans-serif}a{color:var(--cyan);text-decoration:none}a:hover{text-decoration:underline}h1,h2,h3{margin:.2rem 0 .65rem}.topbar{display:flex;justify-content:space-between;align-items:flex-start;flex-wrap:wrap;gap:14px;margin-bottom:14px}.nav{display:flex;gap:8px;flex-wrap:wrap}.nav a{padding:8px 11px;border:1px solid var(--line);border-radius:8px;background:#152130}.panel{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px;margin:14px 0;box-shadow:0 7px 24px #0005}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:11px}.card{background:var(--panel2);border:1px solid #324a62;border-radius:10px;padding:13px}.card strong{display:block;font-size:1.55rem;margin-bottom:3px}.card span{color:var(--muted)}.two{display:grid;grid-template-columns:repeat(auto-fit,minmax(390px,1fr));gap:14px}.table-wrap{overflow:auto;border:1px solid var(--line);border-radius:10px}table{width:100%;border-collapse:collapse;min-width:1120px;background:#101923}td,th{text-align:left;vertical-align:top;border-bottom:1px solid #283b50;padding:9px}th{background:#192737;color:#d6e8f7;position:sticky;top:0}tr:hover td{background:#152333}.ok{color:var(--green);font-weight:800}.warn{color:var(--amber);font-weight:800}.bad{color:var(--red);font-weight:800}.info{color:var(--cyan);font-weight:800}.muted{color:var(--muted)}.small{font-size:.86rem}.mono,code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace}code{background:#091018;padding:2px 5px;border-radius:4px}.badge{display:inline-block;padding:3px 8px;border-radius:999px;border:1px solid #46627e;font-size:.74rem;font-weight:850}.badge.ok{background:#143625}.badge.warn{background:#35270f}.badge.bad{background:#471c24}.badge.info{background:#103142}.filters,.actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.filters>*{width:auto;min-width:145px}.actions form{margin:0}.actions button{width:auto}input,select,textarea,button{padding:9px 10px;background:#142333;color:#fff;border:1px solid #46627e;border-radius:7px}textarea{width:100%;min-height:85px}button{font-weight:750;cursor:pointer}.timeline{display:grid;gap:8px}.event{display:grid;grid-template-columns:155px 175px 1fr;gap:10px;padding:11px;background:#101a25;border:1px solid #293e53;border-radius:9px}.notice,.warning,.error{padding:11px 13px;margin:9px 0;border-radius:8px}.notice{background:#143625;border:1px solid #3b8e65;color:#c1f6d7}.warning{background:#35270f;border:1px solid #93712d;color:#ffe3a6}.error{background:#471c24;border:1px solid #a94352;color:#ffd0d5}@media(max-width:800px){body{padding:10px}.panel{padding:11px}.two{grid-template-columns:1fr}.event{grid-template-columns:1fr}.filters>*{width:100%}}
"""


def _e(value: Any) -> str:
    return html.escape("" if value is None else str(value))


def _connect(database_path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(database_path, timeout=30)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys=ON")
    return connection


def _time(value: Any) -> str:
    try:
        stamp = int(value or 0)
    except (TypeError, ValueError):
        return "-"
    if stamp <= 0:
        return "-"
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(stamp))


def _age(value: Any) -> str:
    try:
        seconds = max(0, int(time.time()) - int(value or 0))
    except (TypeError, ValueError):
        return "unknown"
    if seconds < 120:
        return f"{seconds}s"
    if seconds < 7200:
        return f"{seconds // 60}m"
    if seconds < 172800:
        return f"{seconds // 3600}h"
    return f"{seconds // 86400}d"


def _short(value: Any, start: int = 8, end: int = 5) -> str:
    text = str(value or "")
    if len(text) <= start + end + 2:
        return text
    return f"{text[:start]}…{text[-end:]}"


def _state(last_seen: int) -> tuple[str, str]:
    age = max(0, int(time.time()) - int(last_seen or 0))
    if age < 7 * 86400:
        return "ACTIVE", "ok"
    if age < 30 * 86400:
        return "INACTIVE 7D", "warn"
    if age < 60 * 86400:
        return "INACTIVE 30D", "warn"
    if age < 90 * 86400:
        return "INACTIVE 60D", "bad"
    return "POSSIBLY UNINSTALLED", "bad"


def _safe_json(value: Any) -> dict[str, Any]:
    try:
        parsed = json.loads(str(value or "{}"))
        return parsed if isinstance(parsed, dict) else {}
    except (ValueError, TypeError, json.JSONDecodeError):
        return {}


def _page(title: str, body: str) -> str:
    nav = (
        "<div class='topbar'><div><h1>DriveLab Owner Console</h1>"
        f"<div class='muted'>Device Lifecycle Intelligence v{OWNER_LIFECYCLE_VERSION}</div></div>"
        "<div class='nav'><a href='/'>Dashboard</a><a href='/owner/control-center'>Control Center</a>"
        "<a href='/owner/lifecycle'>Lifecycle</a><a href='/owner/activity'>Activity</a>"
        "<a href='/owner/customers'>Customers</a><a href='/owner/devices'>Devices</a>"
        "<a href='/owner/operations'>Operations</a><a href='/logout'>Sign out</a></div></div>"
    )
    return (
        "<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{_e(title)} - DriveLab</title><style>{STYLE}</style></head><body>{nav}{body}</body></html>"
    )


def _device_rows(connection: sqlite3.Connection) -> list[dict[str, Any]]:
    rows = connection.execute(
        "SELECT p.*,"
        "(SELECT customer_email FROM licenses l WHERE l.id=p.current_license_id) customer_email,"
        "(SELECT COUNT(*) FROM device_presence d WHERE d.device_key_hash<>'' AND d.device_key_hash=p.device_key_hash) same_key_count,"
        "(SELECT COUNT(*) FROM device_relationships r WHERE r.source_installation_id=p.installation_id OR r.target_installation_id=p.installation_id) relationship_count,"
        "(SELECT COUNT(*) FROM device_lifecycle_events e WHERE e.installation_id=p.installation_id) event_count,"
        "(SELECT COUNT(*) FROM device_diagnostic_reports d WHERE d.installation_id=p.installation_id AND d.status IN ('new','investigating')) open_diagnostics "
        "FROM device_presence p ORDER BY p.last_seen_at DESC"
    ).fetchall()
    values: list[dict[str, Any]] = []
    for row in rows:
        item = dict(row)
        anomalies: list[str] = []
        if int(item.get("same_key_count") or 0) > 1:
            anomalies.append("shared device key")
        if str(item.get("previous_app_version") or "") and str(item.get("previous_app_version")) > str(item.get("app_version") or ""):
            anomalies.append("possible downgrade")
        license_id = str(item.get("current_license_id") or "")
        if license_id:
            license_row = connection.execute(
                "SELECT device_limit,(SELECT COUNT(*) FROM activations a WHERE a.license_id=l.id AND a.status='active') active_count FROM licenses l WHERE id=?",
                (license_id,),
            ).fetchone()
            if license_row is not None and int(license_row["active_count"] or 0) > int(license_row["device_limit"] or 0):
                anomalies.append("license over device limit")
        item["anomalies"] = anomalies
        values.append(item)
    return values


def _summary(connection: sqlite3.Connection) -> dict[str, int]:
    now = int(time.time())
    row = connection.execute(
        "SELECT COUNT(*) total,"
        "SUM(CASE WHEN last_seen_at>=? THEN 1 ELSE 0 END) active_7d,"
        "SUM(CASE WHEN last_seen_at<? AND last_seen_at>=? THEN 1 ELSE 0 END) inactive_7_30,"
        "SUM(CASE WHEN last_seen_at<? AND last_seen_at>=? THEN 1 ELSE 0 END) inactive_30_60,"
        "SUM(CASE WHEN last_seen_at<? AND last_seen_at>=? THEN 1 ELSE 0 END) inactive_60_90,"
        "SUM(CASE WHEN last_seen_at<? THEN 1 ELSE 0 END) possible_uninstalled,"
        "SUM(CASE WHEN edition='full' THEN 1 ELSE 0 END) full_count,"
        "SUM(CASE WHEN edition='free' THEN 1 ELSE 0 END) free_count,"
        "SUM(CASE WHEN first_seen_at>=? THEN 1 ELSE 0 END) new_7d "
        "FROM device_presence",
        (
            now - 7 * 86400,
            now - 7 * 86400,
            now - 30 * 86400,
            now - 30 * 86400,
            now - 60 * 86400,
            now - 60 * 86400,
            now - 90 * 86400,
            now - 90 * 86400,
            now - 7 * 86400,
        ),
    ).fetchone()
    diagnostics = connection.execute(
        "SELECT COUNT(*) FROM device_diagnostic_reports WHERE status IN ('new','investigating')"
    ).fetchone()[0]
    today = time.strftime("%Y-%m-%d", time.gmtime())
    active_today = connection.execute(
        "SELECT COUNT(*) FROM device_active_days WHERE active_date=?",
        (today,),
    ).fetchone()[0]
    return {
        key: int(row[key] or 0)
        for key in row.keys()
    } | {"open_diagnostics": int(diagnostics or 0), "active_today": int(active_today or 0)}


def install_owner_lifecycle(
    app: Any,
    settings: Any,
    db: Any,
    authenticated: Any,
    require_csrf: Any,
) -> None:
    database_path = Path(settings.database_path)
    ensure_lifecycle_schema(database_path)

    @app.get("/owner/lifecycle", response_class=HTMLResponse)
    def lifecycle_overview(
        q: str = Query(default=""),
        state: str = Query(default="all"),
        edition: str = Query(default="all"),
        version: str = Query(default="all"),
        notice: str = Query(default=""),
        dlt_admin: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        if not authenticated(dlt_admin, authorization):
            return RedirectResponse(url="/login", status_code=303)
        with _connect(database_path) as connection:
            rows = _device_rows(connection)
            summary = _summary(connection)
            versions = sorted({str(row.get("app_version") or "(unknown)") for row in rows})
        query = q.strip().lower()
        filtered: list[dict[str, Any]] = []
        for row in rows:
            status, _class = _state(int(row.get("last_seen_at") or 0))
            row["lifecycle_state"] = status
            haystack = " ".join(
                str(row.get(key) or "")
                for key in ("installation_id", "app_version", "edition", "current_license_id", "customer_email")
            ).lower()
            if query and query not in haystack:
                continue
            if edition != "all" and str(row.get("edition") or "free") != edition:
                continue
            if version != "all" and str(row.get("app_version") or "(unknown)") != version:
                continue
            state_key = status.lower().replace(" ", "_")
            if state != "all" and state != state_key:
                continue
            filtered.append(row)

        body: list[str] = []
        if notice:
            body.append(f"<div class='notice'>{_e(notice)}</div>")
        body.append(
            "<div class='panel'><h2>Device lifecycle intelligence</h2>"
            "<p class='muted'>Installation identity, activity, versions, Free/Full conversion, connection outcomes, crash-free app sessions, feature use, optional drive summaries, diagnostics, and replacement relationships. Raw gameplay streams and location are not collected.</p></div>"
        )
        cards = [
            (summary["total"], "known installations"),
            (summary["active_today"], "active today"),
            (summary["active_7d"], "active in 7 days"),
            (summary["new_7d"], "new in 7 days"),
            (summary["inactive_7_30"], "inactive 7–30 days"),
            (summary["inactive_30_60"], "inactive 30–60 days"),
            (summary["inactive_60_90"], "inactive 60–90 days"),
            (summary["possible_uninstalled"], "possibly uninstalled"),
            (summary["full_count"], "Full installations"),
            (summary["free_count"], "Free installations"),
            (summary["open_diagnostics"], "open diagnostics"),
        ]
        body.append("<div class='grid'>")
        for value, label in cards:
            body.append(f"<div class='card'><strong>{value}</strong><span>{_e(label)}</span></div>")
        body.append("</div>")
        body.append(
            "<form class='panel filters' method='get'><input name='q' value='" + _e(q) + "' placeholder='Installation, license, email or version'>"
            "<select name='state'>" + "".join(
                f"<option value='{key}'{' selected' if state == key else ''}>{_e(label)}</option>"
                for key, label in (
                    ("all", "All states"),
                    ("active", "Active under 7 days"),
                    ("inactive_7d", "Inactive 7–30 days"),
                    ("inactive_30d", "Inactive 30–60 days"),
                    ("inactive_60d", "Inactive 60–90 days"),
                    ("possibly_uninstalled", "Possibly uninstalled"),
                )
            ) + "</select><select name='edition'>" + "".join(
                f"<option value='{key}'{' selected' if edition == key else ''}>{label}</option>"
                for key, label in (("all", "All editions"), ("free", "Free"), ("full", "Full"))
            ) + "</select><select name='version'>" + "".join(
                [f"<option value='all'{' selected' if version == 'all' else ''}>All versions</option>"]
                + [f"<option value='{_e(item)}'{' selected' if version == item else ''}>{_e(item)}</option>" for item in versions]
            ) + "</select><button>FILTER</button></form>"
        )
        body.append("<div class='panel'><h2>Installations</h2><div class='table-wrap'><table><thead><tr><th>Installation</th><th>State</th><th>Edition / license</th><th>Version</th><th>Activity</th><th>Reliability</th><th>Connection</th><th>Signals</th></tr></thead><tbody>")
        for row in filtered:
            status, status_class = _state(int(row.get("last_seen_at") or 0))
            installation_id = str(row.get("installation_id") or "")
            anomalies = list(row.get("anomalies") or [])
            signals = []
            if anomalies:
                signals.extend(anomalies)
            if int(row.get("open_diagnostics") or 0):
                signals.append(f"{int(row['open_diagnostics'])} open diagnostic")
            body.append(
                f"<tr><td><a class='mono' href='/owner/lifecycle/{quote(installation_id)}'>{_e(_short(installation_id))}</a><br><span class='small muted'>first {_e(_time(row.get('first_seen_at')))}</span></td>"
                f"<td><span class='badge {status_class}'>{_e(status)}</span><br><span class='small muted'>seen {_e(_age(row.get('last_seen_at')))} ago</span></td>"
                f"<td><strong>{_e(str(row.get('edition') or 'free').upper())}</strong><br><span class='mono small'>{_e(_short(row.get('current_license_id')) or 'unlicensed')}</span><br><span class='small muted'>{_e(row.get('customer_email'))}</span></td>"
                f"<td><strong>{_e(row.get('app_version') or '(unknown)')}</strong><br><span class='small muted'>first { _e(row.get('first_app_version') or '(unknown)') }</span></td>"
                f"<td>{int(row.get('launch_count') or 0)} launches<br>{int(row.get('active_days') or 0)} active days<br><span class='small muted'>{int(row.get('event_count') or 0)} events</span></td>"
                f"<td><span class='ok'>{int(row.get('clean_sessions') or 0)} clean</span><br><span class='{'bad' if int(row.get('unclean_sessions') or 0) else 'muted'}'>{int(row.get('unclean_sessions') or 0)} unclean</span></td>"
                f"<td>{_e(row.get('last_connection_status') or 'no report')}<br><span class='small muted'>{_e(_time(row.get('last_connection_at')))}</span></td>"
                f"<td class='small'>{_e(', '.join(signals) if signals else 'normal')}<br>{int(row.get('relationship_count') or 0)} relationship(s)</td></tr>"
            )
        if not filtered:
            body.append("<tr><td colspan='8' class='muted'>No installations match the selected filters.</td></tr>")
        body.append("</tbody></table></div></div>")
        return HTMLResponse(_page("Lifecycle", "".join(body)))

    @app.get("/owner/lifecycle/{installation_id}", response_class=HTMLResponse)
    def lifecycle_device(
        installation_id: str,
        notice: str = Query(default=""),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        if not authenticated(dlt_admin, authorization):
            return RedirectResponse(url="/login", status_code=303)
        installation_id = installation_id.strip()
        csrf = dlt_csrf or __import__("secrets").token_urlsafe(32)
        with _connect(database_path) as connection:
            row = connection.execute(
                "SELECT p.*,(SELECT customer_email FROM licenses l WHERE l.id=p.current_license_id) customer_email FROM device_presence p WHERE installation_id=?",
                (installation_id,),
            ).fetchone()
            if row is None:
                raise HTTPException(status_code=404, detail="Installation not found")
            events = connection.execute(
                "SELECT * FROM device_lifecycle_events WHERE installation_id=? ORDER BY occurred_at DESC,id DESC LIMIT 500",
                (installation_id,),
            ).fetchall()
            days = connection.execute(
                "SELECT * FROM device_active_days WHERE installation_id=? ORDER BY active_date DESC LIMIT 120",
                (installation_id,),
            ).fetchall()
            versions = connection.execute(
                "SELECT * FROM device_version_history WHERE installation_id=? ORDER BY first_seen_at DESC",
                (installation_id,),
            ).fetchall()
            editions = connection.execute(
                "SELECT * FROM device_edition_history WHERE installation_id=? ORDER BY first_seen_at DESC",
                (installation_id,),
            ).fetchall()
            relationships = connection.execute(
                "SELECT * FROM device_relationships WHERE source_installation_id=? OR target_installation_id=? ORDER BY updated_at DESC",
                (installation_id, installation_id),
            ).fetchall()
            diagnostics = connection.execute(
                "SELECT * FROM device_diagnostic_reports WHERE installation_id=? ORDER BY received_at DESC",
                (installation_id,),
            ).fetchall()
        item = dict(row)
        status, status_class = _state(int(item.get("last_seen_at") or 0))
        total_app_sessions = int(item.get("clean_sessions") or 0) + int(item.get("unclean_sessions") or 0)
        crash_free = round(int(item.get("clean_sessions") or 0) / total_app_sessions * 100, 1) if total_app_sessions else 100.0

        body: list[str] = []
        if notice:
            body.append(f"<div class='notice'>{_e(notice)}</div>")
        body.append(
            f"<div class='panel'><h2>Installation <span class='mono'>{_e(installation_id)}</span></h2>"
            f"<p><span class='badge {status_class}'>{_e(status)}</span> · {_e(str(item.get('edition') or 'free').upper())} · version {_e(item.get('app_version') or '(unknown)')}</p>"
            f"<p class='muted'>First seen {_e(_time(item.get('first_seen_at')))} · last seen {_e(_time(item.get('last_seen_at')))} · license {_e(item.get('current_license_id') or 'none')} · {_e(item.get('customer_email') or '')}</p></div>"
        )
        cards = [
            (item.get("launch_count", 0), "app launches"),
            (item.get("active_days", 0), "active days"),
            (f"{crash_free:.1f}%", "crash-free app sessions"),
            (item.get("feature_open_count", 0), "feature opens"),
            (item.get("feature_complete_count", 0), "feature completions"),
            (item.get("session_summary_count", 0), "optional drive summaries"),
            (item.get("diagnostic_count", 0), "diagnostic reports"),
            (item.get("last_connection_status") or "none", "last BeamNG result"),
        ]
        body.append("<div class='grid'>")
        for value, label in cards:
            body.append(f"<div class='card'><strong>{_e(value)}</strong><span>{_e(label)}</span></div>")
        body.append("</div>")

        body.append("<div class='two'><div class='panel'><h2>Version history</h2><div class='table-wrap'><table><thead><tr><th>Version</th><th>First</th><th>Last</th><th>Launches</th></tr></thead><tbody>")
        for version_row in versions:
            body.append(f"<tr><td>{_e(version_row['app_version'])}</td><td>{_e(_time(version_row['first_seen_at']))}</td><td>{_e(_time(version_row['last_seen_at']))}</td><td>{int(version_row['launch_count'] or 0)}</td></tr>")
        body.append("</tbody></table></div></div><div class='panel'><h2>Free / Full history</h2><div class='table-wrap'><table><thead><tr><th>Edition</th><th>License</th><th>First</th><th>Last</th></tr></thead><tbody>")
        for edition_row in editions:
            body.append(f"<tr><td>{_e(str(edition_row['edition']).upper())}</td><td class='mono'>{_e(_short(edition_row['license_id']) or 'none')}</td><td>{_e(_time(edition_row['first_seen_at']))}</td><td>{_e(_time(edition_row['last_seen_at']))}</td></tr>")
        body.append("</tbody></table></div></div></div>")

        body.append("<div class='panel'><h2>Device replacement relationships</h2><div class='actions'>")
        body.append(
            f"<form method='post' action='/owner/lifecycle/relationship'><input type='hidden' name='csrf_token' value='{_e(csrf)}'><input type='hidden' name='source_installation_id' value='{_e(installation_id)}'>"
            "<input name='target_installation_id' placeholder='Replacement installation ID' required>"
            "<select name='relationship_type'><option value='replacement'>Replaced by</option><option value='same_owner'>Same owner</option><option value='duplicate'>Duplicate</option><option value='test_device'>Test device</option></select>"
            "<input name='note' placeholder='Owner note'><button>ADD RELATIONSHIP</button></form>"
        )
        body.append("</div><div class='table-wrap'><table><thead><tr><th>Type</th><th>Source</th><th>Target</th><th>Note</th><th>Updated</th></tr></thead><tbody>")
        for rel in relationships:
            body.append(f"<tr><td>{_e(rel['relationship_type'])}</td><td class='mono'>{_e(_short(rel['source_installation_id']))}</td><td class='mono'>{_e(_short(rel['target_installation_id']))}</td><td>{_e(rel['note'])}</td><td>{_e(_time(rel['updated_at']))}</td></tr>")
        if not relationships:
            body.append("<tr><td colspan='5' class='muted'>No replacement or duplicate relationships recorded.</td></tr>")
        body.append("</tbody></table></div></div>")

        body.append("<div class='panel'><h2>Diagnostic reports</h2><div class='table-wrap'><table><thead><tr><th>Time</th><th>Status</th><th>Summary</th><th>Sanitized details</th><th>Owner update</th></tr></thead><tbody>")
        for report in diagnostics:
            payload = _safe_json(report["payload_json"])
            body.append(
                f"<tr><td>{_e(_time(report['received_at']))}</td><td><span class='badge {'ok' if report['status']=='resolved' else 'warn'}'>{_e(report['status'])}</span></td>"
                f"<td>{_e(report['summary'])}</td><td class='small mono'>{_e(json.dumps(payload, sort_keys=True)[:1200])}</td>"
                f"<td><form method='post' action='/owner/lifecycle/diagnostic'><input type='hidden' name='csrf_token' value='{_e(csrf)}'><input type='hidden' name='report_id' value='{_e(report['report_id'])}'>"
                f"<select name='status'><option value='new'{' selected' if report['status']=='new' else ''}>New</option><option value='investigating'{' selected' if report['status']=='investigating' else ''}>Investigating</option><option value='resolved'{' selected' if report['status']=='resolved' else ''}>Resolved</option></select>"
                f"<input name='owner_note' value='{_e(report['owner_note'])}' placeholder='Owner note'><button>SAVE</button></form></td></tr>"
            )
        if not diagnostics:
            body.append("<tr><td colspan='5' class='muted'>No user-triggered diagnostic reports.</td></tr>")
        body.append("</tbody></table></div></div>")

        body.append("<div class='panel'><h2>Active-day history</h2><div class='table-wrap'><table><thead><tr><th>Date</th><th>Launches</th><th>Foregrounds</th><th>Connections</th><th>Failures</th><th>Clean / unclean</th><th>Feature open / complete</th><th>Drive summaries</th></tr></thead><tbody>")
        for day_row in days:
            body.append(f"<tr><td>{_e(day_row['active_date'])}</td><td>{int(day_row['launch_count'])}</td><td>{int(day_row['foreground_count'])}</td><td>{int(day_row['connection_successes'])}</td><td>{int(day_row['connection_failures'])}</td><td>{int(day_row['clean_sessions'])} / {int(day_row['unclean_sessions'])}</td><td>{int(day_row['feature_opens'])} / {int(day_row['feature_completions'])}</td><td>{int(day_row['drive_summaries'])}</td></tr>")
        body.append("</tbody></table></div></div>")

        body.append("<div class='panel'><h2>Lifecycle timeline</h2><div class='timeline'>")
        for event in events:
            props = _safe_json(event["properties_json"])
            body.append(
                f"<div class='event'><div>{_e(_time(event['occurred_at']))}<br><span class='small muted'>{_e(_age(event['occurred_at']))} ago</span></div>"
                f"<div><strong>{_e(event['event_type'])}</strong><br><span class='small muted'>{_e(event['app_version'])} · {_e(str(event['edition']).upper())}</span></div>"
                f"<div class='small mono'>{_e(json.dumps(props, sort_keys=True))}</div></div>"
            )
        if not events:
            body.append("<div class='muted'>No lifecycle events have arrived from this installation.</div>")
        body.append("</div></div>")
        response = HTMLResponse(_page("Installation lifecycle", "".join(body)))
        if not dlt_csrf:
            response.set_cookie("dlt_csrf", csrf, httponly=True, samesite="strict", max_age=8 * 60 * 60)
        return response

    @app.post("/owner/lifecycle/relationship")
    def lifecycle_relationship(
        source_installation_id: str = Form(...),
        target_installation_id: str = Form(...),
        relationship_type: str = Form(default="replacement"),
        note: str = Form(default=""),
        csrf_token: str = Form(...),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        if not authenticated(dlt_admin, authorization):
            raise HTTPException(status_code=401, detail="Admin authentication required")
        require_csrf(csrf_token, dlt_csrf)
        source = source_installation_id.strip()
        target = target_installation_id.strip()
        relationship = relationship_type.strip().lower()
        if relationship not in {"replacement", "same_owner", "duplicate", "test_device"}:
            raise HTTPException(status_code=422, detail="Invalid relationship type")
        if source == target:
            raise HTTPException(status_code=422, detail="A device cannot be related to itself")
        now = int(time.time())
        with _connect(database_path) as connection:
            for installation_id in (source, target):
                if connection.execute("SELECT 1 FROM device_presence WHERE installation_id=?", (installation_id,)).fetchone() is None:
                    raise HTTPException(status_code=404, detail=f"Installation not found: {installation_id}")
            connection.execute(
                "INSERT INTO device_relationships(source_installation_id,target_installation_id,relationship_type,note,created_at,updated_at) "
                "VALUES(?,?,?,?,?,?) ON CONFLICT(source_installation_id,target_installation_id,relationship_type) DO UPDATE SET note=excluded.note,updated_at=excluded.updated_at",
                (source, target, relationship, note.strip()[:1000], now, now),
            )
            connection.commit()
        return RedirectResponse(url=f"/owner/lifecycle/{quote(source)}?notice={quote('Device relationship saved.')}", status_code=303)

    @app.post("/owner/lifecycle/diagnostic")
    def lifecycle_diagnostic(
        report_id: str = Form(...),
        status: str = Form(default="new"),
        owner_note: str = Form(default=""),
        csrf_token: str = Form(...),
        dlt_admin: str | None = Cookie(default=None),
        dlt_csrf: str | None = Cookie(default=None),
        authorization: str | None = Header(default=None),
    ):
        if not authenticated(dlt_admin, authorization):
            raise HTTPException(status_code=401, detail="Admin authentication required")
        require_csrf(csrf_token, dlt_csrf)
        status = status.strip().lower()
        if status not in {"new", "investigating", "resolved"}:
            raise HTTPException(status_code=422, detail="Invalid diagnostic status")
        with _connect(database_path) as connection:
            report = connection.execute(
                "SELECT installation_id FROM device_diagnostic_reports WHERE report_id=?",
                (report_id.strip(),),
            ).fetchone()
            if report is None:
                raise HTTPException(status_code=404, detail="Diagnostic report not found")
            connection.execute(
                "UPDATE device_diagnostic_reports SET status=?,owner_note=? WHERE report_id=?",
                (status, owner_note.strip()[:4000], report_id.strip()),
            )
            connection.commit()
        installation_id = str(report["installation_id"])
        return RedirectResponse(url=f"/owner/lifecycle/{quote(installation_id)}?notice={quote('Diagnostic report updated.')}", status_code=303)
