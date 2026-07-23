$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Project = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
$JavaHome = "C:\Program Files\Android\Android Studio\jbr"
$Utf8Read = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8Write = [System.Text.UTF8Encoding]::new($false)
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupRoot = Join-Path $Project "backups\before-v2.4.1-inline-full-required-$Timestamp"

$DriveLabUiPath = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\DriveLabUi.kt"
$EditionUiPath = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\EditionUi.kt"
$BuildGradlePath = Join-Path $Project "app\build.gradle.kts"
$ReleaseNotesPath = Join-Path $Project "UPDATE-RELEASE-NOTES.txt"

function Read-Utf8Text {
    param([Parameter(Mandatory)][string]$Path)
    $Text = [System.IO.File]::ReadAllText($Path, $Utf8Read)
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8Write)
}

function Replace-RegexLiteralOnce {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Replacement,
        [Parameter(Mandatory)][string]$Label
    )

    $Regex = [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $Matches = $Regex.Matches($Text)

    if ($Matches.Count -ne 1) {
        throw "$Label expected exactly one source anchor but found $($Matches.Count)."
    }

    $Evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($Match)
        return $Replacement
    }

    return $Regex.Replace($Text, $Evaluator, 1)
}

foreach ($Path in @($DriveLabUiPath, $EditionUiPath, $BuildGradlePath, $ReleaseNotesPath)) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required project file was not found: $Path"
    }
}

$BuildGradle = Read-Utf8Text $BuildGradlePath
if (
    $BuildGradle -notmatch 'versionCode\s*=\s*37' -or
    $BuildGradle -notmatch 'versionName\s*=\s*"2\.4\.1"'
) {
    throw "This correction expects DriveLab 2.4.1 build 37. The project was not changed."
}

$DriveLabUi = Read-Utf8Text $DriveLabUiPath
$EditionUi = Read-Utf8Text $EditionUiPath

if (-not $DriveLabUi.Contains('private fun FullFeaturePreviewHost(')) {
    throw "The current 2.4.1 Full preview host was not found. Run this only after the R5 build shown in your screenshots."
}

if (-not $EditionUi.Contains('fun FullEditionPreviewOverlay(')) {
    throw "The current 2.4.1 Full preview card was not found."
}

$ImportsToAdd = @(
    'import androidx.compose.foundation.gestures.awaitEachGesture',
    'import androidx.compose.foundation.gestures.awaitFirstDown',
    'import androidx.compose.ui.input.pointer.PointerEventPass',
    'import androidx.compose.ui.input.pointer.positionChange'
)

foreach ($Import in $ImportsToAdd) {
    if (-not $DriveLabUi.Contains($Import)) {
        $DriveLabUi = $DriveLabUi.Replace(
            "import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress`n",
            "import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress`n$Import`n"
        )
    }
}

$NewPreviewHost = @'
@Composable
private fun FullFeaturePreviewHost(
    selectedTab: MainTab,
    settings: AppSettings,
    telemetry: TelemetryFrame,
    connection: ConnectionState,
    analyzer: AnalyzerState,
    sessions: List<SessionSummary>,
    crashes: List<CrashIncident>,
    liveHistory: List<LiveTraceSample>,
    progress: DriverProgress,
    lastXpAward: XpAward?,
    phoneAddress: String,
    viewModel: DriveLabViewModel,
    contentPadding: PaddingValues,
    onEnterLicense: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        FullEditionPreviewOverlay(
            featureName = selectedTab.fullEditionName(),
            onEnterLicense = onEnterLicense
        )

        Box(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .weight(1f)
        ) {
            Box(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            alpha = 0.52f
                        }
            ) {
                ResponsivePageFrame {
                    when (selectedTab) {
                        MainTab.COCKPIT ->
                            CockpitScreen(
                                settings,
                                telemetry,
                                connection,
                                analyzer,
                                progress,
                                viewModel,
                                contentPadding
                            )

                        MainTab.RACELINK ->
                            RaceLinkScreen(
                                viewModel,
                                contentPadding
                            )

                        MainTab.ANALYZE ->
                            AnalyzeScreen(
                                settings,
                                telemetry,
                                connection,
                                analyzer,
                                sessions,
                                crashes,
                                liveHistory,
                                progress,
                                lastXpAward,
                                phoneAddress,
                                viewModel,
                                contentPadding
                            )

                        else -> Unit
                    }
                }
            }

            Box(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .pointerInput(selectedTab) {
                            awaitEachGesture {
                                val down =
                                    awaitFirstDown(
                                        requireUnconsumed = false,
                                        pass = PointerEventPass.Initial
                                    )
                                var totalMovement = 0f

                                while (true) {
                                    val event =
                                        awaitPointerEvent(
                                            pass = PointerEventPass.Initial
                                        )
                                    val change =
                                        event.changes.firstOrNull {
                                            it.id == down.id
                                        } ?: break
                                    val delta = change.positionChange()
                                    totalMovement +=
                                        kotlin.math.abs(delta.x) +
                                            kotlin.math.abs(delta.y)

                                    if (!change.pressed) {
                                        if (
                                            totalMovement <
                                            viewConfiguration.touchSlop
                                        ) {
                                            change.consume()
                                        }
                                        break
                                    }
                                }
                            }
                        }
            )
        }
    }
}

