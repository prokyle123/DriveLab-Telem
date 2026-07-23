$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Project = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
$JavaHome = "C:\Program Files\Android\Android Studio\jbr"
$Utf8Read = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8Write = [System.Text.UTF8Encoding]::new($false)
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupRoot = Join-Path $Project "backups\before-v2.4.1-grayed-full-previews-$Timestamp"

$Paths = [ordered]@{
    DriveLabUi = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\DriveLabUi.kt"
    EditionUi = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\EditionUi.kt"
    UpdateUi = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\UpdateUi.kt"
    BuildGradle = Join-Path $Project "app\build.gradle.kts"
    Changelog = Join-Path $Project "CHANGELOG.md"
    ReleaseNotes = Join-Path $Project "UPDATE-RELEASE-NOTES.txt"
}

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

function Replace-ExactOnce {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Old,
        [Parameter(Mandatory)][string]$New,
        [Parameter(Mandatory)][string]$Label
    )
    $Count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($Count -ne 1) {
        throw "$Label expected exactly one source anchor but found $Count."
    }
    return $Text.Replace($Old, $New)
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

function Find-MatchingParenthesis {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$OpenIndex
    )
    $Depth = 0
    $InString = $false
    $InChar = $false
    $Escaped = $false

    for ($Index = $OpenIndex; $Index -lt $Text.Length; $Index++) {
        $Character = $Text[$Index]

        if ($Escaped) {
            $Escaped = $false
            continue
        }

        if ($InString) {
            if ($Character -eq '\') {
                $Escaped = $true
            } elseif ($Character -eq '"') {
                $InString = $false
            }
            continue
        }

        if ($InChar) {
            if ($Character -eq '\') {
                $Escaped = $true
            } elseif ($Character -eq "'") {
                $InChar = $false
            }
            continue
        }

        if ($Character -eq '"') {
            $InString = $true
            continue
        }

        if ($Character -eq "'") {
            $InChar = $true
            continue
        }

        if ($Character -eq '(') {
            $Depth++
        } elseif ($Character -eq ')') {
            $Depth--
            if ($Depth -eq 0) {
                return $Index
            }
        }
    }

    throw "Could not find the closing parenthesis for the custom navigation item."
}

foreach ($Entry in $Paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $Entry.Value)) {
        throw "Required project file was not found: $($Entry.Value)"
    }
}

$DriveLabUi = Read-Utf8Text $Paths.DriveLabUi
$EditionUi = Read-Utf8Text $Paths.EditionUi
$UpdateUi = Read-Utf8Text $Paths.UpdateUi
$BuildGradle = Read-Utf8Text $Paths.BuildGradle
$Changelog = Read-Utf8Text $Paths.Changelog

$Is240 =
    $BuildGradle -match 'versionCode\s*=\s*36' -and
    $BuildGradle -match 'versionName\s*=\s*"2\.4\.0"'

$Is241 =
    $BuildGradle -match 'versionCode\s*=\s*37' -and
    $BuildGradle -match 'versionName\s*=\s*"2\.4\.1"'

if (-not $Is240 -and -not $Is241) {
    throw "Expected DriveLab 2.4.0 build 36 or the draft 2.4.1 build 37. The project was not changed."
}

# Restore the normal bottom navigation if the earlier locked-icon draft was applied.
$OriginalNavigationItem = @'
NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        icon = { Text(symbol, fontWeight = FontWeight.Black) },
                        label = { Text(label, maxLines = 1) }
                    )
'@

if ($DriveLabUi.Contains('NavigationBarItemDefaults.colors')) {
    $MarkerIndex = $DriveLabUi.IndexOf('NavigationBarItemDefaults.colors')
    $NavigationStart = $DriveLabUi.LastIndexOf('NavigationBarItem(', $MarkerIndex)
    if ($NavigationStart -lt 0) {
        throw "The custom locked navigation item could not be isolated."
    }

    $OpenParenthesis = $DriveLabUi.IndexOf('(', $NavigationStart)
    $NavigationEnd = Find-MatchingParenthesis -Text $DriveLabUi -OpenIndex $OpenParenthesis
    $DriveLabUi =
        $DriveLabUi.Substring(0, $NavigationStart) +
        $OriginalNavigationItem.TrimEnd() +
        $DriveLabUi.Substring($NavigationEnd + 1)
}

