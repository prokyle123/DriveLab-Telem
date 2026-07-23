$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Project = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
$PackageName = "com.auroramediagroup.drivelab"
$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$ExpectedVersion = "2.4.0"
$ExpectedCode = 36
$Utf8Read = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8Write = [System.Text.UTF8Encoding]::new($false)

function Capture-Screen {
    param(
        [string]$Serial,
        [string]$Directory,
        [string]$FileName,
        [string]$Title,
        [string]$Instructions
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host $Instructions
    Write-Host ""
    $Answer = Read-Host "Press ENTER to capture, or type S to skip"

    if ($Answer.Trim().ToUpperInvariant() -eq "S") {
        Write-Host "Skipped $FileName" -ForegroundColor Yellow
        return
    }

    $Remote = "/sdcard/$FileName"
    $Local = Join-Path $Directory $FileName

    & $Adb -s $Serial shell screencap -p $Remote | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Screenshot capture failed: $FileName" }

    & $Adb -s $Serial pull $Remote $Local | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Local)) {
        throw "Could not copy screenshot: $FileName"
    }

    & $Adb -s $Serial shell rm -f $Remote | Out-Null
    Write-Host "Captured: $Local" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $Project)) {
    throw "DriveLab project was not found: $Project"
}

if (-not (Test-Path -LiteralPath $Adb)) {
    throw "ADB was not found: $Adb"
}

$GradleFile = Join-Path $Project "app\build.gradle.kts"
$GradleText = [System.IO.File]::ReadAllText($GradleFile, $Utf8Read)
$VersionMatch = [regex]::Match($GradleText, 'versionName\s*=\s*"([^"]+)"')
$CodeMatch = [regex]::Match($GradleText, 'versionCode\s*=\s*(\d+)')

if (-not $VersionMatch.Success -or -not $CodeMatch.Success) {
    throw "Could not read the DriveLab app version."
}

$Version = $VersionMatch.Groups[1].Value
$VersionCode = [int]$CodeMatch.Groups[1].Value

if ($Version -ne $ExpectedVersion -or $VersionCode -ne $ExpectedCode) {
    throw "Expected DriveLab $ExpectedVersion build $ExpectedCode, but found $Version build $VersionCode."
}

$ReleaseOutput = Join-Path $Project "release-output"
$CustomerApk = Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0.apk"
$BuiltApk = Join-Path $Project "app\build\outputs\apk\release\app-release.apk"

if (-not (Test-Path -LiteralPath $CustomerApk)) {
    if (-not (Test-Path -LiteralPath $BuiltApk)) {
        throw "DriveLab-Telem-v2.4.0.apk was not found. Run the 2.4.0 patch/build first."
    }

    New-Item -ItemType Directory -Force -Path $ReleaseOutput | Out-Null
    Copy-Item -LiteralPath $BuiltApk -Destination $CustomerApk -Force
}

