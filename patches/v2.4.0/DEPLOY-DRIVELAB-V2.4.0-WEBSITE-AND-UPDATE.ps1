$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Project = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
$ExpectedVersion = "2.4.0"
$ExpectedCode = 36
$ServiceName = "drivelab-site.service"
$SiteRoot = "/opt/drivelab-site"
$SitePort = 8790
$Utf8Read = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8Write = [System.Text.UTF8Encoding]::new($false)

function Find-ScreenshotZip {
    $Candidates = @(
        (Join-Path $Project "release-output\DriveLab-v2.4.0-website-screenshots.zip"),
        (Join-Path $Project "website-media\DriveLab-v2.4.0-website-screenshots.zip"),
        (Join-Path $env:USERPROFILE "Downloads\DriveLab-v2.4.0-website-screenshots.zip"),
        (Join-Path $env:USERPROFILE "Desktop\DriveLab-v2.4.0-website-screenshots.zip")
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
    }

    $Chosen = Read-Host "Enter the full path to DriveLab-v2.4.0-website-screenshots.zip"
    if ([string]::IsNullOrWhiteSpace($Chosen) -or -not (Test-Path -LiteralPath $Chosen)) {
        throw "The DriveLab 2.4.0 screenshot ZIP was not found."
    }

    return $Chosen
}

if (-not (Test-Path -LiteralPath $Project)) {
    throw "DriveLab project was not found: $Project"
}

$GradleFile = Join-Path $Project "app\build.gradle.kts"
$CustomerApk = Join-Path $Project "release-output\DriveLab-Telem-v2.4.0.apk"
$BuiltApk = Join-Path $Project "app\build\outputs\apk\release\app-release.apk"
$PublisherBat = Join-Path $Project "PUBLISH-UPDATE-TO-PI.bat"
$PublisherPs1 = Join-Path $Project "PUBLISH-UPDATE-TO-PI.ps1"

if (-not (Test-Path -LiteralPath $GradleFile)) {
    throw "app\build.gradle.kts was not found."
}

$GradleText = [System.IO.File]::ReadAllText($GradleFile, $Utf8Read)
$VersionMatch = [regex]::Match($GradleText, 'versionName\s*=\s*"([^"]+)"')
$CodeMatch = [regex]::Match($GradleText, 'versionCode\s*=\s*(\d+)')

if (-not $VersionMatch.Success -or -not $CodeMatch.Success) {
    throw "Could not read the DriveLab version from Gradle."
}

$Version = $VersionMatch.Groups[1].Value
$VersionCode = [int]$CodeMatch.Groups[1].Value

if ($Version -ne $ExpectedVersion -or $VersionCode -ne $ExpectedCode) {
    throw "Expected DriveLab $ExpectedVersion build $ExpectedCode, but found $Version build $VersionCode."
}

if (-not (Test-Path -LiteralPath $CustomerApk)) {
    if (-not (Test-Path -LiteralPath $BuiltApk)) {
        throw "DriveLab-Telem-v2.4.0.apk was not found. Run the 2.4.0 build first."
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CustomerApk) | Out-Null
    Copy-Item -LiteralPath $BuiltApk -Destination $CustomerApk -Force
}