$DriveLabUi = [regex]::Replace(
    $DriveLabUi,
    '(?m)^\s*val\s+locked\s*=\s*tab\.requiresFullEdition\(\)\s*&&\s*!licenseState\.fullFeaturesUnlocked\s*\n',
    ''
)

$DriveLabUi = $DriveLabUi.Replace(
    "import androidx.compose.material3.NavigationBarItemDefaults`n",
    ''
)

if (-not $DriveLabUi.Contains($OriginalNavigationItem.Trim())) {
    throw "The normal letter-based bottom navigation could not be verified."
}

$PreviewHost = @'
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
    Box(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier =
                Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        alpha = 0.38f
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
                    .zIndex(1f)
                    .pointerInput(selectedTab) {
                        awaitPointerEventScope {
                            while (true) {
                                val event =
                                    awaitPointerEvent(
                                        pass =
                                            androidx.compose.ui.input.pointer
                                                .PointerEventPass.Initial
                                    )
                                event.changes.forEach { change ->
                                    change.consume()
                                }
                            }
                        }
                    }
        )

        Box(
            modifier =
                Modifier
                    .align(Alignment.TopCenter)
                    .padding(horizontal = 18.dp, vertical = 22.dp)
                    .zIndex(2f)
        ) {
            FullEditionPreviewOverlay(
                featureName = selectedTab.fullEditionName(),
                onEnterLicense = onEnterLicense
            )
        }
    }
}

'@

