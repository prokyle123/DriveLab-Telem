#!/usr/bin/env python3
from __future__ import annotations

import ast
import shutil
import sys
from pathlib import Path


API_MARKER = "# DriveLab Lifecycle Intelligence API v1.0.0"
ADMIN_MARKER = "# DriveLab Owner Lifecycle Intelligence v1.0.0"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor but found {count}.")
    return text.replace(old, new, 1)


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: patch_stage.py STAGE_ROOT PAYLOAD_ROOT")
    stage = Path(sys.argv[1]).resolve()
    payload = Path(sys.argv[2]).resolve()
    package = stage / "drivelab_license"
    tests = stage / "tests"

    required = [
        package / "main.py",
        package / "admin_app.py",
        package / "owner_control_center.py",
        payload / "lifecycle.py",
        payload / "owner_lifecycle.py",
        payload / "test_lifecycle.py",
    ]
    for path in required:
        if not path.is_file():
            raise SystemExit(f"Required staging input is missing: {path}")

    main_path = package / "main.py"
    admin_path = package / "admin_app.py"
    control_path = package / "owner_control_center.py"

    main_text = read(main_path)
    if API_MARKER in main_text:
        raise SystemExit("Lifecycle API marker is already present in staged main.py.")
    main_anchor = (
        "@app.get(\"/v1/update/latest\", response_model=UpdateBundle)\n"
        "def latest_update():\n"
        "    result = updates.latest()\n"
        "    return UpdateBundle(payload=result.payload, signature=result.signature, algorithm=result.algorithm)\n"
    )
    main_replacement = main_anchor + (
        "\n\n"
        f"{API_MARKER}\n"
        "from .lifecycle import install_lifecycle_api as _install_lifecycle_api_v1\n\n"
        "_install_lifecycle_api_v1(app, settings, service)\n"
        "# DriveLab Lifecycle Intelligence API v1.0.0 END\n"
    )
    main_text = replace_once(main_text, main_anchor, main_replacement, "main.py lifecycle API")

    admin_text = read(admin_path)
    if ADMIN_MARKER in admin_text:
        raise SystemExit("Owner lifecycle marker is already present in staged admin_app.py.")
    admin_anchor = (
        "# DriveLab Owner Control Center v3.0.0\n"
        "from .owner_control_center import install_owner_control_center\n\n"
        "install_owner_control_center(\n"
        "    app,\n"
        "    settings,\n"
        "    db,\n"
        "    authenticated,\n"
        "    require_auth,\n"
        "    require_csrf,\n"
        ")\n"
    )
    admin_replacement = admin_anchor + (
        "\n\n"
        f"{ADMIN_MARKER}\n"
        "from .owner_lifecycle import install_owner_lifecycle\n\n"
        "install_owner_lifecycle(\n"
        "    app,\n"
        "    settings,\n"
        "    db,\n"
        "    authenticated,\n"
        "    require_csrf,\n"
        ")\n"
        "# DriveLab Owner Lifecycle Intelligence v1.0.0 END\n"
    )
    admin_text = replace_once(admin_text, admin_anchor, admin_replacement, "admin_app.py lifecycle owner page")

    control_text = read(control_path)
    control_text = replace_once(
        control_text,
        'CONTROL_CENTER_VERSION = "3.0.0"',
        'CONTROL_CENTER_VERSION = "3.1.0"',
        "owner_control_center.py version",
    )
    control_text = replace_once(
        control_text,
        '"<a href=\'/owner/devices\'>Devices</a>"',
        '"<a href=\'/owner/devices\'>Devices</a>"\n        "<a href=\'/owner/lifecycle\'>Lifecycle</a>"',
        "owner_control_center.py navigation",
    )
    control_text = replace_once(
        control_text,
        "Control Center v{CONTROL_CENTER_VERSION} · licensing, releases, operations, customers, and recovery",
        "Control Center v{CONTROL_CENTER_VERSION} · licensing, lifecycle, releases, operations, customers, and recovery",
        "owner_control_center.py subtitle",
    )

    write(main_path, main_text)
    write(admin_path, admin_text)
    write(control_path, control_text)
    shutil.copy2(payload / "lifecycle.py", package / "lifecycle.py")
    shutil.copy2(payload / "owner_lifecycle.py", package / "owner_lifecycle.py")
    tests.mkdir(parents=True, exist_ok=True)
    shutil.copy2(payload / "test_lifecycle.py", tests / "test_lifecycle.py")

    for path in (
        main_path,
        admin_path,
        control_path,
        package / "lifecycle.py",
        package / "owner_lifecycle.py",
        tests / "test_lifecycle.py",
    ):
        ast.parse(read(path), filename=str(path))

    print("Lifecycle server patch completed and parsed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
