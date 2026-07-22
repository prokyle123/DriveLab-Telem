param([string]$ProjectPath = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PatchRoot = $PSScriptRoot
$PayloadRoot = Join-Path $PatchRoot "payload"
$FragmentsRoot = Join-Path $PatchRoot "fragments"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:BackupRoot = $null
$script:ProjectRoot = $null
$script:ChangedFiles = @(
    "app\build.gradle.kts",
    "CHANGELOG.md",
    "UPDATE-RELEASE-NOTES.txt",
    "app\src\main\java\com\auroramediagroup\drivelab\Achievements.kt",
    "app\src\main\java\com\auroramediagroup\drivelab\AchievementRuntime.kt",
    "app\src\main\java\com\auroramediagroup\drivelab\DriveLabUi.kt",
    "app\src\main\java\com\auroramediagroup\drivelab\DriveLabViewModel.kt",
    "app\src\main\java\com\auroramediagroup\drivelab\LiveProgression.kt",
    "app\src\main\java\com\auroramediagroup\drivelab\Models.kt",
    "app\src\main\java\com\auroramediagroup\drivelab\Storage.kt",
    "app\src\test\java\com\auroramediagroup\drivelab\AchievementCatalogTest.kt",
    "app\src\test\java\com\auroramediagroup\drivelab\AchievementRuntimeTest.kt"
)

function Read-Normalized([string]$Path) {
    ([System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
}

function Write-Utf8([string]$Path, [string]$Text) {
    $parent = Split-Path $Path -Parent
    if ($parent -and !(Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $Utf8NoBom)
}

function Replace-Exact([string]$Path, [string]$Old, [string]$New, [string]$Label) {
    $text = Read-Normalized $Path
    $oldText = $Old -replace "`r`n", "`n"
    $newText = $New -replace "`r`n", "`n"
    $count = ([regex]::Matches($text, [regex]::Escape($oldText))).Count
    if ($count -ne 1) {
        throw "$Label expected one match in $Path but found $count."
    }
    Write-Utf8 $Path ($text.Replace($oldText, $newText))
}

function Replace-RegexOne([string]$Path, [string]$Pattern, [string]$Replacement, [string]$Label) {
    $text = Read-Normalized $Path
    $regex = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $count = $regex.Matches($text).Count
    if ($count -ne 1) {
        throw "$Label expected one match in $Path but found $count."
    }
    $result = $regex.Replace(
        $text,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $Replacement },
        1
    )
    Write-Utf8 $Path $result
}

function Find-DriveLabProject([string]$Requested) {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Requested) {
        $candidates.Add((Resolve-Path $Requested).Path)
    }
    $candidates.Add((Get-Location).Path)
    $known = "$env:USERPROFILE\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
    if (Test-Path $known) { $candidates.Add($known) }

    $roots = @(
        "$env:USERPROFILE\OneDrive\Desktop",
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Documents",
        "$env:USERPROFILE\Downloads"
    ) | Where-Object { Test-Path $_ } | Select-Object -Unique

    foreach ($root in $roots) {
        Get-ChildItem $root -Filter gradlew.bat -File -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $candidates.Add($_.Directory.FullName) }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $gradle = Join-Path $candidate "app\build.gradle.kts"
        if (!(Test-Path $gradle)) { continue }
        $text = Read-Normalized $gradle
        if (
            $text.Contains('applicationId = "com.auroramediagroup.drivelab"') -and
            $text.Contains('versionName = "2.2.1"')
        ) {
            return $candidate
        }
    }
    throw "DriveLab 2.2.1 was not found. Pass -ProjectPath or run from the current project."
}

function Backup-ChangedFiles {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:BackupRoot = Join-Path $script:ProjectRoot "backups\achievement-vault-v2.3.0-r1-$stamp"
    New-Item -ItemType Directory -Path $script:BackupRoot -Force | Out-Null
    $absent = New-Object System.Collections.Generic.List[string]
    foreach ($relative in $script:ChangedFiles) {
        $source = Join-Path $script:ProjectRoot $relative
        $destination = Join-Path $script:BackupRoot $relative
        if (Test-Path $source) {
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item $source $destination -Force
        } else {
            $absent.Add($relative)
        }
    }
    $absent | Set-Content (Join-Path $script:BackupRoot "ABSENT-BEFORE-PATCH.txt") -Encoding UTF8
    Write-Host "Backup: $script:BackupRoot" -ForegroundColor DarkGray
}

function Restore-Backup {
    if (!$script:BackupRoot -or !(Test-Path $script:BackupRoot)) { return }
    $absentPath = Join-Path $script:BackupRoot "ABSENT-BEFORE-PATCH.txt"
    $absent = if (Test-Path $absentPath) { @(Get-Content $absentPath) } else { @() }
    foreach ($relative in $script:ChangedFiles) {
        $target = Join-Path $script:ProjectRoot $relative
        $backup = Join-Path $script:BackupRoot $relative
        if (Test-Path $backup) {
            New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
            Copy-Item $backup $target -Force
        } elseif ($relative -in $absent -and (Test-Path $target)) {
            Remove-Item $target -Force
        }
    }
    Write-Host "Source restored from backup." -ForegroundColor Yellow
}

function Copy-PayloadFile([string]$Relative) {
    $source = Join-Path $PayloadRoot $Relative
    $destination = Join-Path $script:ProjectRoot $Relative
    if (!(Test-Path $source)) { throw "Patch payload missing: $source" }
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item $source $destination -Force
}

try {
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "DriveLab 2.3.0 - Achievement Vault Rebuilt" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $script:ProjectRoot = Find-DriveLabProject $ProjectPath
    Write-Host "Project: $script:ProjectRoot" -ForegroundColor Green

    $required = @(
        "gradlew.bat",
        "app\src\main\java\com\auroramediagroup\drivelab\Achievements.kt",
        "app\src\main\java\com\auroramediagroup\drivelab\DriveLabUi.kt",
        "app\src\main\java\com\auroramediagroup\drivelab\DriveLabViewModel.kt",
        "app\src\main\java\com\auroramediagroup\drivelab\LiveProgression.kt",
        "app\src\main\java\com\auroramediagroup\drivelab\Models.kt",
        "app\src\main\java\com\auroramediagroup\drivelab\Storage.kt"
    )
    foreach ($relative in $required) {
        if (!(Test-Path (Join-Path $script:ProjectRoot $relative))) {
            throw "Required project file missing: $relative"
        }
    }
    if (!(Test-Path (Join-Path $script:ProjectRoot "keystore.properties"))) {
        throw "keystore.properties is missing; permanent release signing is required."
    }

    Backup-ChangedFiles

    Write-Host "[1/9] Installing catalog and live rule engine..." -ForegroundColor Cyan
    Copy-PayloadFile "app\src\main\java\com\auroramediagroup\drivelab\Achievements.kt"
    Copy-PayloadFile "app\src\main\java\com\auroramediagroup\drivelab\AchievementRuntime.kt"
    $runtimePath = Join-Path $script:ProjectRoot "app\src\main\java\com\auroramediagroup\drivelab\AchievementRuntime.kt"

    Replace-Exact $runtimePath `
        '        maxValue(AchievementMetric.BEST_SHIFT_SCORE, analyzer.shift.score.toDouble())' `
        '        if (analyzer.shift.totalShifts > 0) maxValue(AchievementMetric.BEST_SHIFT_SCORE, analyzer.shift.score.toDouble())' `
        "Guard default shift score"
    Replace-Exact $runtimePath `
        '        updateDrift(now, speedMph, driftAngle, throttle, brake, totalG, analyzer)' `
        '        updateDrift(now, dt, speedMph, driftAngle, throttle, brake, totalG, analyzer)' `
        "Pass drift packet time"
    Replace-Exact $runtimePath `
        '        updateCrashes(now, speedMph, analyzer)' `
        '        updateCrashes(now, dt, speedMph, analyzer)' `
        "Pass post-impact packet time"

    $old = @'
    private fun updateDrift(
        now: Long,
        speedMph: Double,
'@
    $new = @'
    private fun updateDrift(
        now: Long,
        dt: Double,
        speedMph: Double,
'@
    Replace-Exact $runtimePath $old $new "Add drift packet-time parameter"
    Replace-Exact $runtimePath '            driftStreak += 0.0.coerceAtLeast(0.0)' '            driftStreak += dt' "Accumulate drift duration"
    Replace-Exact $runtimePath '                rightDriftStreak += 0.0' '                rightDriftStreak += dt' "Accumulate right drift"
    Replace-Exact $runtimePath '                leftDriftStreak += 0.0' '                leftDriftStreak += dt' "Accumulate left drift"

    $old = @'
            } else if (sign < 0) {
                leftDriftStreak += dt
                rightDriftStreak = 0.0
            }
            if (lastDriftSign != 0 && sign != 0 && sign != lastDriftSign && now - lastTransitionAtMs >= 750L) {
'@
    $new = @'
            } else if (sign < 0) {
                leftDriftStreak += dt
                rightDriftStreak = 0.0
            }
            maxValue(AchievementMetric.BEST_DRIFT_DURATION, driftStreak)
            maxValue(AchievementMetric.LONGEST_LEFT_DRIFT_SECONDS, leftDriftStreak)
            maxValue(AchievementMetric.LONGEST_RIGHT_DRIFT_SECONDS, rightDriftStreak)
            if (lastDriftSign != 0 && sign != 0 && sign != lastDriftSign && now - lastTransitionAtMs >= 750L) {
'@
    Replace-Exact $runtimePath $old $new "Store drift streaks"
    Replace-Exact $runtimePath `
        '    private fun updateCrashes(now: Long, speedMph: Double, analyzer: AnalyzerState) {' `
        '    private fun updateCrashes(now: Long, dt: Double, speedMph: Double, analyzer: AnalyzerState) {' `
        "Add post-impact packet-time parameter"

    $old = @'
                postCrashStreak += 0.0.coerceAtLeast(0.0)
                val elapsedSeconds = (now - crashAtMs).coerceAtLeast(0L) / 1000.0
                maxValue(AchievementMetric.LONGEST_POST_CRASH_SECONDS, elapsedSeconds)
'@
    $new = @'
                postCrashStreak += dt
                val elapsedSeconds = (now - crashAtMs).coerceAtLeast(0L) / 1000.0
                maxValue(AchievementMetric.LONGEST_POST_CRASH_SECONDS, max(postCrashStreak, elapsedSeconds))
'@
    Replace-Exact $runtimePath $old $new "Accumulate post-impact drive time"

    Write-Host "[2/9] Expanding progression models..." -ForegroundColor Cyan
    $modelsPath = Join-Path $script:ProjectRoot "app\src\main\java\com\auroramediagroup\drivelab\Models.kt"
    $old = @'
    val brakeRuns: Int = 0,
    val totalCrashes: Int = 0,
    val achievements: Set<String> = emptySet()
'@
    $new = @'
    val brakeRuns: Int = 0,
    val totalCrashes: Int = 0,
    val legacyAchievementCount: Int = 0,
    val achievementStats: Map<String, Double> = emptyMap(),
    val achievements: Set<String> = emptySet()
'@
    Replace-Exact $modelsPath $old $new "Expand DriverProgress"

    $old = @'
    val quarterMileRuns: Int = 0,
    val brakeRuns: Int = 0,
    val crashes: Int = 0
'@
    $new = @'
    val quarterMileRuns: Int = 0,
    val brakeRuns: Int = 0,
    val crashes: Int = 0,
    val achievementStats: Map<String, Double> = emptyMap()
'@
    Replace-Exact $modelsPath $old $new "Expand LiveProgressDelta"

    Write-Host "[3/9] Connecting live telemetry..." -ForegroundColor Cyan
    $livePath = Join-Path $script:ProjectRoot "app\src\main\java\com\auroramediagroup\drivelab\LiveProgression.kt"
    $new = @'
class LiveProgressTracker {
    private val achievementRuntime = AchievementRuntime()
'@
    Replace-Exact $livePath 'class LiveProgressTracker {' $new "Create achievement runtime"

    $old = @'
        previousTopSpeedBucket = floor(progress.topSpeedMph / 5.0).toInt()
        ready = true
'@
    $new = @'
        previousTopSpeedBucket = floor(progress.topSpeedMph / 5.0).toInt()
        achievementRuntime.sync(progress, analyzer)
        ready = true
'@
    Replace-Exact $livePath $old $new "Synchronize achievement runtime"
    Replace-Exact $livePath `
        '    fun update(frame: TelemetryFrame, analyzer: AnalyzerState): LiveProgressDelta? {' `
        '    fun update(frame: TelemetryFrame, analyzer: AnalyzerState, redlineRpm: Int = 7000): LiveProgressDelta? {' `
        "Pass configured redline"

    $old = @'
        lastCrashId = crashId
        driveAbuseDelta = max(driveAbuseDelta, (analyzer.engine.abuseScore - driveStartAbuse).coerceAtLeast(0))

        val eventPending = pendingShifts > 0 || pendingQuarterRuns > 0 || pendingBrakeRuns > 0 || pendingCrashes > 0 || pendingCompletedDrives > 0
'@
    $new = @'
        lastCrashId = crashId
        driveAbuseDelta = max(driveAbuseDelta, (analyzer.engine.abuseScore - driveStartAbuse).coerceAtLeast(0))
        achievementRuntime.update(frame, analyzer, dt, redlineRpm, activeDrive)

        val eventPending = pendingShifts > 0 || pendingQuarterRuns > 0 || pendingBrakeRuns > 0 || pendingCrashes > 0 || pendingCompletedDrives > 0
'@
    Replace-Exact $livePath $old $new "Evaluate live challenge rules"

    $old = @'
    private fun finishDrive(analyzer: AnalyzerState) {
        if (!activeDrive) return
        activeDrive = false
'@
    $new = @'
    private fun finishDrive(analyzer: AnalyzerState) {
        if (!activeDrive) return
        achievementRuntime.finishDrive(analyzer)
        activeDrive = false
'@
    Replace-Exact $livePath $old $new "Evaluate complete-drive challenges"

    $old = @'
            quarterMileRuns = pendingQuarterRuns,
            brakeRuns = pendingBrakeRuns,
            crashes = pendingCrashes
'@
    $new = @'
            quarterMileRuns = pendingQuarterRuns,
            brakeRuns = pendingBrakeRuns,
            crashes = pendingCrashes,
            achievementStats = achievementRuntime.snapshot()
'@
    Replace-Exact $livePath $old $new "Persist challenge statistics"

    $viewModelPath = Join-Path $script:ProjectRoot "app\src\main\java\com\auroramediagroup\drivelab\DriveLabViewModel.kt"
    $old = @'
                                .update(
                                    frame,
                                    analyzer.state.value
                                )
'@
    $new = @'
                                .update(
                                    frame,
                                    analyzer.state.value,
                                    _settings.value.redlineRpm
                                )
'@
    Replace-Exact $viewModelPath $old $new "Connect redline to live challenge engine"

    Write-Host "[4/9] Installing migration and persistent statistics..." -ForegroundColor Cyan
    $storagePath = Join-Path $script:ProjectRoot "app\src\main\java\com\auroramediagroup\drivelab\Storage.kt"
    $storeFragment = (Read-Normalized (Join-Path $FragmentsRoot "ProgressStoreV2.kt.txt")).TrimEnd()
    $storeReplacement = $storeFragment + "`n`nprivate fun android.content.SharedPreferences.getStoredDouble"
    $pattern = 'class ProgressStore\(context: Context\) \{.*?\n\}\n\nprivate fun android\.content\.SharedPreferences\.getStoredDouble'
    Replace-RegexOne $storagePath $pattern $storeReplacement "Replace ProgressStore"

    Write-Host "[5/9] Rebuilding Achievement Vault UI..." -ForegroundColor Cyan
    $uiPath = Join-Path $script:ProjectRoot "app\src\main\java\com\auroramediagroup\drivelab\DriveLabUi.kt"
    $uiFragment = (Read-Normalized (Join-Path $FragmentsRoot "AchievementsScreenV2.kt.txt")).TrimEnd()
    $uiReplacement = $uiFragment + "`n`n@Composable`nprivate fun DriverCoachScreen"
    $pattern = '@Composable\nprivate fun AchievementsScreen\(progress: DriverProgress\) \{.*?\n\}\n\n@Composable\nprivate fun DriverCoachScreen'
    Replace-RegexOne $uiPath $pattern $uiReplacement "Replace Achievement Vault screen"
    Replace-Exact $uiPath `
        'Tiered milestones cover speed, distance, drives, drift, clean driving, shifts, drag runs, braking, and impacts.' `
        '1,001 distinct challenges use live telemetry, combinations, streaks, recoveries, and secret goals.' `
        "Update achievement summary"

    Write-Host "[6/9] Installing tests and release metadata..." -ForegroundColor Cyan
    Copy-PayloadFile "app\src\test\java\com\auroramediagroup\drivelab\AchievementCatalogTest.kt"
    Copy-PayloadFile "app\src\test\java\com\auroramediagroup\drivelab\AchievementRuntimeTest.kt"
    Copy-PayloadFile "UPDATE-RELEASE-NOTES.txt"

    $gradlePath = Join-Path $script:ProjectRoot "app\build.gradle.kts"
    Replace-Exact $gradlePath '        versionCode = 34' '        versionCode = 35' "Bump version code"
    Replace-Exact $gradlePath '        versionName = "2.2.1"' '        versionName = "2.3.0"' "Bump version name"

    $changelogPath = Join-Path $script:ProjectRoot "CHANGELOG.md"
    $changelog = @'
# DriveLab Telem Changelog

## 2.3.0

- Replaced the original tier-heavy catalog with 1,000 distinct driving challenges and the final DriveLab Legend achievement.
- Added automatic live tracking for combinations, streaks, recoveries, full-drive goals, secret challenges, and unusual driving behavior.
- Added Common, Skilled, Expert, Extreme, Insane, and Legendary rarity levels.
- Preserved XP, levels, specialties, statistics, records, licenses, TrackLab, Auto Co-Driver, RaceLink, sessions, crashes, and permanent Android signing compatibility.
- Preserved the previous unlocked-achievement count as a Legacy Vault record with Original Driver recognition.
'@
    Replace-Exact $changelogPath '# DriveLab Telem Changelog' $changelog.TrimEnd() "Add 2.3.0 changelog"

    Write-Host "[7/9] Running unit tests, release lint, and signed build..." -ForegroundColor Cyan
    $javaCandidates = @(
        @($env:JAVA_HOME, "C:\Program Files\Android\Android Studio\jbr", "C:\Program Files\Android\Android Studio\jre") |
            Where-Object { $_ -and (Test-Path (Join-Path $_ "bin\java.exe")) }
    )
    if ($javaCandidates.Count -gt 0) { $env:JAVA_HOME = $javaCandidates[0] }

    Push-Location $script:ProjectRoot
    try {
        $log = Join-Path $script:BackupRoot "BUILD-2.3.0.log"
        & .\gradlew.bat --no-daemon clean testDebugUnitTest lintRelease assembleRelease --stacktrace 2>&1 |
            Tee-Object -FilePath $log
        if ($LASTEXITCODE -ne 0) { throw "Gradle verification failed. See $log" }
    } finally {
        Pop-Location
    }

    Write-Host "[8/9] Verifying permanent APK signature..." -ForegroundColor Cyan
    $apk = Get-ChildItem (Join-Path $script:ProjectRoot "app\build\outputs\apk\release") -Filter *.apk -File -ErrorAction Stop |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (!$apk) { throw "Release APK was not created." }

    $sdkRoot = $null
    $localProperties = Join-Path $script:ProjectRoot "local.properties"
    if (Test-Path $localProperties) {
        $sdkLine = Get-Content $localProperties | Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
        if ($sdkLine) {
            $sdkRoot = ($sdkLine -replace '^sdk\.dir=', '') -replace '\\\\', '\'
        }
    }
    if (!$sdkRoot) { $sdkRoot = "$env:LOCALAPPDATA\Android\Sdk" }

    $apksigner = Get-ChildItem (Join-Path $sdkRoot "build-tools") -Filter apksigner.bat -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (!$apksigner) { throw "apksigner.bat was not found under $sdkRoot\build-tools." }
    & $apksigner.FullName verify --verbose --print-certs $apk.FullName
    if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed." }

    $sha = (Get-FileHash $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $desktop = "$env:USERPROFILE\OneDrive\Desktop"
    if (!(Test-Path $desktop)) { $desktop = "$env:USERPROFILE\Desktop" }
    $outputApk = Join-Path $desktop "DriveLab-Telem-v2.3.0-Achievement-Vault.apk"
    Copy-Item $apk.FullName $outputApk -Force
    Set-Content "$outputApk.sha256.txt" "$sha  $(Split-Path $outputApk -Leaf)" -Encoding ASCII

    Write-Host "[9/9] Installing on one connected Android device when available..." -ForegroundColor Cyan
    $adb = Join-Path $sdkRoot "platform-tools\adb.exe"
    if (Test-Path $adb) {
        $devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "`tdevice$" })
        if ($devices.Count -eq 1) {
            & $adb install -r $outputApk
            if ($LASTEXITCODE -ne 0) { throw "APK built and signed, but ADB installation failed." }
            Write-Host "Installed over the current DriveLab app." -ForegroundColor Green
        } else {
            Write-Host "ADB install skipped: connect exactly one authorized device." -ForegroundColor Yellow
        }
    } else {
        Write-Host "ADB install skipped: adb.exe was not found." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "DRIVELAB 2.3.0 BUILD PASSED" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "APK: $outputApk" -ForegroundColor Cyan
    Write-Host "SHA-256: $sha" -ForegroundColor Cyan
    Write-Host "Backup: $script:BackupRoot" -ForegroundColor DarkGray
    Write-Host "Nothing was published. Complete live Free and Full testing before release." -ForegroundColor Yellow
}
catch {
    Write-Host ""
    Write-Host "PATCH OR BUILD FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Restore-Backup
    Write-Host "No customer update was published." -ForegroundColor Yellow
    exit 1
}