'@

$DriveLabUi = Replace-RegexLiteralOnce `
    -Text $DriveLabUi `
    -Pattern '@Composable\s+private\s+fun\s+FullFeaturePreviewHost\(.*?(?=\n@Composable\s+private\s+fun\s+OnboardingScreen\()' `
    -Replacement $NewPreviewHost `
    -Label "Full feature preview host"

$NewInlineCard = @'
@Composable
fun FullEditionPreviewOverlay(
    featureName: String,
    onEnterLicense: () -> Unit
) {
    val context = LocalContext.current
    val description =
        when (featureName) {
            "Cockpit Dashboards" ->
                "The complete Cockpit page is shown below as a disabled preview. DriveLab Full unlocks every layout, gauge, style, and control."

            "RaceLink Multiplayer" ->
                "The complete RaceLink page is shown below as a disabled preview. DriveLab Full unlocks friends, rooms, invitations, chat, and competition tools."

            "Driving Analysis" ->
                "The complete Analyze page is shown below as a disabled preview. DriveLab Full unlocks sessions, graphs, coaching, crash history, achievements, and exports."

            else ->
                "$featureName is shown below as a disabled preview and is available with DriveLab Full."
        }

    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(
                    start = 14.dp,
                    end = 14.dp,
                    top = 24.dp,
                    bottom = 8.dp
                )
                .background(
                    DrivePanel,
                    RoundedCornerShape(18.dp)
                )
                .border(
                    1.dp,
                    DriveCyan.copy(alpha = 0.38f),
                    RoundedCornerShape(18.dp)
                )
                .padding(14.dp),
        verticalArrangement =
            Arrangement.spacedBy(8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement =
                Arrangement.SpaceBetween,
            verticalAlignment =
                androidx.compose.ui.Alignment.CenterVertically
        ) {
            Text(
                text = "FULL EDITION REQUIRED",
                color = DriveAmber,
                fontWeight = FontWeight.Black
            )

            Text(
                text = "FREE PREVIEW",
                color = DriveMuted,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.labelMedium
            )
        }

        Text(
            text = featureName,
            color = Color.White,
            fontWeight = FontWeight.Black,
            style = MaterialTheme.typography.titleMedium
        )

        Text(
            text = description,
            color = Color.White.copy(alpha = 0.84f),
            style = MaterialTheme.typography.bodySmall
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement =
                Arrangement.spacedBy(8.dp)
        ) {
            Button(
                onClick = {
                    if (
                        BuildConfig.LICENSE_PURCHASE_URL
                            .isNotBlank()
                    ) {
                        openEditionPurchaseUrl(
                            context,
                            BuildConfig.LICENSE_PURCHASE_URL
                        )
                    } else {
                        onEnterLicense()
                    }
                },
                modifier = Modifier.weight(1f)
            ) {
                Text("GET FULL VERSION")
            }

            OutlinedButton(
                onClick = onEnterLicense,
                modifier = Modifier.weight(1f)
            ) {
                Text("LICENSE KEY")
            }
        }
    }
}

'@

$EditionUi = Replace-RegexLiteralOnce `
    -Text $EditionUi `
    -Pattern '@Composable\s+fun\s+FullEditionPreviewOverlay\(.*?(?=\n@Composable\s+fun\s+UpgradeFullEditionCard\()' `
    -Replacement $NewInlineCard `
    -Label "Inline Full Edition required card"

$RequiredMarkers = @(
    'FULL EDITION REQUIRED',
    'The complete Cockpit page is shown below as a disabled preview.',
    'alpha = 0.52f',
    'awaitEachGesture',
    'PointerEventPass.Initial'
)