$ScreenshotZip = Find-ScreenshotZip
$ScreenshotHash = (Get-FileHash -LiteralPath $ScreenshotZip -Algorithm SHA256).Hash.ToLowerInvariant()
$ApkHash = (Get-FileHash -LiteralPath $CustomerApk -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host ""
Write-Host "===== DRIVELAB 2.4.0 RELEASE FILES =====" -ForegroundColor Cyan
Write-Host "Screenshots: $ScreenshotZip"
Write-Host "Screenshot SHA-256: $ScreenshotHash"
Write-Host "APK: $CustomerApk"
Write-Host "APK SHA-256: $ApkHash"

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
$RemoteZip = "/tmp/drivelab-v2.4.0-website-screenshots-$Timestamp.zip"
$RemoteScript = "/tmp/deploy-drivelab-v2.4.0-website-$Timestamp.py"
$LocalScript = Join-Path $env:TEMP "deploy-drivelab-v2.4.0-website-$Timestamp.py"

$Python = @'
from pathlib import Path
from datetime import datetime
from html import escape
import os
import re
import shutil
import sys
import zipfile

SITE_ROOT = Path("/opt/drivelab-site")
ZIP_PATH = Path(sys.argv[1])
START = "<!-- DRIVELAB DRIVE INTELLIGENCE START -->"
END = "<!-- DRIVELAB DRIVE INTELLIGENCE END -->"
CSS_START = "/* DRIVELAB DRIVE INTELLIGENCE CSS START */"
CSS_END = "/* DRIVELAB DRIVE INTELLIGENCE CSS END */"

CAPTIONS = {
    "01-drive-intelligence-settings.png": (
        "Drive Intelligence settings",
        "Stunt detection, Driver DNA, Drive Stories, sensitivity, visual popups, and spoken announcements are controlled from one themed settings area."
    ),
    "02-stunt-maneuver-popup.png": (
        "Live maneuver detection",
        "Confirmed maneuvers can appear live with the detected event, vehicle speed, confidence score, and earned XP."
    ),
    "03-driver-dna-available.png": (
        "Driver DNA stays optional",
        "Driver DNA remains visible as an available feature without entering the normal app experience while it is disabled."
    ),
    "04-driver-dna-profile.png": (
        "A profile that develops slowly",
        "When enabled, Driver DNA builds a private profile from completed drives instead of reacting wildly to one isolated session."
    ),
    "05-drive-story-session.png": (
        "Drive Stories in saved sessions",
        "Saved sessions can include a locally generated story, major moments, detected maneuvers, and important session statistics."
    ),
    "06-drive-story-complete-dialog.png": (
        "Review and share the drive",
        "Completed drives can be reviewed immediately and exported as a clean Drive Story share card."
    ),
}

PREFERRED_ORDER = list(CAPTIONS.keys())
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
        text = read_text(candidate)
        if not text:
            continue
        lowered = text.lower()
        score = 0
        score += lowered.count("drivelab") * 8
        score += lowered.count("tracklab") * 4
        score += lowered.count("racelink") * 4
        score += lowered.count("auto co-driver") * 4
        score += 10 if "</body>" in lowered else 0
        scored.append((score, -len(str(candidate)), candidate, text))

    if not scored:
        raise SystemExit("Could not locate the DriveLab website homepage.")

    scored.sort(reverse=True, key=lambda item: (item[0], item[1]))
    _, _, page, text = scored[0]
    return page, text


def choose_static_root(page, html):
    source_refs = re.findall(
        r'''(?is)(?:src|href)\s*=\s*["']([^"']+)["']''',
        html,
    )

    explicit_prefixes = []
    for source in source_refs:
        clean = source.split("?", 1)[0].split("#", 1)[0]
        for prefix in ("/static/", "/assets/", "/media/", "/public/"):
            if clean.startswith(prefix):
                explicit_prefixes.append(prefix.rstrip("/"))

    roots = [
        SITE_ROOT / "static",
        page.parent / "static",
        SITE_ROOT / "site" / "static",
        SITE_ROOT / "app" / "static",
        SITE_ROOT / "assets",
        page.parent / "assets",
        SITE_ROOT / "public",
        page.parent / "public",
        SITE_ROOT / "media",
        page.parent / "media",
    ]

    seen = set()
    roots = [item for item in roots if not (str(item) in seen or seen.add(str(item)))]

    for prefix in explicit_prefixes:
        expected_name = prefix.strip("/")
        for root in roots:
            if root.name == expected_name and root.exists():
                return root, prefix

    for root in roots:
        if root.exists() and root.is_dir():
            if root.name == "static":
                return root, "/static"
            if root.name == "assets":
                return root, "/assets"
            if root.name == "media":
                return root, "/media"
            if root.name == "public":
                return root, "/public"

    fallback = SITE_ROOT / "static"
    fallback.mkdir(parents=True, exist_ok=True)
    return fallback, "/static"


def visible_text(markup):
    return re.sub(r"\s+", " ", re.sub(r"(?is)<[^>]+>", " ", markup)).strip().lower()


def section_blocks(html):
    return list(re.finditer(r"(?is)<section\b[^>]*>.*?</section>", html))


def insert_in_feature_flow(html, section):
    blocks = section_blocks(html)

    for term in ("racelink", "drive link"):
        for block in blocks:
            if term in visible_text(block.group(0)):
                return html[:block.start()] + section + "\n\n" + html[block.start():]

    for term in ("auto co-driver", "auto codriver", "tracklab"):
        for block in reversed(blocks):
            if term in visible_text(block.group(0)):
                return html[:block.end()] + "\n\n" + section + html[block.end():]

    lowered = html.lower()
    for closing in ("</main>", "</body>"):
        position = lowered.rfind(closing)
        if position >= 0:
            return html[:position] + section + "\n" + html[position:]

    return html + "\n" + section


def clean_existing(html):
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
    return html


if not SITE_ROOT.exists():
    raise SystemExit(f"Website root was not found: {SITE_ROOT}")

if not ZIP_PATH.exists():
    raise SystemExit(f"Screenshot ZIP was not found: {ZIP_PATH}")

page, original_html = choose_homepage()
html = clean_existing(original_html)
static_root, url_prefix = choose_static_root(page, html)
media_root = static_root / "drive-intelligence"

stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
backup_root = SITE_ROOT / "backups" / f"drive-intelligence-v2.4.0-{stamp}"
backup_root.mkdir(parents=True, exist_ok=True)
shutil.copy2(page, backup_root / page.name)

if media_root.exists():
    shutil.copytree(media_root, backup_root / "media", dirs_exist_ok=True)
    shutil.rmtree(media_root)
media_root.mkdir(parents=True, exist_ok=True)

images = []
with zipfile.ZipFile(ZIP_PATH) as archive:
    entries = []
    for info in archive.infolist():
        if info.is_dir():
            continue
        basename = Path(info.filename).name
        suffix = Path(basename).suffix.lower()
        if suffix not in ALLOWED:
            continue
        entries.append((basename, info))

    if not entries:
        raise SystemExit("The screenshot ZIP did not contain PNG, JPG, JPEG, or WEBP images.")

    order_index = {name: index for index, name in enumerate(PREFERRED_ORDER)}
    entries.sort(key=lambda pair: (order_index.get(pair[0].lower(), 999), pair[0].lower()))

    used = set()
    for number, (basename, info) in enumerate(entries, start=1):
        safe = re.sub(r"[^A-Za-z0-9._-]+", "-", basename).strip("-.")
        if not safe:
            safe = f"drive-intelligence-{number:02d}.png"
        stem = Path(safe).stem
        suffix = Path(safe).suffix.lower()
        candidate = safe
        duplicate = 2
        while candidate.lower() in used:
            candidate = f"{stem}-{duplicate}{suffix}"
            duplicate += 1
        used.add(candidate.lower())

        destination = media_root / candidate
        with archive.open(info) as source, destination.open("wb") as output:
            shutil.copyfileobj(source, output)

        title, caption = CAPTIONS.get(
            basename.lower(),
            (f"Drive Intelligence screenshot {number}", "A real DriveLab 2.4.0 screen captured directly from the Android app."),
        )
        images.append((candidate, title, caption))

cards = [
    (
        "Full stunt detection",
        "Detect donuts, burnouts, J-turns, reverse 180s, drift transitions, jumps, flips, two-wheel driving, wheelies, stoppies, hard landings, and major recoveries from BeamNG telemetry."
    ),
    (
        "Optional Driver DNA",
        "Build a slow-changing private driving profile across twelve traits. Driver DNA starts disabled and remains completely out of the way until the driver enables it."
    ),
    (
        "Drive Stories",
        "Turn completed sessions into readable stories with major moments, detected maneuvers, records, difficult moments, and a clean share card generated locally on the phone."
    ),
]

feature_cards = "\n".join(
    f'''<article class="dl-di-card">
        <div class="dl-di-card-number">0{index}</div>
        <h3>{escape(title)}</h3>
        <p>{escape(body)}</p>
    </article>'''
    for index, (title, body) in enumerate(cards, start=1)
)

gallery = "\n".join(
    f'''<figure class="dl-di-shot">
        <button class="dl-di-shot-button" type="button" aria-label="Open {escape(title)} screenshot" onclick="window.open('{url_prefix}/drive-intelligence/{escape(filename)}','_blank','noopener')">
            <img src="{url_prefix}/drive-intelligence/{escape(filename)}" alt="{escape(title)} in DriveLab Telem 2.4.0" loading="lazy" decoding="async">
        </button>
        <figcaption>
            <strong>{escape(title)}</strong>
            <span>{escape(caption)}</span>
        </figcaption>
    </figure>'''
    for filename, title, caption in images
)

section = f'''
{START}
<section id="drive-intelligence" class="dl-di-section" aria-labelledby="drive-intelligence-title">
    <div class="dl-di-shell">
        <div class="dl-di-heading-grid">
            <div>
                <div class="dl-di-kicker">NEW IN DRIVELAB TELEM 2.4.0</div>
                <h2 id="drive-intelligence-title">Drive Intelligence</h2>
                <p class="dl-di-intro">DriveLab now understands more of what happens during the drive. It recognizes real maneuvers from MotionSim and OutGauge telemetry, turns completed sessions into Drive Stories, and can build an optional long-term Driver DNA profile without forcing it into the normal app experience.</p>
                <div class="dl-di-pills" aria-label="Drive Intelligence highlights">
                    <span>18 maneuver types</span>
                    <span>Confidence scoring</span>
                    <span>XP and cooldowns</span>
                    <span>Local processing</span>
                    <span>Driver DNA off by default</span>
                </div>
            </div>
            <aside class="dl-di-release-card">
                <span class="dl-di-release-label">DRIVE INTELLIGENCE</span>
                <strong>Stunts. Stories. Driving identity.</strong>
                <p>Built directly into the existing DriveLab session, progression, and sharing systems.</p>
                <a href="/download/latest">Download DriveLab 2.4.0</a>
            </aside>
        </div>

        <div class="dl-di-card-grid">
            {feature_cards}
        </div>

        <div class="dl-di-gallery-heading">
            <div>
                <span class="dl-di-gallery-kicker">REAL ANDROID SCREENS</span>
                <h3>Drive Intelligence inside the app</h3>
            </div>
            <p>These screenshots were captured from the working DriveLab 2.4.0 build. Select any image to open the full-resolution screen.</p>
        </div>

        <div class="dl-di-gallery">
            {gallery}
        </div>
    </div>
</section>
{END}
'''

css = f'''
{CSS_START}
<style>
.dl-di-section {{
    position: relative;
    padding: clamp(64px, 8vw, 104px) 20px;
    overflow: hidden;
    color: #ffffff;
    background:
        radial-gradient(circle at 12% 8%, rgba(0, 216, 255, .13), transparent 32%),
        radial-gradient(circle at 88% 18%, rgba(72, 224, 139, .08), transparent 30%),
        linear-gradient(180deg, rgba(7, 12, 20, .98), rgba(10, 15, 25, .98));
    border-top: 1px solid rgba(255, 255, 255, .06);
    border-bottom: 1px solid rgba(255, 255, 255, .06);
}}
.dl-di-section *, .dl-di-section *::before, .dl-di-section *::after {{ box-sizing: border-box; }}
.dl-di-shell {{ width: min(1180px, 100%); margin: 0 auto; }}
.dl-di-heading-grid {{ display: grid; grid-template-columns: minmax(0, 1.45fr) minmax(260px, .55fr); gap: clamp(24px, 5vw, 58px); align-items: center; }}
.dl-di-kicker, .dl-di-gallery-kicker {{ color: #00d8ff; font-size: .78rem; font-weight: 900; letter-spacing: .16em; text-transform: uppercase; }}
.dl-di-section h2 {{ margin: 10px 0 16px; font-size: clamp(2.3rem, 6vw, 4.7rem); line-height: .98; letter-spacing: -.045em; color: #ffffff; }}
.dl-di-intro {{ max-width: 760px; margin: 0; color: #aab7ca; font-size: clamp(1rem, 1.5vw, 1.16rem); line-height: 1.75; }}
.dl-di-pills {{ display: flex; flex-wrap: wrap; gap: 8px; margin-top: 22px; }}
.dl-di-pills span {{ padding: 8px 11px; border: 1px solid rgba(0,216,255,.22); border-radius: 999px; background: rgba(0,216,255,.075); color: #dff9ff; font-size: .78rem; font-weight: 800; }}
.dl-di-release-card {{ padding: 24px; border: 1px solid rgba(0,216,255,.28); border-radius: 24px; background: linear-gradient(145deg, rgba(23,31,44,.96), rgba(13,19,30,.98)); box-shadow: 0 24px 60px rgba(0,0,0,.32); }}
.dl-di-release-label {{ display: block; color: #48e08b; font-size: .73rem; font-weight: 900; letter-spacing: .14em; }}
.dl-di-release-card strong {{ display: block; margin-top: 10px; font-size: 1.45rem; line-height: 1.2; }}
.dl-di-release-card p {{ color: #aab7ca; line-height: 1.55; }}
.dl-di-release-card a {{ display: inline-flex; margin-top: 8px; padding: 11px 15px; border-radius: 999px; background: #00d8ff; color: #071018; font-weight: 900; text-decoration: none; }}
.dl-di-card-grid {{ display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 16px; margin-top: clamp(36px, 6vw, 68px); }}
.dl-di-card {{ position: relative; min-height: 230px; padding: 22px; border: 1px solid rgba(255,255,255,.075); border-radius: 22px; background: linear-gradient(155deg, rgba(23,31,44,.92), rgba(15,21,32,.96)); box-shadow: 0 18px 42px rgba(0,0,0,.18); }}
.dl-di-card-number {{ color: rgba(0,216,255,.42); font-size: .82rem; font-weight: 900; letter-spacing: .14em; }}
.dl-di-card h3 {{ margin: 28px 0 10px; color: #ffffff; font-size: 1.28rem; }}
.dl-di-card p {{ margin: 0; color: #aab7ca; line-height: 1.65; }}
.dl-di-gallery-heading {{ display: grid; grid-template-columns: minmax(0, 1fr) minmax(280px, .8fr); gap: 22px; align-items: end; margin: clamp(54px, 8vw, 88px) 0 24px; }}
.dl-di-gallery-heading h3 {{ margin: 7px 0 0; color: #ffffff; font-size: clamp(1.8rem, 4vw, 2.8rem); }}
.dl-di-gallery-heading p {{ margin: 0; color: #aab7ca; line-height: 1.65; }}
.dl-di-gallery {{ display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 18px; }}
.dl-di-shot {{ margin: 0; overflow: hidden; border: 1px solid rgba(255,255,255,.08); border-radius: 22px; background: #111722; box-shadow: 0 20px 48px rgba(0,0,0,.24); }}
.dl-di-shot-button {{ display: block; width: 100%; padding: 0; border: 0; cursor: zoom-in; background: #080c14; }}
.dl-di-shot img {{ display: block; width: 100%; height: auto; max-height: 660px; object-fit: contain; background: #080c14; transition: transform .22s ease, opacity .22s ease; }}
.dl-di-shot-button:hover img {{ transform: scale(1.018); opacity: .95; }}
.dl-di-shot figcaption {{ display: grid; gap: 7px; padding: 16px 17px 18px; }}
.dl-di-shot figcaption strong {{ color: #ffffff; font-size: .98rem; }}
.dl-di-shot figcaption span {{ color: #9eacc0; font-size: .88rem; line-height: 1.55; }}
@media (max-width: 900px) {{
    .dl-di-heading-grid, .dl-di-gallery-heading {{ grid-template-columns: 1fr; }}
    .dl-di-card-grid, .dl-di-gallery {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
}}
@media (max-width: 620px) {{
    .dl-di-section {{ padding-left: 14px; padding-right: 14px; }}
    .dl-di-card-grid, .dl-di-gallery {{ grid-template-columns: 1fr; }}
    .dl-di-card {{ min-height: 0; }}
    .dl-di-shot img {{ max-height: none; }}
}}
</style>
{CSS_END}
'''

lowered = html.lower()
head_position = lowered.rfind("</head>")
if head_position >= 0:
    html = html[:head_position] + css + "\n" + html[head_position:]
else:
    html = css + "\n" + html

html = insert_in_feature_flow(html, section)
html = re.sub(r"\n{4,}", "\n\n\n", html)

page.write_text(html, encoding="utf-8")

print("DriveLab 2.4.0 website section installed.")
print(f"Homepage: {page}")
print(f"Static root: {static_root}")
print(f"Image URL prefix: {url_prefix}/drive-intelligence/")
print(f"Screenshots installed: {len(images)}")
print(f"Backup: {backup_root}")
for filename, title, _ in images:
    print(f" - {filename}: {title}")
'@

[System.IO.File]::WriteAllText($LocalScript, $Python, $Utf8Write)

Write-Host ""
Write-Host "===== COPYING WEBSITE MEDIA =====" -ForegroundColor Cyan

& $Scp.Source $ScreenshotZip "${Target}:$RemoteZip"
if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the screenshot ZIP to the Pi."
}