if (-not $DriveLabUi.Contains('private fun FullFeaturePreviewHost(')) {
    $DriveLabUi = Replace-ExactOnce `
        -Text $DriveLabUi `
        -Old "@Composable`nprivate fun OnboardingScreen(" `
        -New ($PreviewHost + "@Composable`nprivate fun OnboardingScreen(") `
        -Label "Preview host insertion"
}

$OldLockedCallPattern = 'FullEditionLockedScreen\(\s*featureName\s*=\s*selectedTab\.fullEditionName\(\),\s*contentPadding\s*=\s*padding,\s*onUpgrade\s*=\s*\{\s*selectedTab\s*=\s*MainTab\.SETUP\s*\}\s*\)'
$NewPreviewCall = @'
FullFeaturePreviewHost(
                selectedTab = selectedTab,
                settings = settings,
                telemetry = telemetry,
                connection = connection,
                analyzer = analyzer,
                sessions = sessions,
                crashes = crashes,
                liveHistory = liveHistory,
                progress = progress,
                lastXpAward = lastXpAward,
                phoneAddress = phoneAddress,
                viewModel = viewModel,
                contentPadding = padding,
                onEnterLicense = {
                    selectedTab = MainTab.SETUP
                }
            )
'@

if ($DriveLabUi -match 'FullEditionLockedScreen\(') {
    $DriveLabUi = Replace-RegexLiteralOnce `
        -Text $DriveLabUi `
        -Pattern $OldLockedCallPattern `
        -Replacement $NewPreviewCall.TrimEnd() `
        -Label "Locked page replacement"
}

$NewPreviewOverlay = @'
@Composable
fun FullEditionPreviewOverlay(
    featureName: String,
    onEnterLicense: () -> Unit
) {
    val context = LocalContext.current
    val description =
        when (featureName) {
            "Cockpit Dashboards" ->
                "Preview custom cockpit layouts, advanced gauges, live vehicle details, dashboard styles, and configurable telemetry panels."

            "RaceLink Multiplayer" ->
                "Preview friend connections, private race rooms, invitations, room chat, run comparisons, and DriveLab competition tools."

            "Driving Analysis" ->
                "Preview saved drives, graphs, crash records, coaching, achievements, history, and detailed session analysis."

            else ->
                "$featureName and every advanced DriveLab tool are included with the Full Edition."
        }

    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .background(
                    DrivePanel.copy(alpha = 0.97f),
                    RoundedCornerShape(18.dp)
                )
                .border(
                    1.dp,
                    DriveAmber.copy(alpha = 0.42f),
                    RoundedCornerShape(18.dp)
                )
                .padding(15.dp),
        verticalArrangement =
            Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement =
                Arrangement.SpaceBetween
        ) {
            Text(
                text = "FULL VERSION PREVIEW",
                color = DriveAmber,
                fontWeight = FontWeight.Black
            )

            Text(
                text = "FREE EDITION",
                color = DriveMuted,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.labelMedium
            )
        }

        Text(
            text = featureName,
            color = Color.White,
            fontWeight = FontWeight.Black,
            style = MaterialTheme.typography.titleLarge
        )

        Text(
            text = description,
            color = Color.White.copy(alpha = 0.90f),
            style = MaterialTheme.typography.bodyMedium
        )

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
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("GET FULL VERSION")
        }

        OutlinedButton(
            onClick = onEnterLicense,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("ENTER LICENSE KEY")
        }

        Text(
            text = "The page below is a disabled preview. One permanent license unlocks every Full feature with no subscription.",
            color = DriveMuted,
            textAlign = TextAlign.Center,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

'@

$OverlayFunctionPattern = '@Composable\s+fun\s+FullEdition(?:LockedScreen|PreviewOverlay)\(.*?(?=\n@Composable\s+fun\s+UpgradeFullEditionCard\()'
$EditionUi = Replace-RegexLiteralOnce `
    -Text $EditionUi `
    -Pattern $OverlayFunctionPattern `
    -Replacement $NewPreviewOverlay `
    -Label "Full Edition preview overlay"

if ($Is240) {
    $BuildGradle = Replace-RegexLiteralOnce `
        -Text $BuildGradle `
        -Pattern 'versionCode\s*=\s*36' `
        -Replacement 'versionCode = 37' `
        -Label "Android versionCode"

    $BuildGradle = Replace-RegexLiteralOnce `
        -Text $BuildGradle `
        -Pattern 'versionName\s*=\s*"2\.4\.0"' `
        -Replacement 'versionName = "2.4.1"' `
        -Label "Android versionName"
}

$NewReleaseEntry = @'
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
    ),
'@

if ($UpdateUi -match 'version\s*=\s*"2\.4\.1"') {
    $UpdateUi = Replace-RegexLiteralOnce `
        -Text $UpdateUi `
        -Pattern '(?m)^    ReleaseEntry\(\s*version\s*=\s*"2\.4\.1",.*?^    \),\s*\n' `
        -Replacement $NewReleaseEntry `
        -Label "Existing 2.4.1 release entry"
} else {
    $UpdateUi = Replace-RegexLiteralOnce `
        -Text $UpdateUi `
        -Pattern '(version\s*=\s*"2\.4\.0",\s*label\s*=\s*)"CURRENT RELEASE"' `
        -Replacement '$1"PREVIOUS RELEASE"' `
        -Label "2.4.0 release-history label"

    $UpdateUi = Replace-ExactOnce `
        -Text $UpdateUi `
        -Old "private val ReleaseHistory = listOf(`n" `
        -New ("private val ReleaseHistory = listOf(`n" + $NewReleaseEntry) `
        -Label "Release-history insertion"
}

$NewChangelogSection = @'
## 2.4.1

- Kept Cockpit, Link, and Analyze visible in Free Edition with normal bottom-navigation letters.
- Shows the real Full pages dimmed and disabled instead of replacing them with a separate locked page.
- Added compact Full Version Preview cards for Cockpit, RaceLink, and Analyze.
- Added Get Full Version and Enter License Key actions.
- Preserved licensed Full Edition behavior, user data, and Android signing compatibility.

'@

