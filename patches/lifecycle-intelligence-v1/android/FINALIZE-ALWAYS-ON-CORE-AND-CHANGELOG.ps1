param(
    [Parameter(Mandatory = $true)]
    [string]$Stage
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Get-Location).Path
$Stage = [System.IO.Path]::GetFullPath($Stage)
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Backup = Join-Path $Stage "pre-finalize-backup-$Stamp"
$Report = Join-Path $Stage "LIFECYCLE-ANDROID-FINAL-STAGE-REPORT.txt"

function Normalize-Lf([string]$Value) {
    return $Value.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Read-StrictUtf8([string]$Path) {
    return Normalize-Lf ([System.IO.File]::ReadAllText($Path, $Utf8Strict))
}

function Write-Utf8Lf([string]$Path, [string]$Value) {
    [System.IO.File]::WriteAllText($Path, (Normalize-Lf $Value), $Utf8NoBom)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Replace-Once(
    [string]$Text,
    [string]$Old,
    [string]$New,
    [string]$Label
) {
    $Old = Normalize-Lf $Old
    $New = Normalize-Lf $New
    $Count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($Count -ne 1) {
        throw "${Label} expected exactly one source anchor but found ${Count}."
    }
    return $Text.Replace($Old, $New)
}

function Assert-OriginalHash([string]$Relative, [string]$Expected) {
    $Path = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required original source file is missing: ${Path}"
    }
    $Actual = Get-Sha256 $Path
    if ($Actual -ne $Expected) {
        throw "Original working-project baseline mismatch for ${Relative}. Expected ${Expected} but found ${Actual}."
    }
}

function Assert-Contains([string]$Path, [string]$Marker) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required staged file is missing: ${Path}"
    }
    $Text = Read-StrictUtf8 $Path
    if (-not $Text.Contains($Marker)) {
        throw "Required staged marker is missing from ${Path}: ${Marker}"
    }
}