$ApkHash = (Get-FileHash -LiteralPath $CustomerApk -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "DriveLab 2.4.0 APK: $CustomerApk" -ForegroundColor Green
Write-Host "SHA-256: $ApkHash"

& $Adb start-server | Out-Null
$Devices = @(
    & $Adb devices |
        Select-Object -Skip 1 |
        ForEach-Object {
            if ($_ -match '^(\S+)\s+device$') { $matches[1] }
        }
)

if ($Devices.Count -eq 0) {
    throw "No authorized Android phone is connected."
}

$Serial = $Devices[0]
if ($Devices.Count -gt 1) {
    for ($Index = 0; $Index -lt $Devices.Count; $Index++) {
        Write-Host "[$($Index + 1)] $($Devices[$Index])"
    }

    $Selection = [int](Read-Host "Choose the phone number") - 1
    if ($Selection -lt 0 -or $Selection -ge $Devices.Count) {
        throw "Invalid Android device selection."
    }
    $Serial = $Devices[$Selection]
}

& $Adb -s $Serial install -r -g $CustomerApk
if ($LASTEXITCODE -ne 0) { throw "APK installation failed." }

& $Adb -s $Serial shell am force-stop $PackageName | Out-Null
& $Adb -s $Serial shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null

$ScreenshotDirectory = Join-Path $Project "website-media\drive-intelligence-v2.4.0"
New-Item -ItemType Directory -Force -Path $ScreenshotDirectory | Out-Null

Capture-Screen $Serial $ScreenshotDirectory "01-drive-intelligence-settings.png" `
    "SCREENSHOT 1 — DRIVE INTELLIGENCE SETTINGS" `
    "Open Setup and show the full DRIVE INTELLIGENCE settings card."

Capture-Screen $Serial $ScreenshotDirectory "02-stunt-maneuver-popup.png" `
    "SCREENSHOT 2 — MANEUVER DETECTED" `
    "Trigger a clean jump, donut, drift transition, or recovery. Capture while the MANEUVER DETECTED popup is visible."

Capture-Screen $Serial $ScreenshotDirectory "03-driver-dna-available.png" `
    "SCREENSHOT 3 — DRIVER DNA AVAILABLE" `
    "Disable Driver DNA, then open Analyze > Progress and show the available-but-disabled Driver DNA card."

Capture-Screen $Serial $ScreenshotDirectory "04-driver-dna-profile.png" `
    "SCREENSHOT 4 — DRIVER DNA PROFILE" `
    "Enable Driver DNA and show its Analyze > Progress profile with traits and confidence. Skip if it does not have enough data yet."

Capture-Screen $Serial $ScreenshotDirectory "05-drive-story-session.png" `
    "SCREENSHOT 5 — DRIVE STORY SESSION" `
    "Open Analyze > Sessions and show a saved session with its Drive Story and major moments."

Capture-Screen $Serial $ScreenshotDirectory "06-drive-story-complete-dialog.png" `
    "SCREENSHOT 6 — COMPLETED DRIVE STORY" `
    "Complete a recorded drive and show the completed-drive dialog with the Drive Story and SHARE STORY button. Skip if unavailable."

$Captions = @'
DriveLab Telem 2.4.0 — Drive Intelligence

01-drive-intelligence-settings.png
Drive Intelligence puts stunt detection, optional Driver DNA, Drive Stories, sensitivity, event popups, and spoken announcements in one settings area.

02-stunt-maneuver-popup.png
Confirmed stunts appear live with the detected maneuver, speed, confidence, and XP reward.

03-driver-dna-available.png
Driver DNA remains available without entering the normal app experience while disabled.

04-driver-dna-profile.png
When enabled, Driver DNA builds a slow-changing private profile from completed drives.

05-drive-story-session.png
Saved sessions include a locally generated Drive Story, major moments, and detected maneuvers.

06-drive-story-complete-dialog.png
Completed drives can be reviewed and shared as a Drive Story card.
'@

[System.IO.File]::WriteAllText(
    (Join-Path $ScreenshotDirectory "WEBSITE-CAPTIONS.txt"),
    $Captions,
    $Utf8Write
)

$ZipPath = Join-Path $ReleaseOutput "DriveLab-v2.4.0-website-screenshots.zip"
Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $ScreenshotDirectory "*") -DestinationPath $ZipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "Website screenshots ZIP:" -ForegroundColor Green
Write-Host $ZipPath

$PublisherBat = Join-Path $Project "PUBLISH-UPDATE-TO-PI.bat"
$PublisherPs1 = Join-Path $Project "PUBLISH-UPDATE-TO-PI.ps1"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "PUBLISH DRIVELAB 2.4.0 UPDATE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
$Publish = Read-Host "Type PUBLISH to push the APK, or press ENTER to skip"

if ($Publish.Trim().ToUpperInvariant() -eq "PUBLISH") {
    if (Test-Path -LiteralPath $PublisherBat) {
        & $PublisherBat
    }
    elseif (Test-Path -LiteralPath $PublisherPs1) {
        powershell.exe -ExecutionPolicy Bypass -File $PublisherPs1
    }
    else {
        throw "The update-server publisher was not found in the project."
    }

    if ($LASTEXITCODE -ne 0) {
        throw "The update-server publisher failed."
    }

    Write-Host "DriveLab 2.4.0 was pushed to the update server." -ForegroundColor Green
}
else {
    Write-Host "The update server was left unchanged." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Upload this ZIP in the chat so the screenshots can be placed into the existing themed website sections:" -ForegroundColor Cyan
Write-Host $ZipPath