if ($Changelog -match '(?m)^##\s+2\.4\.1\s*$') {
    $Changelog = Replace-RegexLiteralOnce `
        -Text $Changelog `
        -Pattern '(?m)^##\s+2\.4\.1\s*\n.*?(?=^##\s+|\z)' `
        -Replacement $NewChangelogSection `
        -Label "Existing 2.4.1 changelog section"
} else {
    $Changelog = Replace-ExactOnce `
        -Text $Changelog `
        -Old "# DriveLab Telem Changelog`n`n" `
        -New ("# DriveLab Telem Changelog`n`n" + $NewChangelogSection) `
        -Label "Changelog title"
}

$ReleaseNotes = @'
DriveLab Telem 2.4.1 - Full feature previews

- Cockpit, Link, and Analyze stay visible with normal bottom-navigation letters
- Free Edition shows the real Full pages dimmed and disabled
- Compact preview cards explain what each Full section provides
- Added Get Full Version and Enter License Key actions
- Licensed Full Edition behavior remains unchanged
- Preserved licenses, Drive Intelligence data, sessions, achievements, TrackLab courses, RaceLink profiles, settings, and signing compatibility

Install this update directly over the existing DriveLab installation. Do not uninstall first.
'@

$ValidationMarkers = @(
    'private fun FullFeaturePreviewHost(',
    'alpha = 0.38f',
    'FullEditionPreviewOverlay(',
    'FULL VERSION PREVIEW',
    'GET FULL VERSION',
    'ENTER LICENSE KEY'
)

foreach ($Marker in $ValidationMarkers) {
    if (-not ($DriveLabUi.Contains($Marker) -or $EditionUi.Contains($Marker))) {
        throw "Final source validation failed: $Marker"
    }
}

if ($DriveLabUi.Contains('NavigationBarItemDefaults.colors')) {
    throw "The old locked bottom-navigation styling is still present."
}

if ($DriveLabUi -match 'text\s*=\s*if\s*\(locked\)') {
    throw "The old bottom-navigation lock icon logic is still present."
}

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
foreach ($Entry in $Paths.GetEnumerator()) {
    $Relative = $Entry.Value.Substring($Project.Length).TrimStart('\')
    $BackupPath = Join-Path $BackupRoot $Relative
    New-Item -ItemType Directory -Force -Path (Split-Path $BackupPath -Parent) | Out-Null
    Copy-Item -LiteralPath $Entry.Value -Destination $BackupPath -Force
}

$WroteSource = $false
try {
    Write-Host ""
    Write-Host "===== APPLYING CORRECTED DRIVELAB 2.4.1 PREVIEW DESIGN =====" -ForegroundColor Cyan
    Write-Host "Bottom navigation: normal letters, no lock icons" -ForegroundColor Green
    Write-Host "Free Full-only tabs: real page visible, dimmed, disabled, purchase card on top" -ForegroundColor Green

    Write-Utf8Text $Paths.DriveLabUi $DriveLabUi
    Write-Utf8Text $Paths.EditionUi $EditionUi
    Write-Utf8Text $Paths.UpdateUi $UpdateUi
    Write-Utf8Text $Paths.BuildGradle $BuildGradle
    Write-Utf8Text $Paths.Changelog $Changelog
    Write-Utf8Text $Paths.ReleaseNotes ($ReleaseNotes.TrimEnd() + "`n")
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
    Write-Host "DRIVELAB 2.4.1 CORRECTED BUILD COMPLETE" -ForegroundColor Green
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
        foreach ($Entry in $Paths.GetEnumerator()) {
            $Relative = $Entry.Value.Substring($Project.Length).TrimStart('\')
            $BackupPath = Join-Path $BackupRoot $Relative
            if (Test-Path -LiteralPath $BackupPath) {
                Copy-Item -LiteralPath $BackupPath -Destination $Entry.Value -Force
            }
        }
        Write-Host "The previous DriveLab source was restored." -ForegroundColor Yellow
    }
    throw
}