& $Scp.Source $LocalScript "${Target}:$RemoteScript"
if ($LASTEXITCODE -ne 0) {
    throw "Could not copy the website installer to the Pi."
}

Write-Host ""
Write-Host "===== INSTALLING THEMED DRIVE INTELLIGENCE SECTION =====" -ForegroundColor Cyan

$RemoteCommand = @"
sudo python3 '$RemoteScript' '$RemoteZip' && \
sudo systemctl restart '$ServiceName' && \
sleep 3 && \
curl -fsS 'http://127.0.0.1:$SitePort/healthz'
"@

& $Ssh.Source -t $Target $RemoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "The website update, service restart, or health check failed."
}

Write-Host ""
Write-Host "===== PUBLISHING DRIVELAB 2.4.0 APK =====" -ForegroundColor Cyan

if (Test-Path -LiteralPath $PublisherBat) {
    & $PublisherBat
}
elseif (Test-Path -LiteralPath $PublisherPs1) {
    powershell.exe -ExecutionPolicy Bypass -File $PublisherPs1
}
else {
    throw "The update-server publisher was not found in the DriveLab project."
}

if ($LASTEXITCODE -ne 0) {
    throw "The update-server publisher failed. The website update remains installed."
}

Remove-Item -LiteralPath $LocalScript -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "DRIVELAB 2.4.0 WEBSITE AND UPDATE SERVER COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Website: themed Drive Intelligence section installed"
Write-Host "Screenshots: copied from $ScreenshotZip"
Write-Host "Update server: DriveLab 2.4.0 published"
Write-Host "APK SHA-256: $ApkHash"
Write-Host ""
Write-Host "Open the public site and press Ctrl+F5 to bypass the browser cache." -ForegroundColor Yellow