$Baseline = [ordered]@{
    "app\build.gradle.kts" = "c43eeeece37af4b61e5d216b385376a46921f0bc12ae2abfb9eb42908f135c65"
    "app\src\main\java\com\auroramediagroup\drivelab\DriveLabUi.kt" = "8ec170cea01161a7444d168f1857ee4c8591927b26edeb3cae1a999ea2cc5143"
    "app\src\main\java\com\auroramediagroup\drivelab\DriveLabViewModel.kt" = "f2c342e647669768e06a7e93b6221eb66359af6d9dfa71072bc1d4371c40a7ec"
    "app\src\main\java\com\auroramediagroup\drivelab\MainActivity.kt" = "83a516b6540b45d006a2018c73b4633ec98be6821e31b40ed787ed470a88c215"
    "app\src\main\java\com\auroramediagroup\drivelab\Models.kt" = "353a679a1ce9a4787630043adbd4b4c61f6ba7b9ceb726fa201c187c535a08dc"
    "app\src\main\java\com\auroramediagroup\drivelab\Storage.kt" = "8911ec4f3068e77014ba044a39cb7d057e7664c97ad06b90459ae598c91fab33"
    "app\src\main\java\com\auroramediagroup\drivelab\UpdateUi.kt" = "00b2825c4146236b9f5784f8758625b0971237e0cb5d40725cf8644bae7cc23f"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "DRIVELAB 2.4.0 BUILD 37 - FINAL LIFECYCLE CLEANUP" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Original project: $Root"
Write-Host "Existing stage:   $Stage"
Write-Host "Stage backup:     $Backup"

if (-not (Test-Path -LiteralPath $Stage -PathType Container)) {
    throw "The isolated stage was not found: ${Stage}"
}
if ($Stage.TrimEnd('\') -eq $Root.TrimEnd('\')) {
    throw "The stage must not be the original working project."
}
if (-not (Test-Path -LiteralPath (Join-Path $Root "gradlew.bat") -PathType Leaf)) {
    throw "Run this command from the original DriveLab Android project root."
}
if (-not (Test-Path -LiteralPath (Join-Path $Stage "gradlew.bat") -PathType Leaf)) {
    throw "The staged Gradle wrapper is missing."
}

Write-Host ""
Write-Host "===== VERIFYING ORIGINAL PROJECT REMAINS UNCHANGED =====" -ForegroundColor Cyan
foreach ($Entry in $Baseline.GetEnumerator()) {
    Assert-OriginalHash $Entry.Key $Entry.Value
}
Write-Host "Original project baseline hashes passed." -ForegroundColor Green

$JavaRoot = Join-Path $Stage "app\src\main\java\com\auroramediagroup\drivelab"
$GradlePath = Join-Path $Stage "app\build.gradle.kts"
$LifecyclePath = Join-Path $JavaRoot "LifecycleTelemetry.kt"
$ViewModelPath = Join-Path $JavaRoot "DriveLabViewModel.kt"
$UiPath = Join-Path $JavaRoot "DriveLabUi.kt"
$StoragePath = Join-Path $JavaRoot "Storage.kt"
$UpdateUiPath = Join-Path $JavaRoot "UpdateUi.kt"
$MainActivityPath = Join-Path $JavaRoot "MainActivity.kt"
$ModelsPath = Join-Path $JavaRoot "Models.kt"

Write-Host ""
Write-Host "===== VERIFYING THE CURRENT TESTED STAGE =====" -ForegroundColor Cyan
Assert-Contains $GradlePath 'versionCode = 37'
Assert-Contains $GradlePath 'versionName = "2.4.0"'
Assert-Contains $LifecyclePath 'featureUsageEnabled: Boolean = this.featureUsageEnabled,'
Assert-Contains $LifecyclePath 'sessionSummariesEnabled: Boolean = this.sessionSummariesEnabled,'
Assert-Contains $ViewModelPath 'private val lifecycleTelemetry = LifecycleTelemetryManager(application)'
Assert-Contains $UiPath 'DEVICE LIFECYCLE & PRIVACY'
Assert-Contains $StoragePath 'lifecycleReportingEnabled = preferences.getBoolean("lifecycleReportingEnabled", true),'
Assert-Contains $UpdateUiPath 'version = "2.4.1"'
Write-Host "Existing lifecycle build and mistaken 2.4.1 changelog state verified." -ForegroundColor Green

Write-Host ""
Write-Host "===== BACKING UP THE ISOLATED STAGE FILES =====" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
foreach ($Path in @($StoragePath, $ViewModelPath, $UiPath, $UpdateUiPath)) {
    Copy-Item -LiteralPath $Path -Destination (Join-Path $Backup ([System.IO.Path]::GetFileName($Path))) -Force
}
Write-Host "Stage source backup completed." -ForegroundColor Green

Write-Host ""
Write-Host "===== MAKING CORE LIFECYCLE INTELLIGENCE PERMANENTLY ENABLED =====" -ForegroundColor Cyan
$Text = Read-StrictUtf8 $StoragePath
$Text = Replace-Once $Text `
    '        lifecycleReportingEnabled = preferences.getBoolean("lifecycleReportingEnabled", true),' `
    '        lifecycleReportingEnabled = true,' `
    "Always-on lifecycle load"
$Text = Replace-Once $Text `
    '            .putBoolean("lifecycleReportingEnabled", settings.lifecycleReportingEnabled)' `
    '            .putBoolean("lifecycleReportingEnabled", true)' `
    "Always-on lifecycle save"
Write-Utf8Lf $StoragePath $Text

$Text = Read-StrictUtf8 $ViewModelPath
$Old = @'
            lifecycleTelemetry.configure(
                enabled = _settings.value.lifecycleReportingEnabled,
                featureUsage = _settings.value.featureUsageReportingEnabled,
                sessionSummaries = _settings.value.sessionSummarySharingEnabled
            )
'@
$New = @'
            lifecycleTelemetry.configure(
                enabled = true,
                featureUsage = _settings.value.featureUsageReportingEnabled,
                sessionSummaries = _settings.value.sessionSummarySharingEnabled
            )
'@
$Text = Replace-Once $Text $Old $New "Always-on lifecycle startup"
Write-Utf8Lf $ViewModelPath $Text
Write-Host "Core lifecycle reporting now ignores any old disabled preference and starts enabled." -ForegroundColor Green

Write-Host ""
Write-Host "===== REMOVING THE CORE REPORTING SWITCH FROM SETUP =====" -ForegroundColor Cyan
$Text = Read-StrictUtf8 $UiPath
$Text = Replace-Once $Text `
    '                    "Signed, low-volume reports help identify app versions, active days, license conversions, crashes, and BeamNG connection failures. Raw UDP packets, routes, GPS, chat, license keys, screenshots, and phone files are never included.",' `
    '                    "Core signed lifecycle and reliability intelligence runs automatically. Raw UDP packets, routes, GPS, chat, license keys, screenshots, and phone files are never included. Optional feature usage and completed-session summaries remain controlled below.",' `
    "Lifecycle card explanation"
$MasterSwitch = @'
                SettingSwitch(
                    "Device and reliability reporting",
                    "Installation/version history, app launches, crash-free status, edition changes, and connection outcomes. Enabled by default and may be disabled here.",
                    settings.lifecycleReportingEnabled,
                    viewModel::setLifecycleReportingEnabled
                )
'@
$Text = Replace-Once $Text $MasterSwitch '' "Remove core lifecycle switch"
$Text = Replace-Once $Text `
    '                    settings.lifecycleReportingEnabled && settings.featureUsageReportingEnabled,' `
    '                    settings.featureUsageReportingEnabled,' `
    "Feature usage switch independence"
$Text = Replace-Once $Text `
    '                    settings.lifecycleReportingEnabled && settings.sessionSummarySharingEnabled,' `
    '                    settings.sessionSummarySharingEnabled,' `
    "Session summary switch independence"
$Text = Replace-Once $Text `
    '                Text("Device and reliability reporting sends a random installation ID, Android Keystore public key, app version, Free or Full association, app launch and active-day events, version and edition changes, clean or unclean app-session status, and summarized BeamNG connection outcomes. This reporting is low volume, cryptographically signed by the device, enabled by default, and may be disabled in Setup.")' `
    '                Text("Core device and reliability intelligence sends a random installation ID, Android Keystore public key, app version, Free or Full association, app launch and active-day events, version and edition changes, clean or unclean app-session status, and summarized BeamNG connection outcomes. This low-volume reporting is cryptographically signed by the device and runs automatically as part of DriveLab.")' `
    "Always-on privacy disclosure"
Write-Utf8Lf $UiPath $Text
Write-Host "The core reporting switch was removed; optional feature and session-summary controls remain." -ForegroundColor Green

Write-Host ""
Write-Host "===== CORRECTING THE UNDEPLOYED 2.4.1 CHANGELOG =====" -ForegroundColor Cyan
$Text = Read-StrictUtf8 $UpdateUiPath
$OldRelease = @'
private val ReleaseHistory = listOf(
    ReleaseEntry(
        version = "2.4.1",
        label = "CURRENT RELEASE",
        notes = listOf(
            "Kept Cockpit, Link, and Analyze visible in Free Edition with their normal bottom-navigation letters.",
            "Free users now see the real Full pages dimmed underneath a disabled preview layer instead of a replacement locked page.",
            "Added compact Full Version Preview cards explaining Cockpit, RaceLink, and Analyze.",
            "Added direct Get Full Version and Enter License Key actions without changing licensed Full Edition behavior.",
            "Preserved licenses, Drive Intelligence data, sessions, achievements, TrackLab courses, RaceLink profiles, settings, and Android signing compatibility."
        )
    ),    ReleaseEntry(
        version = "2.4.0",
        label = "PREVIOUS RELEASE",
        notes = listOf(
            "Added Drive Intelligence with live stunt and maneuver detection.",
            "Added donuts, burnouts, J-turns, reverse 180s, Scandinavian flicks, handbrake-style turns, and drift transitions.",
            "Added two-wheel driving, wheelies, stoppies, clean jumps, big jumps, hard landings, barrel rolls, front flips, backflips, and flat spins.",
            "Added near-rollover recovery and high-speed-save detection.",
            "Added confidence scoring, cooldowns, repeat-event XP reduction, optional large event cards, and optional spoken maneuver names.",
            "Added optional Driver DNA with twelve slow-changing traits. Driver DNA is disabled by default and stored locally.",
            "Added locally generated Drive Stories with major moments and shareable story cards.",
            "Added Drive Stories and maneuver history to recorded sessions and completed-drive summaries.",
            "Preserved licenses, TrackLab courses and laps, Auto Co-Driver settings, RaceLink data, achievements, progression, sessions, crashes, and Android signing compatibility."
        )
    ),
'@
$NewRelease = @'
private val ReleaseHistory = listOf(
    ReleaseEntry(
        version = "2.4.0",
        label = "CURRENT RELEASE",
        notes = listOf(
            "Added Drive Intelligence with live stunt, maneuver, recovery, jump, roll, drift-transition, burnout, donut, J-turn, and high-speed-save detection.",
            "Added confidence scoring, cooldowns, repeat-event XP reduction, optional event cards, optional spoken maneuver names, Driver DNA, and locally generated Drive Stories.",
            "Kept Cockpit, Link, and Analyze visible in Free Edition and added dimmed Full Version previews with direct upgrade and license-entry actions.",
            "Added signed lifecycle intelligence for app launches, active days, version history, Free-to-Full changes, crash-free sessions, and BeamNG connection outcomes.",
            "Core lifecycle and reliability reporting now runs automatically; optional anonymous feature usage and completed-session summaries remain user-controlled.",
            "Added a user-triggered sanitized diagnostic report for support without uploading raw telemetry, GPS, routes, chat, license keys, screenshots, or phone files.",
            "Preserved licenses, Drive Intelligence data, TrackLab courses, RaceLink profiles, settings, achievements, sessions, crashes, and Android signing compatibility."
        )
    ),
'@
$Text = Replace-Once $Text $OldRelease $NewRelease "Release history correction"
$OldSeen = @'
    val seenKey =
        "seen_release_${BuildConfig.VERSION_CODE}"
'@
$NewSeen = @'
    val seenKey =
        "seen_release_${BuildConfig.VERSION_CODE}_lifecycle_final"
'@
$Text = Replace-Once $Text $OldSeen $NewSeen "Release-note seen-key revision"
Write-Utf8Lf $UpdateUiPath $Text
Write-Host "The undeployed 2.4.1 entry was removed and its real changes were merged into 2.4.0." -ForegroundColor Green

Write-Host ""
Write-Host "===== STATIC VALIDATION =====" -ForegroundColor Cyan
Assert-Contains $StoragePath 'lifecycleReportingEnabled = true,'
Assert-Contains $StoragePath '.putBoolean("lifecycleReportingEnabled", true)'
Assert-Contains $ViewModelPath 'enabled = true,'
Assert-Contains $UiPath 'Core signed lifecycle and reliability intelligence runs automatically.'
Assert-Contains $UiPath 'settings.featureUsageReportingEnabled,'
Assert-Contains $UiPath 'settings.sessionSummarySharingEnabled,'
Assert-Contains $UpdateUiPath 'version = "2.4.0"'
Assert-Contains $UpdateUiPath 'label = "CURRENT RELEASE"'
Assert-Contains $UpdateUiPath 'seen_release_${BuildConfig.VERSION_CODE}_lifecycle_final'
if ((Read-StrictUtf8 $UiPath).Contains('"Device and reliability reporting",')) {
    throw "The removed core lifecycle switch is still present in DriveLabUi.kt."
}
if ((Read-StrictUtf8 $UpdateUiPath).Contains('version = "2.4.1"')) {
    throw "The undeployed 2.4.1 changelog entry is still present."
}
Write-Host "Always-on core reporting, optional controls, privacy text, and corrected changelog markers passed." -ForegroundColor Green

Write-Host ""
Write-Host "===== CONFIGURING JAVA =====" -ForegroundColor Cyan
$AndroidStudioJbr = "C:\Program Files\Android\Android Studio\jbr"
if (-not (Test-Path -LiteralPath (Join-Path $AndroidStudioJbr "bin\java.exe") -PathType Leaf)) {
    throw "Android Studio JBR was not found at ${AndroidStudioJbr}"
}
$env:JAVA_HOME = $AndroidStudioJbr
$env:PATH = "$($env:JAVA_HOME)\bin;$env:PATH"
$JavaCommand = Get-Command java.exe -ErrorAction Stop
Write-Host "JAVA_HOME: $env:JAVA_HOME"
& java.exe -version
if ($LASTEXITCODE -ne 0) {
    throw "Java was found but could not be executed."
}

Write-Host ""
Write-Host "===== BUILDING AND TESTING THE FINAL ISOLATED STAGE =====" -ForegroundColor Cyan
$GradleExit = -1
Push-Location $Stage
try {
    & .\gradlew.bat --no-daemon clean testReleaseUnitTest lintRelease assembleRelease
    $GradleExit = $LASTEXITCODE
}
finally {
    Pop-Location
}
if ($GradleExit -ne 0) {
    throw "Gradle build or tests failed with exit code ${GradleExit}. The original project remains unchanged; stage backups are in ${Backup}."
}

$BuiltApk = Join-Path $Stage "app\build\outputs\apk\release\app-release.apk"
if (-not (Test-Path -LiteralPath $BuiltApk -PathType Leaf)) {
    throw "Gradle completed but the release APK was not found: ${BuiltApk}"
}
$ReleaseOutput = Join-Path $Stage "release-output"
New-Item -ItemType Directory -Force -Path $ReleaseOutput | Out-Null
$FinalApk = Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0-build37-lifecycle-FINAL-STAGE.apk"
Copy-Item -LiteralPath $BuiltApk -Destination $FinalApk -Force
$ApkHash = Get-Sha256 $FinalApk

Write-Host ""
Write-Host "===== VERIFYING APK SIGNATURE AND MANIFEST =====" -ForegroundColor Cyan
$BuildToolsRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk\build-tools"
$ApkSigner = Get-ChildItem -Path $BuildToolsRoot -Filter apksigner.bat -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
$Aapt = Get-ChildItem -Path $BuildToolsRoot -Filter aapt.exe -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if ($null -eq $ApkSigner) {
    throw "apksigner.bat was not found under ${BuildToolsRoot}"
}
if ($null -eq $Aapt) {
    throw "aapt.exe was not found under ${BuildToolsRoot}"
}
& $ApkSigner.FullName verify --verbose --print-certs $FinalApk
if ($LASTEXITCODE -ne 0) {
    throw "APK signature verification failed."
}
$Badging = (& $Aapt.FullName dump badging $FinalApk 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw "aapt could not inspect the staged APK."
}
if ($Badging -notmatch "package: name='com\.auroramediagroup\.drivelab'") {
    throw "The staged APK package name is incorrect."
}
if ($Badging -notmatch "versionCode='37'") {
    throw "The staged APK versionCode is not 37."
}
if ($Badging -notmatch "versionName='2\.4\.0'") {
    throw "The staged APK versionName is not 2.4.0."
}
Write-Host "APK package, version, build number, and signature verification passed." -ForegroundColor Green

Write-Host ""
Write-Host "===== PROVING THE ORIGINAL PROJECT WAS STILL NOT MODIFIED =====" -ForegroundColor Cyan
foreach ($Entry in $Baseline.GetEnumerator()) {
    Assert-OriginalHash $Entry.Key $Entry.Value
}
Write-Host "Original project hashes remain unchanged." -ForegroundColor Green

$ReportLines = @(
    "DRIVELAB 2.4.0 BUILD 37 FINAL LIFECYCLE STAGE"
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "Original project: $Root"
    "Staged project: $Stage"
    "Stage backup: $Backup"
    "Public version: 2.4.0"
    "Version code: 37"
    "APK: $FinalApk"
    "APK SHA-256: $ApkHash"
    ""
    "Passed:"
    "- core lifecycle and reliability intelligence permanently enabled"
    "- core reporting switch removed from Setup"
    "- optional feature usage and session-summary controls preserved"
    "- privacy disclosure corrected"
    "- undeployed 2.4.1 changelog entry removed"
    "- real 2.4.1 work merged into the 2.4.0 current-release notes"
    "- release-note seen key revised"
    "- release unit tests, lint, and APK assembly"
    "- APK signature, package, versionName, and versionCode verification"
    "- original project hashes unchanged"
    ""
    "Not performed:"
    "- APK installation"
    "- original project replacement"
    "- update-server publication"
    "- GitHub release replacement"
    "- public website change"
)
[System.IO.File]::WriteAllLines($Report, $ReportLines, $Utf8NoBom)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "FINAL LIFECYCLE APK BUILT - ORIGINAL PROJECT UNCHANGED" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Final staged APK: $FinalApk"
Write-Host "SHA-256:          $ApkHash"
Write-Host "Report:            $Report"
Write-Host "Stage backup:       $Backup"
Write-Host ""
Write-Host "The final staged APK has not been installed or published." -ForegroundColor Yellow
