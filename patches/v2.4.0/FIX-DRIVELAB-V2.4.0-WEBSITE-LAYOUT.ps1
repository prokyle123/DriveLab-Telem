$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ServiceName = "drivelab-site.service"
$SitePort = 8790
$Target = Read-Host "Pi SSH target [kali@ak47]"

if ([string]::IsNullOrWhiteSpace($Target)) {
    $Target = "kali@ak47"
}

$Ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
$Scp = Get-Command scp.exe -ErrorAction SilentlyContinue

if (-not $Ssh -or -not $Scp) {
    throw "Windows OpenSSH ssh.exe and scp.exe are required."
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LocalScript = Join-Path $env:TEMP "fix-drivelab-v2.4.0-website-layout-$Timestamp.py"
$RemoteScript = "/tmp/fix-drivelab-v2.4.0-website-layout-$Timestamp.py"
$Utf8Write = [System.Text.UTF8Encoding]::new($false)

$Python = @'
from pathlib import Path
from datetime import datetime
from html import escape
import re
import shutil
import subprocess
import sys
import time
import urllib.request

SITE_ROOT = Path("/opt/drivelab-site")
SERVICE = "drivelab-site.service"
HEALTH_URL = "http://127.0.0.1:8790/healthz"

START = "<!-- DRIVELAB DRIVE INTELLIGENCE START -->"
END = "<!-- DRIVELAB DRIVE INTELLIGENCE END -->"
CSS_START = "/* DRIVELAB DRIVE INTELLIGENCE CSS START */"
CSS_END = "/* DRIVELAB DRIVE INTELLIGENCE CSS END */"

CAPTIONS = {
    "01-drive-intelligence-settings.png": (
        "Drive Intelligence settings",
        "Control stunt detection, event popups, spoken announcements, Driver DNA, Drive Stories, and detection sensitivity from one place."
    ),
    "02-stunt-maneuver-popup.png": (
        "Live maneuver detection",
        "Confirmed maneuvers can appear with vehicle speed, detection confidence, and earned XP."
    ),
    "03-driver-dna-available.png": (
        "Driver DNA remains optional",
        "The feature stays visible but completely inactive until the driver chooses to enable it."
    ),
    "04-driver-dna-profile.png": (
        "A profile that develops gradually",
        "When enabled, Driver DNA builds a private long-term profile from completed drives rather than one isolated run."
    ),
    "05-drive-story-session.png": (
        "Drive Stories in saved sessions",
        "Saved sessions can include a locally generated story, major moments, detected maneuvers, and important statistics."
    ),
    "06-drive-story-complete-dialog.png": (
        "Review and share the drive",
        "Completed drives can be reviewed immediately and exported as a clean Drive Story share card."
    ),
}

ALLOWED = {".png", ".jpg", ".jpeg", ".webp"}


def read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None


def choose_homepage():
    candidates = [
        SITE_ROOT / "templates" / "index.html",
        SITE_ROOT / "site" / "templates" / "index.html",
        SITE_ROOT / "app" / "templates" / "index.html",
        SITE_ROOT / "static" / "index.html",
        SITE_ROOT / "public" / "index.html",
        SITE_ROOT / "index.html",
    ]

    for candidate in candidates:
        if candidate.exists():
            text = read_text(candidate)
            if text and "drivelab" in text.lower():
                return candidate, text

    scored = []
    for candidate in SITE_ROOT.rglob("index.html"):
        if "/backups/" in str(candidate):
            continue
        text = read_text(candidate)
        if not text:
            continue
        lowered = text.lower()
        score = 0
        score += lowered.count("drivelab") * 8
        score += lowered.count("tracklab") * 4
        score += lowered.count("racelink") * 5
        score += 20 if START.lower() in lowered else 0
        score += 10 if "</body>" in lowered else 0
        scored.append((score, -len(str(candidate)), candidate, text))

    if not scored:
        raise SystemExit("Could not locate the DriveLab homepage.")

    scored.sort(reverse=True, key=lambda item: (item[0], item[1]))
    _, _, page, text = scored[0]
    return page, text


def remove_bad_injection(html):
    html = re.sub(
        r"(?is)\s*" + re.escape(START) + r".*?" + re.escape(END) + r"\s*",
        "\n",
        html,
    )
    html = re.sub(
        r"(?is)\s*" + re.escape(CSS_START) + r".*?" + re.escape(CSS_END) + r"\s*",
        "\n",
        html,
    )
    html = re.sub(
        r'''(?is)\s*<section\b[^>]*id\s*=\s*["']drive-intelligence["'][^>]*>.*?</section>\s*''',
        "\n",
        html,
    )
    return html


def newest_original_backup(page):
    backup_base = SITE_ROOT / "backups"
    if not backup_base.exists():
        return None

    candidates = []
    for folder in backup_base.glob("drive-intelligence-v2.4.0-*"):
        candidate = folder / page.name
        if not candidate.exists():
            continue
        text = read_text(candidate)
        if not text or "drivelab" not in text.lower():
            continue
        if START in text or CSS_START in text or 'id="drive-intelligence"' in text:
            continue
        candidates.append(candidate)

    if not candidates:
        return None

    return max(candidates, key=lambda item: item.stat().st_mtime)


def find_media():
    candidates = []
    for directory in SITE_ROOT.rglob("drive-intelligence"):
        if not directory.is_dir() or "/backups/" in str(directory):
            continue
        images = [
            item for item in directory.iterdir()
            if item.is_file() and item.suffix.lower() in ALLOWED
        ]
        if images:
            candidates.append((len(images), directory, images))

    if not candidates:
        raise SystemExit(
            "The Drive Intelligence screenshot directory was not found. "
            "The homepage was not changed."
        )

    candidates.sort(key=lambda item: item[0], reverse=True)
    _, directory, images = candidates[0]

    if directory.parent.name == "static":
        prefix = "/static/drive-intelligence"
    elif directory.parent.name == "assets":
        prefix = "/assets/drive-intelligence"
    elif directory.parent.name == "media":
        prefix = "/media/drive-intelligence"
    elif directory.parent.name == "public":
        prefix = "/public/drive-intelligence"
    else:
        prefix = "/static/drive-intelligence"

    return directory, prefix, sorted(images, key=lambda item: item.name.lower())


def visible_text(markup):
    return re.sub(
        r"\s+",
        " ",
        re.sub(r"(?is)<[^>]+>", " ", markup),
    ).strip().lower()


def section_blocks(html):
    return list(re.finditer(r"(?is)<section\b[^>]*>.*?</section>", html))


def insert_near_racelink(html, section):
    blocks = section_blocks(html)

    race_candidates = []
    for block in blocks:
        text = visible_text(block.group(0))
        if "racelink" in text or "race link" in text:
            race_candidates.append(block)

    if race_candidates:
        race_block = max(
            race_candidates,
            key=lambda block: len(block.group(0)),
        )
        return html[:race_block.start()] + section + "\n\n" + html[race_block.start():]

    track_candidates = []
    for block in blocks:
        text = visible_text(block.group(0))
        if "tracklab" in text or "auto co-driver" in text or "auto codriver" in text:
            track_candidates.append(block)

    if track_candidates:
        track_block = track_candidates[-1]
        return html[:track_block.end()] + "\n\n" + section + html[track_block.end():]

    lowered = html.lower()
    for closing in ("</main>", "</body>"):
        position = lowered.rfind(closing)
        if position >= 0:
            return html[:position] + section + "\n" + html[position:]

    raise SystemExit(
        "Could not locate a safe TrackLab/RaceLink insertion point. "
        "The homepage was not changed."
    )


def restart_and_check():
    subprocess.run(
        ["systemctl", "restart", SERVICE],
        check=True,
    )
    time.sleep(3)
    with urllib.request.urlopen(HEALTH_URL, timeout=10) as response:
        payload = response.read().decode("utf-8", errors="replace")
        if response.status != 200:
            raise RuntimeError(f"Health check returned HTTP {response.status}")
        return payload.strip()


if not SITE_ROOT.exists():
    raise SystemExit(f"Website root was not found: {SITE_ROOT}")

page, broken_html = choose_homepage()
original_backup = newest_original_backup(page)

if original_backup is None:
    raise SystemExit(
        "The untouched pre-Drive-Intelligence homepage backup was not found. "
        "Nothing was changed."
    )

restored_html = read_text(original_backup)
if not restored_html:
    raise SystemExit("The original homepage backup could not be read.")

restored_html = remove_bad_injection(restored_html)
media_root, media_prefix, image_files = find_media()

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
emergency_root = SITE_ROOT / "backups" / f"before-drive-intelligence-layout-repair-{stamp}"
emergency_root.mkdir(parents=True, exist_ok=True)
emergency_page = emergency_root / page.name
shutil.copy2(page, emergency_page)

cards = [
    (
        "Full stunt detection",
        "Recognizes donuts, burnouts, J-turns, reverse 180s, drift transitions, jumps, flips, two-wheel driving, wheelies, stoppies, hard landings, and major recoveries from BeamNG telemetry."
    ),
    (
        "Optional Driver DNA",
        "Builds a slow-changing private driving profile across twelve traits. Driver DNA starts disabled and stays out of the normal app until the driver enables it."
    ),
    (
        "Drive Stories",
        "Turns completed sessions into readable stories with major moments, detected maneuvers, difficult moments, and shareable cards generated locally on the phone."
    ),
]

feature_cards = "\n".join(
    f'''<article style="padding:22px;border:1px solid rgba(255,255,255,.09);border-radius:20px;background:linear-gradient(145deg,rgba(20,31,45,.96),rgba(11,19,30,.98));box-shadow:0 18px 42px rgba(0,0,0,.20);">
        <div style="color:rgba(0,216,255,.60);font-size:.78rem;font-weight:900;letter-spacing:.16em;">0{index}</div>
        <h3 style="margin:24px 0 10px;color:#fff;font-size:1.25rem;">{escape(title)}</h3>
        <p style="margin:0;color:#a8b5c8;line-height:1.65;">{escape(body)}</p>
    </article>'''
    for index, (title, body) in enumerate(cards, start=1)
)

gallery_items = []
for number, image in enumerate(image_files, start=1):
    title, caption = CAPTIONS.get(
        image.name.lower(),
        (
            f"Drive Intelligence screen {number}",
            "A real screen captured from the working DriveLab Telem 2.4.0 Android build."
        ),
    )
    image_url = f"{media_prefix}/{escape(image.name)}"
    gallery_items.append(
        f'''<figure style="margin:0;overflow:hidden;border:1px solid rgba(255,255,255,.09);border-radius:20px;background:#111722;box-shadow:0 18px 44px rgba(0,0,0,.24);">
            <a href="{image_url}" target="_blank" rel="noopener" style="display:block;background:#080c14;text-decoration:none;">
                <img src="{image_url}" alt="{escape(title)} in DriveLab Telem 2.4.0" loading="lazy" decoding="async" style="display:block;width:100%;height:auto;max-height:680px;object-fit:contain;background:#080c14;">
            </a>
            <figcaption style="display:grid;gap:7px;padding:16px 17px 18px;">
                <strong style="color:#fff;font-size:.98rem;">{escape(title)}</strong>
                <span style="color:#9eacc0;font-size:.88rem;line-height:1.55;">{escape(caption)}</span>
            </figcaption>
        </figure>'''
    )

gallery = "\n".join(gallery_items)

section = f'''
{START}
<section id="drive-intelligence" aria-labelledby="drive-intelligence-title" style="position:relative;padding:clamp(64px,8vw,100px) 18px;overflow:hidden;color:#fff;background:radial-gradient(circle at 12% 8%,rgba(0,216,255,.11),transparent 32%),linear-gradient(180deg,#07111d,#091522);border-top:1px solid rgba(255,255,255,.06);border-bottom:1px solid rgba(255,255,255,.06);">
    <div style="width:min(1180px,100%);margin:0 auto;">
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:clamp(24px,5vw,56px);align-items:center;">
            <div>
                <div style="color:#00d8ff;font-size:.78rem;font-weight:900;letter-spacing:.16em;text-transform:uppercase;">NEW IN DRIVELAB TELEM 2.4.0</div>
                <h2 id="drive-intelligence-title" style="margin:10px 0 16px;color:#fff;font-size:clamp(2.2rem,6vw,4.5rem);line-height:1;letter-spacing:-.04em;">Drive Intelligence</h2>
                <p style="max-width:760px;margin:0;color:#aab7ca;font-size:clamp(1rem,1.5vw,1.15rem);line-height:1.75;">DriveLab recognizes more of what happens during a drive, turns completed sessions into Drive Stories, and can build an optional long-term Driver DNA profile without forcing it into the normal app experience.</p>
                <div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:22px;">
                    <span style="padding:8px 11px;border:1px solid rgba(0,216,255,.22);border-radius:999px;background:rgba(0,216,255,.075);color:#dff9ff;font-size:.78rem;font-weight:800;">18 maneuver types</span>
                    <span style="padding:8px 11px;border:1px solid rgba(0,216,255,.22);border-radius:999px;background:rgba(0,216,255,.075);color:#dff9ff;font-size:.78rem;font-weight:800;">Confidence scoring</span>
                    <span style="padding:8px 11px;border:1px solid rgba(0,216,255,.22);border-radius:999px;background:rgba(0,216,255,.075);color:#dff9ff;font-size:.78rem;font-weight:800;">XP and cooldowns</span>
                    <span style="padding:8px 11px;border:1px solid rgba(0,216,255,.22);border-radius:999px;background:rgba(0,216,255,.075);color:#dff9ff;font-size:.78rem;font-weight:800;">Local processing</span>
                    <span style="padding:8px 11px;border:1px solid rgba(0,216,255,.22);border-radius:999px;background:rgba(0,216,255,.075);color:#dff9ff;font-size:.78rem;font-weight:800;">Driver DNA off by default</span>
                </div>
            </div>
            <aside style="padding:24px;border:1px solid rgba(0,216,255,.28);border-radius:24px;background:linear-gradient(145deg,rgba(23,31,44,.96),rgba(13,19,30,.98));box-shadow:0 24px 60px rgba(0,0,0,.32);">
                <span style="display:block;color:#48e08b;font-size:.73rem;font-weight:900;letter-spacing:.14em;">DRIVE INTELLIGENCE</span>
                <strong style="display:block;margin-top:10px;color:#fff;font-size:1.45rem;line-height:1.2;">Stunts. Stories. Driving identity.</strong>
                <p style="color:#aab7ca;line-height:1.55;">Built into DriveLab's existing session, progression, and sharing systems.</p>
                <a href="/download/latest" style="display:inline-flex;margin-top:8px;padding:11px 15px;border-radius:999px;background:#00d8ff;color:#071018;font-weight:900;text-decoration:none;">Download DriveLab 2.4.0</a>
            </aside>
        </div>

        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:16px;margin-top:clamp(36px,6vw,66px);">
            {feature_cards}
        </div>

        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:22px;align-items:end;margin:clamp(54px,8vw,84px) 0 24px;">
            <div>
                <span style="color:#00d8ff;font-size:.78rem;font-weight:900;letter-spacing:.16em;">REAL ANDROID SCREENS</span>
                <h3 style="margin:7px 0 0;color:#fff;font-size:clamp(1.8rem,4vw,2.7rem);">Drive Intelligence inside the app</h3>
            </div>
            <p style="margin:0;color:#aab7ca;line-height:1.65;">These screens were captured from the working DriveLab 2.4.0 build. Select an image to open the full-resolution capture.</p>
        </div>

        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:18px;align-items:start;">
            {gallery}
        </div>
    </div>
</section>
{END}
'''

candidate_html = insert_near_racelink(restored_html, section)
candidate_html = re.sub(r"\n{4,}", "\n\n\n", candidate_html)

if candidate_html.count(START) != 1 or candidate_html.count(END) != 1:
    raise SystemExit("Drive Intelligence marker validation failed. Nothing was changed.")

if CSS_START in candidate_html or CSS_END in candidate_html:
    raise SystemExit("Old broken CSS markers remain. Nothing was changed.")

if candidate_html.count('id="drive-intelligence"') != 1:
    raise SystemExit("Drive Intelligence section count validation failed. Nothing was changed.")

race_position = candidate_html.lower().find("racelink", candidate_html.find(END))
if race_position < 0:
    print("WARNING: RaceLink text was not found after the inserted section; TrackLab/main fallback was used.")

candidate_file = page.with_name(page.name + ".v240-layout-candidate")
candidate_file.write_text(candidate_html, encoding="utf-8")

try:
    shutil.move(str(candidate_file), str(page))
    health = restart_and_check()
except Exception as error:
    shutil.copy2(emergency_page, page)
    try:
        restart_and_check()
    except Exception:
        pass
    raise SystemExit(
        "Website repair failed and the previous page was restored: " + str(error)
    )

print("DriveLab website layout repair completed.")
print(f"Homepage: {page}")
print(f"Restored source: {original_backup}")
print(f"Emergency backup: {emergency_page}")
print(f"Screenshot directory: {media_root}")
print(f"Screenshots used: {len(image_files)}")
print(f"Health: {health}")
print("The broken CSS markers were removed.")
print("Drive Intelligence now sits immediately beside the TrackLab/RaceLink feature flow.")
'@

[System.IO.File]::WriteAllText(
    $LocalScript,
    $Python,
    $Utf8Write
)

Write-Host ""
Write-Host "===== COPYING SAFE WEBSITE REPAIR =====" -ForegroundColor Cyan

& $Scp.Source $LocalScript "${Target}:$RemoteScript"

if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the website repair to the Pi."
}

Write-Host ""
Write-Host "===== RESTORING AND REBUILDING WEBSITE SECTION =====" -ForegroundColor Cyan

& $Ssh.Source -t $Target "sudo python3 '$RemoteScript'"

if ($LASTEXITCODE -ne 0) {
    throw "The safe website repair failed. Review the message above; the script leaves or restores the previous page on failure."
}

Remove-Item -LiteralPath $LocalScript -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "DRIVELAB WEBSITE LAYOUT REPAIR COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Open the website and press Ctrl+F5." -ForegroundColor Yellow
Write-Host "This repair does not republish or modify the APK update feed." -ForegroundColor Cyan