foreach ($Marker in $RequiredMarkers) {
    if (-not ($DriveLabUi.Contains($Marker) -or $EditionUi.Contains($Marker))) {
        throw "Source validation failed before writing: $Marker"
    }
}

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
Copy-Item -LiteralPath $DriveLabUiPath -Destination (Join-Path $BackupRoot "DriveLabUi.kt") -Force
Copy-Item -LiteralPath $EditionUiPath -Destination (Join-Path $BackupRoot "EditionUi.kt") -Force
Copy-Item -LiteralPath $ReleaseNotesPath -Destination (Join-Path $BackupRoot "UPDATE-RELEASE-NOTES.txt") -Force

$ReleaseNotes = @'
DriveLab Telem 2.4.1 - Full feature previews

- Cockpit, Link, and Analyze stay visible with normal bottom-navigation letters
- Replaced the large covering preview popup with a compact inline Full Edition Required card
- The complete Full page remains visible below the card in a lightly grayed state
- Free users can scroll through the preview while controls and buttons remain locked
- Added Get Full Version and License Key actions
- Licensed Full Edition behavior remains unchanged

Install this update directly over the existing DriveLab installation. Do not uninstall first.
'@

$WroteSource = $false
try {
    Write-Host ""
    Write-Host "===== APPLYING INLINE FULL EDITION PREVIEW DESIGN =====" -ForegroundColor Cyan
    Write-Host "The large covering popup will be removed." -ForegroundColor Green
    Write-Host "The real page will stay visible and scrollable below a compact required card." -ForegroundColor Green

    Write-Utf8Text $DriveLabUiPath $DriveLabUi
    Write-Utf8Text $EditionUiPath $EditionUi
    Write-Utf8Text $ReleaseNotesPath ($ReleaseNotes.TrimEnd() + "`n")
    $WroteSource = $true

    $env:JAVA_HOME = $JavaHome
    $env:Path = "$JavaHome\bin;$env:Path"

    Push-Location $Project
    try {
        Write-Host ""
        Write-Host "===== UNIT TESTS, LINT, AND SIGNED RELEASE BUILD =====" -ForegroundColor Cyan
        Write-Host "Do not close this window or press Ctrl+C while Gradle is running." -ForegroundColor Yellow

        & .\gradlew.bat `
            --no-daemon `
            testReleaseUnitTest `
            lintRelease `
            assembleRelease

        if ($LASTEXITCODE -ne 0) {
            throw "Gradle failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }

    $BuiltApk = Join-Path $Project "app\build\outputs\apk\release\app-release.apk"
    if (-not (Test-Path -LiteralPath $BuiltApk)) {
        throw "The signed release APK was not found after Gradle completed: $BuiltApk"
    }

    $ReleaseOutput = Join-Path $Project "release-output"
    New-Item -ItemType Directory -Force -Path $ReleaseOutput | Out-Null
    $NamedApk = Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.1.apk"
    Copy-Item -LiteralPath $BuiltApk -Destination $NamedApk -Force

    $Hash = (Get-FileHash -LiteralPath $NamedApk -Algorithm SHA256).Hash.ToLowerInvariant()

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "DRIVELAB 2.4.1 INLINE PREVIEW BUILD COMPLETE" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "APK:     $NamedApk"
    Write-Host "SHA-256: $Hash"
    Write-Host "Backup:  $BackupRoot"

    $Adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path -LiteralPath $Adb) {
        $ConnectedDevices = & $Adb devices | Select-String -Pattern "\tdevice$"
        if ($ConnectedDevices) {
            Write-Host ""
            Write-Host "===== INSTALLING ON CONNECTED ANDROID DEVICE =====" -ForegroundColor Cyan
            & $Adb install -r $NamedApk
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "The APK built successfully, but ADB installation failed. Install it manually from release-output."
            }
        } else {
            Write-Host "No authorized Android device was connected. The APK was not installed automatically." -ForegroundColor Yellow
        }
    }
}
catch {
    if ($WroteSource) {
        Write-Host ""
        Write-Host "PATCH OR BUILD FAILED - RESTORING SOURCE BACKUP" -ForegroundColor Red
        Copy-Item -LiteralPath (Join-Path $BackupRoot "DriveLabUi.kt") -Destination $DriveLabUiPath -Force
        Copy-Item -LiteralPath (Join-Path $BackupRoot "EditionUi.kt") -Destination $EditionUiPath -Force
        Copy-Item -LiteralPath (Join-Path $BackupRoot "UPDATE-RELEASE-NOTES.txt") -Destination $ReleaseNotesPath -Force
        Write-Host "The previous DriveLab 2.4.1 source was restored." -ForegroundColor Yellow
    }
    throw
}
