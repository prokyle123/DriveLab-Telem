param(
    [string]$Stage = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v2.4.0-lifecycle-stage-20260723-214946",
    [string]$SshTarget = "kali@ak47"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$VersionName = "2.4.0"
$VersionCode = 37
$PackageName = "com.auroramediagroup.drivelab"
$ExpectedSignerSha256 = "c27df4a0e5f3cd2f99d7240a49f3ce7936340d3359420872a651e3d4fed8b82d"
$SourceApk = Join-Path $Stage "release-output\DriveLab-Telem-v2.4.0-build37-AUTOMATIC-INTELLIGENCE-STAGE.apk"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Workspace = Join-Path $Stage "release-publish-$Stamp"
$CanonicalApk = Join-Path $Workspace "DriveLab-Telem-v2.4.0.apk"
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-Utf8([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n").Replace("`r", "`n"), $Utf8NoBom)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-HttpJson(
    [System.Net.Http.HttpClient]$Client,
    [System.Net.Http.HttpMethod]$Method,
    [string]$Uri,
    [System.Net.Http.HttpContent]$Content = $null
) {
    $Request = New-Object System.Net.Http.HttpRequestMessage($Method, $Uri)
    if ($null -ne $Content) {
        $Request.Content = $Content
    }
    try {
        $Response = $Client.SendAsync($Request).GetAwaiter().GetResult()
        $Body = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $Response.IsSuccessStatusCode) {
            throw "HTTP $([int]$Response.StatusCode) from ${Uri}: ${Body}"
        }
        return [pscustomobject]@{
            Text = $Body
            Json = $Body | ConvertFrom-Json
        }
    }
    finally {
        $Request.Dispose()
    }
}

function Get-StatValue($Stats, [string]$Name) {
    $Property = $Stats.PSObject.Properties[$Name]
    if ($null -eq $Property -or $null -eq $Property.Value) {
        return 0
    }
    return [int]$Property.Value
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "DRIVELAB 2.4.0 BUILD 37 - VIRUSTOTAL AND PRODUCTION PUBLISH" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Stage:      $Stage"
Write-Host "Source APK: $SourceApk"
Write-Host "SSH target: $SshTarget"

if (-not (Test-Path -LiteralPath $SourceApk -PathType Leaf)) {
    throw "The automatic-intelligence APK was not found: ${SourceApk}"
}

$Ssh = Get-Command ssh.exe -ErrorAction Stop
$Scp = Get-Command scp.exe -ErrorAction Stop
$BuildToolsRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools"
$ApkSigner = Get-ChildItem -Path $BuildToolsRoot -Filter apksigner.bat -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
$Aapt = Get-ChildItem -Path $BuildToolsRoot -Filter aapt.exe -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if ($null -eq $ApkSigner) { throw "apksigner.bat was not found under ${BuildToolsRoot}" }
if ($null -eq $Aapt) { throw "aapt.exe was not found under ${BuildToolsRoot}" }

New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
Copy-Item -LiteralPath $SourceApk -Destination $CanonicalApk -Force

Write-Host ""
Write-Host "===== VERIFYING THE EXACT APK BEFORE ANY NETWORK ACTION =====" -ForegroundColor Cyan
$SignerOutput = (& $ApkSigner.FullName verify --verbose --print-certs $CanonicalApk 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed.`n${SignerOutput}" }
if ($SignerOutput -notmatch [regex]::Escape($ExpectedSignerSha256)) {
    throw "The APK is not signed by the expected permanent DriveLab certificate."
}
$Badging = (& $Aapt.FullName dump badging $CanonicalApk 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw "aapt could not inspect the APK." }
if ($Badging -notmatch "package: name='com\.auroramediagroup\.drivelab'") { throw "Unexpected APK package name." }
if ($Badging -notmatch "versionCode='37'") { throw "Unexpected APK versionCode." }
if ($Badging -notmatch "versionName='2\.4\.0'") { throw "Unexpected APK versionName." }
$Sha256 = Get-Sha256 $CanonicalApk
$SizeBytes = (Get-Item -LiteralPath $CanonicalApk).Length
Write-Host "Package:    $PackageName" -ForegroundColor Green
Write-Host "Version:    $VersionName ($VersionCode)" -ForegroundColor Green
Write-Host "SHA-256:    $Sha256" -ForegroundColor Green
Write-Host "Size bytes: $SizeBytes" -ForegroundColor Green

Write-Host ""
Write-Host "===== VIRUSTOTAL API TOKEN =====" -ForegroundColor Cyan
Write-Host "The token is entered locally, kept in memory, and is not written to disk or GitHub." -ForegroundColor Yellow
$SecureToken = Read-Host "Paste the VirusTotal API token" -AsSecureString
$Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)
try {
    $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
}
if ([string]::IsNullOrWhiteSpace($Token)) { throw "No VirusTotal API token was entered." }

Add-Type -AssemblyName System.Net.Http
$Client = New-Object System.Net.Http.HttpClient
$Client.Timeout = [TimeSpan]::FromMinutes(5)
$Client.DefaultRequestHeaders.Add("x-apikey", $Token)
$UploadStartedUtc = [DateTimeOffset]::UtcNow
try {
    Write-Host ""
    Write-Host "===== UPLOADING THE EXACT APK TO VIRUSTOTAL =====" -ForegroundColor Cyan
    $Multipart = New-Object System.Net.Http.MultipartFormDataContent
    $FileBytes = [System.IO.File]::ReadAllBytes($CanonicalApk)
    $FileContent = New-Object System.Net.Http.ByteArrayContent -ArgumentList (,$FileBytes)
    $FileContent.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue("application/vnd.android.package-archive")
    $Multipart.Add($FileContent, "file", "DriveLab-Telem-v2.4.0.apk")
    try {
        $Upload = Invoke-HttpJson $Client ([System.Net.Http.HttpMethod]::Post) "https://www.virustotal.com/api/v3/files" $Multipart
    }
    finally {
        $FileContent.Dispose()
        $Multipart.Dispose()
        [Array]::Clear($FileBytes, 0, $FileBytes.Length)
    }

    $AnalysisId = [string]$Upload.Json.data.id
    if ([string]::IsNullOrWhiteSpace($AnalysisId)) { throw "VirusTotal did not return an analysis ID." }
    Write-Host "VirusTotal analysis ID received. Waiting for completion..."

    $AnalysisStatus = ""
    for ($Attempt = 1; $Attempt -le 60; $Attempt++) {
        Start-Sleep -Seconds 30
        $Analysis = Invoke-HttpJson $Client ([System.Net.Http.HttpMethod]::Get) "https://www.virustotal.com/api/v3/analyses/$AnalysisId"
        $AnalysisStatus = [string]$Analysis.Json.data.attributes.status
        Write-Host "VirusTotal status: $AnalysisStatus ($Attempt/60)"
        if ($AnalysisStatus -eq "completed") { break }
    }
    if ($AnalysisStatus -ne "completed") { throw "VirusTotal analysis did not complete within 30 minutes." }

    $FileReport = $null
    for ($Attempt = 1; $Attempt -le 12; $Attempt++) {
        try {
            $FileReport = Invoke-HttpJson $Client ([System.Net.Http.HttpMethod]::Get) "https://www.virustotal.com/api/v3/files/$Sha256"
            break
        }
        catch {
            if ($Attempt -eq 12) { throw }
            Start-Sleep -Seconds 10
        }
    }
}
finally {
    $Client.Dispose()
    $Token = $null
    $SecureToken.Dispose()
}

$Attributes = $FileReport.Json.data.attributes
if ([string]$Attributes.sha256 -ne $Sha256) { throw "VirusTotal returned a report for a different SHA-256." }
$Stats = $Attributes.last_analysis_stats
$Malicious = Get-StatValue $Stats "malicious"
$Suspicious = Get-StatValue $Stats "suspicious"
$Undetected = Get-StatValue $Stats "undetected"
$Harmless = Get-StatValue $Stats "harmless"
$Timeouts = (Get-StatValue $Stats "timeout") + (Get-StatValue $Stats "confirmed-timeout")
$Failures = Get-StatValue $Stats "failure"
$Unsupported = Get-StatValue $Stats "type-unsupported"
$EngineResults = @($Attributes.last_analysis_results.PSObject.Properties).Count
if ($EngineResults -le 0) {
    $EngineResults = $Malicious + $Suspicious + $Undetected + $Harmless + $Timeouts + $Failures + $Unsupported
}
if ($Malicious -gt 0 -or $Suspicious -gt 0) {
    throw "VirusTotal reported malicious=${Malicious}, suspicious=${Suspicious}. Production publishing was blocked."
}
$AnalysisEpoch = [int64]$Attributes.last_analysis_date
if ($AnalysisEpoch -gt 0) {
    $ScannedUtc = [DateTimeOffset]::FromUnixTimeSeconds($AnalysisEpoch).UtcDateTime
}
else {
    $ScannedUtc = [DateTime]::UtcNow
}
$ScannedIso = $ScannedUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
$ScannedDisplay = $ScannedUtc.ToString("MMMM d, yyyy", [Globalization.CultureInfo]::GetCultureInfo("en-US"))
$VtUrl = "https://www.virustotal.com/gui/file/$Sha256"

$ReceiptPath = Join-Path $Workspace "DriveLab-Telem-v2.4.0-VirusTotal.txt"
$VtUrlPath = Join-Path $Workspace "DriveLab-Telem-v2.4.0-VirusTotal-URL.txt"
$VtJsonPath = Join-Path $Workspace "DriveLab-Telem-v2.4.0-VirusTotal.json"
$ShaPath = Join-Path $Workspace "DriveLab-Telem-v2.4.0-SHA256.txt"
$NotesPath = Join-Path $Workspace "release-notes.txt"
$SecurityBlockPath = Join-Path $Workspace "security-block.html"
$RemoteScriptPath = Join-Path $Workspace "publish-on-pi.sh"

$Receipt = @"
DriveLab Telem 2.4.0 VirusTotal verification

Version: 2.4.0
Build: 37
APK: DriveLab-Telem-v2.4.0.apk
SHA-256: $Sha256
Scanned UTC: $ScannedIso
VirusTotal report: $VtUrl

Analysis statistics
Malicious: $Malicious
Suspicious: $Suspicious
Undetected: $Undetected
Harmless: $Harmless
Timeouts: $Timeouts
Failures: $Failures
Type unsupported: $Unsupported
Total engine results: $EngineResults
"@
Write-Utf8 $ReceiptPath $Receipt
Write-Utf8 $VtUrlPath "$VtUrl`n"
Write-Utf8 $VtJsonPath ($FileReport.Text + "`n")
Write-Utf8 $ShaPath @"
DriveLab Telem 2.4.0
Build: 37
APK: DriveLab-Telem-v2.4.0.apk
SHA-256: $Sha256
VirusTotal: $VtUrl
"@
Write-Utf8 $NotesPath @"
DriveLab Telem 2.4.0 build 37

- Added signed lifecycle intelligence for launches, active days, version history, Free-to-Full changes, crash-free sessions, and BeamNG connection outcomes.
- Added automatic feature-use intelligence and automatic completed real-session summaries.
- Added a user-triggered sanitized diagnostic report for support.
- Removed lifecycle reporting switches from Setup while keeping raw UDP telemetry, GPS, routes, chat, license keys, screenshots, and phone files excluded.
- Corrected the in-app release history so undeployed version 2.4.1 is not listed as a release.
- Preserved licenses, settings, sessions, achievements, TrackLab courses, RaceLink profiles, and Android signing compatibility.
"@
$ShortHash = $Sha256.Substring(0, 12) + "&hellip;" + $Sha256.Substring($Sha256.Length - 12)
$SecurityBlock = @"
<!-- DRIVELAB DOWNLOAD TRUST START -->
        <div class="download-security-trust" id="security" aria-label="DriveLab APK security verification">
          <div class="download-security-summary">
            <span class="download-security-icon" aria-hidden="true">&#10003;</span>
            <div>
              <p class="download-security-kicker">VERIFIED PRODUCTION APK</p>
              <strong>$Malicious malicious &bull; $Suspicious suspicious</strong>
              <span>VirusTotal $EngineResults engine results &bull; exact signed build 37 APK</span>
            </div>
          </div>
          <div class="download-security-links" aria-label="APK verification links">
            <a href="$VtUrl" target="_blank" rel="noopener noreferrer">VirusTotal report</a>
            <a href="/static/security/DriveLab-Telem-v2.4.0-VirusTotal.txt" target="_blank" rel="noopener noreferrer">Verification receipt</a>
            <a href="/static/security/DriveLab-Telem-v2.4.0-SHA256.txt" target="_blank" rel="noopener noreferrer">SHA-256 details</a>
          </div>
          <p class="download-security-meta">DriveLab Telem 2.4.0 (37) &bull; scanned $ScannedDisplay &bull; SHA-256 <code>$ShortHash</code></p>
          <p class="download-security-note">No participating VirusTotal engine flagged this exact APK at the recorded scan time. Malware scans are point-in-time checks and cannot guarantee absolute safety. Install only from official DriveLab sources.</p>
        </div>
        <!-- DRIVELAB DOWNLOAD TRUST END -->
"@
Write-Utf8 $SecurityBlockPath $SecurityBlock

$RemoteScript = @'
#!/usr/bin/env bash
set -Eeuo pipefail

REMOTE_DIR="${1:?remote directory required}"
EXPECTED_SHA="${2:?expected SHA-256 required}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/var/backups/drivelab-release-publish/$STAMP"
UPDATES="/var/lib/drivelab-license/updates"
SITE_ROOT="/opt/drivelab-site"
SITE_INDEX="$SITE_ROOT/public/index.html"
SECURITY_DIR="$SITE_ROOT/static/security"
APK="$REMOTE_DIR/DriveLab-Telem-v2.4.0.apk"
NOTES="$REMOTE_DIR/release-notes.txt"
CHANGED=0

rollback() {
    echo
    echo "===== AUTOMATIC RELEASE ROLLBACK ====="
    if [[ -d "$BACKUP/updates" ]]; then
        rm -rf "$UPDATES"
        cp -a "$BACKUP/updates" "$UPDATES"
    fi
    if [[ -f "$BACKUP/index.html" ]]; then
        install -o drivelab-site -g drivelab-site -m 0644 "$BACKUP/index.html" "$SITE_INDEX"
    fi
    if [[ -d "$BACKUP/security" ]]; then
        rm -rf "$SECURITY_DIR"
        cp -a "$BACKUP/security" "$SECURITY_DIR"
    fi
    systemctl restart drivelab-site.service || true
    systemctl start drivelab-public-status-publisher.service || true
    echo "Rollback attempted from: $BACKUP"
}

on_error() {
    local status="$1"
    local line="$2"
    trap - ERR
    set +e
    echo "Release deployment failed at line $line with status $status." >&2
    if [[ "$CHANGED" -eq 1 ]]; then rollback; fi
    exit "$status"
}
trap 'on_error $? $LINENO' ERR

[[ "$EUID" -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
for required in "$APK" "$NOTES" "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal.txt" "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal.json" "$REMOTE_DIR/DriveLab-Telem-v2.4.0-VirusTotal-URL.txt" "$REMOTE_DIR/DriveLab-Telem-v2.4.0-SHA256.txt" "$REMOTE_DIR/security-block.html"; do
    [[ -f "$required" ]] || { echo "Missing release file: $required" >&2; exit 1; }
done
[[ "$(sha256sum "$APK" | awk '{print $1}')" == "$EXPECTED_SHA" ]] || { echo "Remote APK hash mismatch." >&2; exit 1; }
systemctl is-active --quiet drivelab-license-api.service
systemctl is-active --quiet drivelab-site.service
curl -fsS --max-time 10 http://127.0.0.1:8787/v1/health >/dev/null
curl -fsS --max-time 10 http://127.0.0.1:8790/healthz >/dev/null

mkdir -p "$BACKUP"
chmod 0700 "$BACKUP"
cp -a "$UPDATES" "$BACKUP/updates"
cp -a "$SITE_INDEX" "$BACKUP/index.html"
cp -a "$SECURITY_DIR" "$BACKUP/security"
CHANGED=1

echo
echo "===== PUBLISHING SIGNED BUILD 37 UPDATE ====="
/usr/local/bin/drivelab-license-admin publish-update \
    --apk "$APK" \
    --version-code 37 \
    --version-name 2.4.0 \
    --notes-file "$NOTES" \
    --min-android-sdk 26 \
    --channel stable

echo
echo "===== INSTALLING VIRUSTOTAL WEBSITE RECEIPTS ====="
install -d -o drivelab-site -g drivelab-site -m 0755 "$SECURITY_DIR"
for name in DriveLab-Telem-v2.4.0-VirusTotal.txt DriveLab-Telem-v2.4.0-VirusTotal.json DriveLab-Telem-v2.4.0-VirusTotal-URL.txt DriveLab-Telem-v2.4.0-SHA256.txt; do
    install -o drivelab-site -g drivelab-site -m 0644 "$REMOTE_DIR/$name" "$SECURITY_DIR/$name"
done

python3 - "$SITE_INDEX" "$REMOTE_DIR/security-block.html" <<'PYHTML'
import re
import sys
from pathlib import Path
index = Path(sys.argv[1])
block = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
text = index.read_text(encoding="utf-8")
pattern = re.compile(r"<!-- DRIVELAB DOWNLOAD TRUST START -->.*?<!-- DRIVELAB DOWNLOAD TRUST END -->", re.S)
updated, count = pattern.subn(block, text, count=1)
if count != 1:
    raise SystemExit(f"Expected one website trust block, found {count}")
index.write_text(updated, encoding="utf-8")
PYHTML
chown drivelab-site:drivelab-site "$SITE_INDEX"
chmod 0644 "$SITE_INDEX"
systemctl restart drivelab-site.service
systemctl start drivelab-public-status-publisher.service

for attempt in $(seq 1 30); do
    if curl -fsS --max-time 5 http://127.0.0.1:8790/healthz >/dev/null; then break; fi
    sleep 1
done
curl -fsS --max-time 10 http://127.0.0.1:8787/v1/update/latest > "$BACKUP/live-update-bundle.json"
curl -fsSL --max-time 60 http://127.0.0.1:8787/v1/public/download/latest -o "$BACKUP/live-download.apk"
[[ "$(sha256sum "$BACKUP/live-download.apk" | awk '{print $1}')" == "$EXPECTED_SHA" ]] || { echo "Published download hash mismatch." >&2; exit 1; }
curl -fsS --max-time 10 http://127.0.0.1:8790/ > "$BACKUP/live-site.html"
grep -Fq "$EXPECTED_SHA" "$BACKUP/live-site.html"
curl -fsS --max-time 10 http://127.0.0.1:8790/static/security/DriveLab-Telem-v2.4.0-VirusTotal.txt > "$BACKUP/live-vt-receipt.txt"
grep -Fq "Build: 37" "$BACKUP/live-vt-receipt.txt"
grep -Fq "$EXPECTED_SHA" "$BACKUP/live-vt-receipt.txt"
/usr/local/bin/drivelab-license-admin update-status > "$BACKUP/update-status.txt"

CHANGED=0
trap - ERR
echo
echo "============================================================"
echo "DRIVELAB BUILD 37 PUBLISHED SUCCESSFULLY"
echo "============================================================"
echo "Backup: $BACKUP"
echo "SHA-256: $EXPECTED_SHA"
echo "Update feed, public download, website trust block, and VirusTotal receipts validated."
'@
Write-Utf8 $RemoteScriptPath $RemoteScript

Write-Host ""
Write-Host "===== COPYING VERIFIED RELEASE PACKAGE TO THE PI =====" -ForegroundColor Cyan
$RemoteDir = "/home/kali/drivelab-release-2.4.0-build37-$Stamp"
& $Ssh.Source $SshTarget "mkdir -p '$RemoteDir' && chmod 700 '$RemoteDir'"
if ($LASTEXITCODE -ne 0) { throw "Could not create the remote release directory." }
$FilesToCopy = @(
    $CanonicalApk,
    $ReceiptPath,
    $VtUrlPath,
    $VtJsonPath,
    $ShaPath,
    $NotesPath,
    $SecurityBlockPath,
    $RemoteScriptPath
)
foreach ($Path in $FilesToCopy) {
    & $Scp.Source $Path "${SshTarget}:${RemoteDir}/"
    if ($LASTEXITCODE -ne 0) { throw "SCP failed for ${Path}." }
}

Write-Host ""
Write-Host "===== PROMOTING UPDATE FEED AND WEBSITE WITH ROLLBACK PROTECTION =====" -ForegroundColor Cyan
& $Ssh.Source -t $SshTarget "chmod 0700 '$RemoteDir/publish-on-pi.sh' && sudo bash '$RemoteDir/publish-on-pi.sh' '$RemoteDir' '$Sha256'"
if ($LASTEXITCODE -ne 0) { throw "The Pi release promotion failed or rolled back." }

Write-Host ""
Write-Host "===== PUBLIC ENDPOINT CHECKS =====" -ForegroundColor Cyan
try {
    $PublicLatest = Invoke-WebRequest -UseBasicParsing -Uri "https://license.drivelabregistration.org/v1/update/latest" -TimeoutSec 20
    if ($PublicLatest.StatusCode -ne 200) { throw "Unexpected update endpoint status." }
    Write-Host "Public signed update endpoint: HTTP 200" -ForegroundColor Green
}
catch {
    Write-Warning "The local Pi validation passed, but the public update endpoint check failed: $($_.Exception.Message)"
}
try {
    $PublicSite = Invoke-WebRequest -UseBasicParsing -Uri "https://drivelabregistration.org/" -TimeoutSec 20
    if ($PublicSite.Content -notmatch [regex]::Escape($Sha256)) { throw "The public page did not contain the new SHA-256." }
    Write-Host "Public website VirusTotal block: updated" -ForegroundColor Green
}
catch {
    Write-Warning "The local Pi validation passed, but the public website check failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "DRIVELAB 2.4.0 BUILD 37 RELEASE COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Published APK: $CanonicalApk"
Write-Host "SHA-256:      $Sha256"
Write-Host "VirusTotal:   $VtUrl"
Write-Host "Malicious:    $Malicious"
Write-Host "Suspicious:   $Suspicious"
Write-Host "Engines:      $EngineResults"
Write-Host "Workspace:    $Workspace"
