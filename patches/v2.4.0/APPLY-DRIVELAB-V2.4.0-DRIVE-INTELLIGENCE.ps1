$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Project = "C:\Users\proky\OneDrive\Desktop\DriveLabTelem-v1.8.0-online-check-purchase"
$PackageName = "com.auroramediagroup.drivelab"
$JavaHome = "C:\Program Files\Android\Android Studio\jbr"
$Adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$PayloadUrl = "https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/5067a3a976e49292805e83d0a1f3759744a7a50a/patches/v2.4.0/DriveIntelligence.kt"

$Utf8Read = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8Write = [System.Text.UTF8Encoding]::new($false)

function Read-Utf8File {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Required file was not found: $Path"
    }
    return ([System.IO.File]::ReadAllText($Path, $Utf8Read) -replace "`r`n", "`n")
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )
    $Parent = Split-Path -Parent $Path
    if ($Parent) { New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
    [System.IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Utf8Write)
}

function Replace-TextOnce {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Old,
        [Parameter(Mandatory)][string]$New,
        [Parameter(Mandatory)][string]$Label
    )
    $Count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($Count -ne 1) {
        throw "$Label expected exactly one source match but found $Count."
    }
    return $Text.Replace($Old, $New)
}

function Replace-RegexOnce {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Replacement,
        [Parameter(Mandatory)][string]$Label
    )
    $Options = [System.Text.RegularExpressions.RegexOptions]::Singleline
    $Matches = [regex]::Matches($Text, $Pattern, $Options)
    if ($Matches.Count -ne 1) {
        throw "$Label expected exactly one source match but found $($Matches.Count)."
    }
    $Evaluator = [System.Text.RegularExpressions.MatchEvaluator]{ param($Match) $Replacement }
    return [regex]::Replace($Text, $Pattern, $Evaluator, $Options)
}

function Assert-CleanUtf8 {
    param([Parameter(Mandatory)][string]$Path)
    $Text = Read-Utf8File $Path
    if (
        $Text.Contains("Ã") -or
        $Text.Contains("Â") -or
        $Text.Contains("â€") -or
        $Text.Contains([char]0xFFFD)
    ) {
        throw "UTF-8 validation failed for $Path"
    }
}

function Restore-Backup {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string[]]$OriginalFiles,
        [Parameter(Mandatory)][string]$NewFile
    )
    Write-Host "Restoring the original DriveLab source..." -ForegroundColor Yellow
    foreach ($Original in $OriginalFiles) {
        $Relative = $Original.Substring($Project.Length).TrimStart("\")
        $Saved = Join-Path $BackupRoot $Relative
        if (Test-Path -LiteralPath $Saved) {
            Copy-Item -LiteralPath $Saved -Destination $Original -Force
        }
    }
    $NewRelative = $NewFile.Substring($Project.Length).TrimStart("\")
    $SavedNew = Join-Path $BackupRoot $NewRelative
    if (Test-Path -LiteralPath $SavedNew) {
        Copy-Item -LiteralPath $SavedNew -Destination $NewFile -Force
    } else {
        Remove-Item -LiteralPath $NewFile -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $Project)) {
    throw "DriveLab project was not found at $Project"
}
if (-not (Test-Path -LiteralPath $JavaHome)) {
    throw "Android Studio Java was not found at $JavaHome"
}

$Gradle = Join-Path $Project "app\build.gradle.kts"
$Models = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\Models.kt"
$Storage = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\Storage.kt"
$ViewModel = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\DriveLabViewModel.kt"
$Ui = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\DriveLabUi.kt"
$AutomaticDrive = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\AutomaticDriveSession.kt"
$UpdateUi = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\UpdateUi.kt"
$Changelog = Join-Path $Project "CHANGELOG.md"
$DriveIntelligence = Join-Path $Project "app\src\main\java\com\auroramediagroup\drivelab\DriveIntelligence.kt"
$ReleaseNotes = Join-Path $Project "UPDATE-RELEASE-NOTES.txt"
$ReleaseOutput = Join-Path $Project "release-output"
$BuiltApk = Join-Path $Project "app\build\outputs\apk\release\app-release.apk"
$CustomerApk = Join-Path $ReleaseOutput "DriveLab-Telem-v2.4.0.apk"

$OriginalFiles = @($Gradle, $Models, $Storage, $ViewModel, $Ui, $AutomaticDrive, $UpdateUi, $Changelog)
foreach ($File in $OriginalFiles) {
    if (-not (Test-Path -LiteralPath $File)) { throw "Required DriveLab file is missing: $File" }
}

$GradleText = Read-Utf8File $Gradle
if ($GradleText -notmatch 'versionCode\s*=\s*35' -or $GradleText -notmatch 'versionName\s*=\s*"2\.3\.0"') {
    throw "This patch requires the current DriveLab 2.3.0 source at build 35."
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupRoot = Join-Path $Project ".patch-backups\drive-intelligence-v2.4.0-$Timestamp"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
foreach ($File in $OriginalFiles) {
    $Relative = $File.Substring($Project.Length).TrimStart("\")
    $Destination = Join-Path $BackupRoot $Relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $File -Destination $Destination -Force
}
if (Test-Path -LiteralPath $DriveIntelligence) {
    $Relative = $DriveIntelligence.Substring($Project.Length).TrimStart("\")
    $Destination = Join-Path $BackupRoot $Relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $DriveIntelligence -Destination $Destination -Force
}

Write-Host "Backup created: $BackupRoot" -ForegroundColor Cyan

try {
    Write-Host "Downloading the Drive Intelligence source payload..." -ForegroundColor Cyan
    $PayloadTemp = Join-Path $env:TEMP "DriveIntelligence-v2.4.0-$Timestamp.kt"
    Invoke-WebRequest -Uri $PayloadUrl -OutFile $PayloadTemp -UseBasicParsing
    $Payload = [System.IO.File]::ReadAllText($PayloadTemp, $Utf8Read)
    if (-not $Payload.Contains("class DriveIntelligenceEngine")) {
        throw "The downloaded Drive Intelligence payload was incomplete."
    }
    Write-Utf8File $DriveIntelligence $Payload
    Remove-Item -LiteralPath $PayloadTemp -Force -ErrorAction SilentlyContinue

    $GradleText = Read-Utf8File $Gradle
    $GradleText = Replace-TextOnce $GradleText 'versionCode = 35' 'versionCode = 36' "Version code"
    $GradleText = Replace-TextOnce $GradleText 'versionName = "2.3.0"' 'versionName = "2.4.0"' "Version name"
    Write-Utf8File $Gradle $GradleText

    $ModelsText = Read-Utf8File $Models
    $NewSettings = @'
data class AppSettings(
    val onboardingComplete: Boolean = false,
    val demoMode: Boolean = false,
    val units: UnitSystem = UnitSystem.MPH,
    val temperatureUnit: TemperatureUnit = TemperatureUnit.CELSIUS,
    val boostUnit: BoostUnit = BoostUnit.BAR,
    val dashboardStyle: DashboardStyle = DashboardStyle.TRACK,
    val outGaugePort: Int = 4444,
    val motionPort: Int = 4445,
    val redlineRpm: Int = 7000,
    val keepScreenAwake: Boolean = true,
    val showFuel: Boolean = true,
    val showTemperatures: Boolean = true,
    val showTurbo: Boolean = true,
    val soundsEnabled: Boolean = false,
    val automaticDriveTrackingEnabled: Boolean = true,
    val dashboardReorderEnabled: Boolean = false,
    val startupTab: MainTab = MainTab.LIVE,
    val stuntDetectionEnabled: Boolean = true,
    val stuntPopupsEnabled: Boolean = true,
    val stuntSpeechEnabled: Boolean = false,
    val stuntSensitivity: DriveIntelligenceSensitivity = DriveIntelligenceSensitivity.BALANCED,
    val driverDnaEnabled: Boolean = false,
    val driverDnaShowAfterDrive: Boolean = true,
    val driveStoriesEnabled: Boolean = true,
    val driveStoriesIncludeNegative: Boolean = true,
    val driveStoriesIncludeDna: Boolean = false,
    val driveStoryDetail: DriveStoryDetail = DriveStoryDetail.NORMAL,
    val dashboardLayouts: Map<DashboardPage, List<String>> = emptyMap()
)

fun Double.safeFinite
'@
    $ModelsText = Replace-RegexOnce $ModelsText 'data class AppSettings\(.*?\n\)\n\nfun Double\.safeFinite' $NewSettings "AppSettings model"
    Write-Utf8File $Models $ModelsText

    $StorageText = Read-Utf8File $Storage
    $StorageLoadAnchor = '        dashboardLayouts = decodeDashboardLayouts(preferences.getString("dashboardLayouts", null))'
    $StorageLoadReplacement = @'
        stuntDetectionEnabled = preferences.getBoolean("stuntDetectionEnabled", true),
        stuntPopupsEnabled = preferences.getBoolean("stuntPopupsEnabled", true),
        stuntSpeechEnabled = preferences.getBoolean("stuntSpeechEnabled", false),
        stuntSensitivity = runCatching {
            DriveIntelligenceSensitivity.valueOf(
                preferences.getString("stuntSensitivity", DriveIntelligenceSensitivity.BALANCED.name)!!
            )
        }.getOrDefault(DriveIntelligenceSensitivity.BALANCED),
        driverDnaEnabled = preferences.getBoolean("driverDnaEnabled", false),
        driverDnaShowAfterDrive = preferences.getBoolean("driverDnaShowAfterDrive", true),
        driveStoriesEnabled = preferences.getBoolean("driveStoriesEnabled", true),
        driveStoriesIncludeNegative = preferences.getBoolean("driveStoriesIncludeNegative", true),
        driveStoriesIncludeDna = preferences.getBoolean("driveStoriesIncludeDna", false),
        driveStoryDetail = runCatching {
            DriveStoryDetail.valueOf(
                preferences.getString("driveStoryDetail", DriveStoryDetail.NORMAL.name)!!
            )
        }.getOrDefault(DriveStoryDetail.NORMAL),
        dashboardLayouts = decodeDashboardLayouts(preferences.getString("dashboardLayouts", null))
'@
    $StorageText = Replace-TextOnce $StorageText $StorageLoadAnchor $StorageLoadReplacement.TrimEnd() "Settings load"
    $StorageSaveAnchor = '            .putString("dashboardLayouts", encodeDashboardLayouts(settings.dashboardLayouts))'
    $StorageSaveReplacement = @'
            .putBoolean("stuntDetectionEnabled", settings.stuntDetectionEnabled)
            .putBoolean("stuntPopupsEnabled", settings.stuntPopupsEnabled)
            .putBoolean("stuntSpeechEnabled", settings.stuntSpeechEnabled)
            .putString("stuntSensitivity", settings.stuntSensitivity.name)
            .putBoolean("driverDnaEnabled", settings.driverDnaEnabled)
            .putBoolean("driverDnaShowAfterDrive", settings.driverDnaShowAfterDrive)
            .putBoolean("driveStoriesEnabled", settings.driveStoriesEnabled)
            .putBoolean("driveStoriesIncludeNegative", settings.driveStoriesIncludeNegative)
            .putBoolean("driveStoriesIncludeDna", settings.driveStoriesIncludeDna)
            .putString("driveStoryDetail", settings.driveStoryDetail.name)
            .putString("dashboardLayouts", encodeDashboardLayouts(settings.dashboardLayouts))
'@
    $StorageText = Replace-TextOnce $StorageText $StorageSaveAnchor $StorageSaveReplacement.TrimEnd() "Settings save"
    Write-Utf8File $Storage $StorageText

    $AutomaticText = Read-Utf8File $AutomaticDrive
    $AutomaticText = Replace-RegexOnce $AutomaticText 'data class CompletedDriveSession\(\n    val session: SessionSummary,\n    val previousSession: SessionSummary\?,\n    val xpEarned: Long,\n    val automatic: Boolean\n\)' @'
data class CompletedDriveSession(
    val session: SessionSummary,
    val previousSession: SessionSummary?,
    val xpEarned: Long,
    val automatic: Boolean,
    val intelligence: DriveIntelligenceRecord? = null
)
'@ "CompletedDriveSession model"
    $DurationAnchor = @'
                DriveSummaryRow(
                    label = "Duration",
'@
    $DurationReplacement = @'
                result.intelligence?.let {
                    DriveStoryDialogCard(it)
                }

                DriveSummaryRow(
                    label = "Duration",
'@
    $AutomaticText = Replace-TextOnce $AutomaticText $DurationAnchor $DurationReplacement "Completed-drive story"
    $AutomaticText = Replace-RegexOnce $AutomaticText 'ExportUtils\.shareSessionCard\(\s*context,\s*session\s*\)' @'
val intelligence = result.intelligence
                    if (intelligence?.story != null) {
                        DriveIntelligenceExport.shareStoryCard(context, session, intelligence)
                    } else {
                        ExportUtils.shareSessionCard(context, session)
                    }
'@ "Completed-drive share action"
    $AutomaticText = Replace-TextOnce $AutomaticText '                Text("SHARE CARD")' '                Text(if (result.intelligence?.story != null) "SHARE STORY" else "SHARE CARD")' "Completed-drive share label"
    Write-Utf8File $AutomaticDrive $AutomaticText

    $ViewModelText = Read-Utf8File $ViewModel
    $ViewModelText = Replace-TextOnce $ViewModelText '    private val appUpdateManager = AppUpdateManager(application)' @'
    private val appUpdateManager = AppUpdateManager(application)
    private val driveIntelligenceEngine = DriveIntelligenceEngine(application)
'@ "Drive Intelligence engine"
    $LiveHistoryAnchor = @'
    private val _liveHistory = MutableStateFlow<List<LiveTraceSample>>(emptyList())
    val liveHistory: StateFlow<List<LiveTraceSample>> = _liveHistory.asStateFlow()
    private var lastLiveTraceAtMs = 0L
'@
    $LiveHistoryReplacement = @'
    private val _liveHistory = MutableStateFlow<List<LiveTraceSample>>(emptyList())
    val liveHistory: StateFlow<List<LiveTraceSample>> = _liveHistory.asStateFlow()
    private var lastLiveTraceAtMs = 0L

    val driveIntelligenceState: StateFlow<DriveIntelligenceState> = driveIntelligenceEngine.state
    private val _driveIntelligenceRecords = MutableStateFlow(driveIntelligenceEngine.loadRecords())
    val driveIntelligenceRecords: StateFlow<Map<String, DriveIntelligenceRecord>> = _driveIntelligenceRecords.asStateFlow()
'@
    $ViewModelText = Replace-TextOnce $ViewModelText $LiveHistoryAnchor $LiveHistoryReplacement "Drive Intelligence state"
    $PreviousSessionAnchor = @'
            val previousSession =
                _sessions.value.firstOrNull()

            val wasAutomatic =
'@
    $PreviousSessionReplacement = @'
            val previousSession =
                _sessions.value.firstOrNull()

            val intelligenceRecord = driveIntelligenceEngine.completeSession(
                session = session,
                previousSession = previousSession,
                settings = _settings.value,
                currentProgress = _progress.value
            )

            val wasAutomatic =
'@
    $ViewModelText = Replace-TextOnce $ViewModelText $PreviousSessionAnchor $PreviousSessionReplacement "Completed-session intelligence"
    $DelayAnchor = @'
                delay(250L)

                val xpEarned =
'@
    $DelayReplacement = @'
                _driveIntelligenceRecords.value = driveIntelligenceEngine.loadRecords()

                delay(250L)

                val xpEarned =
'@
    $ViewModelText = Replace-TextOnce $ViewModelText $DelayAnchor $DelayReplacement "Intelligence history refresh"
    $CompletedResultAnchor = @'
                        automatic =
                            wasAutomatic
                    )
'@
    $CompletedResultReplacement = @'
                        automatic =
                            wasAutomatic,
                        intelligence =
                            intelligenceRecord
                    )
'@
    $ViewModelText = Replace-TextOnce $ViewModelText $CompletedResultAnchor $CompletedResultReplacement "Completed-drive result"
    $AnalyzerAnchor = @'
                        analyzer.update(frame)
                        appendLiveTrace(frame)
'@
    $AnalyzerReplacement = @'
                        analyzer.update(frame)
                        driveIntelligenceEngine.update(
                            frame = frame,
                            analyzer = analyzer.state.value,
                            settings = _settings.value
                        )?.let(::applyDriveIntelligenceXp)
                        appendLiveTrace(frame)
'@
    $ViewModelText = Replace-TextOnce $ViewModelText $AnalyzerAnchor $AnalyzerReplacement "Live maneuver processing"
    $AutoTrackingMethodAnchor = '    fun setAutomaticDriveTrackingEnabled('
    $IntelligenceMethods = @'
    fun setStuntDetectionEnabled(enabled: Boolean) =
        updateSettings(_settings.value.copy(stuntDetectionEnabled = enabled), restartNetwork = false)

    fun setStuntPopupsEnabled(enabled: Boolean) =
        updateSettings(_settings.value.copy(stuntPopupsEnabled = enabled), restartNetwork = false)

    fun setStuntSpeechEnabled(enabled: Boolean) =
        updateSettings(_settings.value.copy(stuntSpeechEnabled = enabled), restartNetwork = false)

    fun setStuntSensitivity(sensitivity: DriveIntelligenceSensitivity) =
        updateSettings(_settings.value.copy(stuntSensitivity = sensitivity), restartNetwork = false)

    fun setDriverDnaEnabled(enabled: Boolean) =
        updateSettings(_settings.value.copy(driverDnaEnabled = enabled), restartNetwork = false)

    fun setDriverDnaShowAfterDrive(enabled: Boolean) =
        updateSettings(_settings.value.copy(driverDnaShowAfterDrive = enabled), restartNetwork = false)

    fun setDriveStoriesEnabled(enabled: Boolean) =
        updateSettings(_settings.value.copy(driveStoriesEnabled = enabled), restartNetwork = false)

    fun setDriveStoriesIncludeNegative(enabled: Boolean) =
        updateSettings(_settings.value.copy(driveStoriesIncludeNegative = enabled), restartNetwork = false)

    fun setDriveStoriesIncludeDna(enabled: Boolean) =
        updateSettings(_settings.value.copy(driveStoriesIncludeDna = enabled), restartNetwork = false)

    fun setDriveStoryDetail(detail: DriveStoryDetail) =
        updateSettings(_settings.value.copy(driveStoryDetail = detail), restartNetwork = false)

    fun resetDriverDna() = driveIntelligenceEngine.resetDna()
    fun dismissDriveIntelligenceEvent() = driveIntelligenceEngine.dismissCurrentEvent()

    fun setAutomaticDriveTrackingEnabled(
'@
    $ViewModelText = Replace-TextOnce $ViewModelText $AutoTrackingMethodAnchor $IntelligenceMethods "Drive Intelligence settings methods"
    $ViewModelText = Replace-TextOnce $ViewModelText '            liveProgressTracker.reset(cleared, analyzer.state.value)' @'
            liveProgressTracker.reset(cleared, analyzer.state.value)
            driveIntelligenceEngine.resetDna()
'@ "Driver DNA reset"
    $DeleteSessionBlock = @'
    fun deleteSession(id: String) {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { sessionStore.deleteSession(id) }
            _sessions.value = _sessions.value.filterNot { it.id == id }
        }
    }
'@
    $DeleteSessionReplacement = @'
    fun deleteSession(id: String) {
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                sessionStore.deleteSession(id)
                driveIntelligenceEngine.deleteRecord(id)
            }
            _sessions.value = _sessions.value.filterNot { it.id == id }
            _driveIntelligenceRecords.value = driveIntelligenceEngine.loadRecords()
        }
    }
'@
    $ViewModelText = Replace-TextOnce $ViewModelText $DeleteSessionBlock $DeleteSessionReplacement "Session deletion"
    $ClearSessionsBlock = @'
    fun clearSessions() {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { sessionStore.clearSessions() }
            _sessions.value = emptyList()
        }
    }
'@
    $ClearSessionsReplacement = @'
    fun clearSessions() {
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                sessionStore.clearSessions()
                driveIntelligenceEngine.clearRecords()
            }
            _sessions.value = emptyList()
            _driveIntelligenceRecords.value = emptyMap()
        }
    }
'@
    $ViewModelText = Replace-TextOnce $ViewModelText $ClearSessionsBlock $ClearSessionsReplacement "Session clearing"
    $XpHandler = @'
    private fun applyDriveIntelligenceXp(event: ManeuverEvent) {
        if (event.isDemo || !licenseManager.state.value.canUseFullApp) return
        val delta = maneuverXpDelta(event)
        if (!delta.hasChanges) return
        viewModelScope.launch {
            val (updated, award) = withContext(Dispatchers.IO) {
                progressStore.applyLiveDelta(delta)
            }
            _progress.value = updated
            if (award != null) _lastXpAward.value = award
        }
    }

    fun deleteSession(id: String) {
'@
    $ViewModelText = Replace-TextOnce $ViewModelText '    fun deleteSession(id: String) {' $XpHandler "Maneuver XP handler"
    Write-Utf8File $ViewModel $ViewModelText

    $UiText = Read-Utf8File $Ui
    $CompletedStateAnchor = @'
    val completedDriveSession by
        viewModel.completedDriveSession.collectAsState()
'@
    $CompletedStateReplacement = @'
    val completedDriveSession by
        viewModel.completedDriveSession.collectAsState()
    val driveIntelligenceState by
        viewModel.driveIntelligenceState.collectAsState()
'@
    $UiText = Replace-TextOnce $UiText $CompletedStateAnchor $CompletedStateReplacement "Drive Intelligence UI state"
    $SoundAnchor = '    SoundEffectsHost(settings, telemetry, connection, analyzer, lastXpAward)'
    $SoundReplacement = @'
    DriveIntelligenceEventHost(
        state = driveIntelligenceState,
        settings = settings,
        onDismiss = viewModel::dismissDriveIntelligenceEvent
    )

    SoundEffectsHost(settings, telemetry, connection, analyzer, lastXpAward)
'@
    $UiText = Replace-TextOnce $UiText $SoundAnchor $SoundReplacement.TrimEnd() "Maneuver event host"
    $ProgressStartAnchor = @'
) {
    val style = currentDrivingStyle(analyzer)
    val precision =
'@
    $ProgressStartReplacement = @'
) {
    val intelligenceSettings by viewModel.settings.collectAsState()
    val intelligenceState by viewModel.driveIntelligenceState.collectAsState()
    val style = currentDrivingStyle(analyzer)
    val precision =
'@
    $UiText = Replace-TextOnce $UiText $ProgressStartAnchor $ProgressStartReplacement "Driver DNA progress state"
    $ProgressHeaderAnchor = @'
        item { SectionHeader("Driver Progression", "XP, levels, records, and achievements update automatically while telemetry is flowing. No recording required.") }
        item {
'@
    $ProgressHeaderReplacement = @'
        item { SectionHeader("Driver Progression", "XP, levels, records, and achievements update automatically while telemetry is flowing. No recording required.") }
        item { DriverDnaProgressCard(settings = intelligenceSettings, state = intelligenceState) }
        item {
'@
    $UiText = Replace-TextOnce $UiText $ProgressHeaderAnchor $ProgressHeaderReplacement "Driver DNA progress card"
    $UnitsAnchor = @'
        item {
            Column(modifier = Modifier.fillMaxWidth().background(DrivePanel, RoundedCornerShape(18.dp)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("UNITS", color = DriveCyan, fontWeight = FontWeight.Bold)
'@
    $UnitsReplacement = @'
        item {
            DriveIntelligenceSettingsCard(
                settings = settings,
                fullEdition = licenseState.canUseFullApp,
                state = viewModel.driveIntelligenceState.collectAsState().value,
                viewModel = viewModel
            )
        }

        item {
            Column(modifier = Modifier.fillMaxWidth().background(DrivePanel, RoundedCornerShape(18.dp)).padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("UNITS", color = DriveCyan, fontWeight = FontWeight.Bold)
'@
    $UiText = Replace-TextOnce $UiText $UnitsAnchor $UnitsReplacement "Drive Intelligence settings card"
    $SessionsStartAnchor = @'
private fun SessionsScreen(sessions: List<SessionSummary>, viewModel: DriveLabViewModel) {
    val context = LocalContext.current
'@
    $SessionsStartReplacement = @'
private fun SessionsScreen(sessions: List<SessionSummary>, viewModel: DriveLabViewModel) {
    val context = LocalContext.current
    val intelligenceRecords by viewModel.driveIntelligenceRecords.collectAsState()
'@
    $UiText = Replace-TextOnce $UiText $SessionsStartAnchor $SessionsStartReplacement "Session intelligence state"
    $SessionItemsAnchor = '        items(sessions, key = { it.id }) { session ->'
    $SessionItemsReplacement = @'
        items(sessions, key = { it.id }) { session ->
            val intelligence = intelligenceRecords[session.id]
'@
    $UiText = Replace-TextOnce $UiText $SessionItemsAnchor $SessionItemsReplacement.TrimEnd() "Session intelligence lookup"
    $TraceAnchor = '                SessionTraceChart(session.samples, Modifier.fillMaxWidth())'
    $TraceReplacement = @'
                intelligence?.let { DriveStorySessionCard(session = session, record = it) }
                SessionTraceChart(session.samples, Modifier.fillMaxWidth())
'@
    $UiText = Replace-TextOnce $UiText $TraceAnchor $TraceReplacement.TrimEnd() "Drive Story session card"
    $ShareButtonAnchor = '                    Button(onClick = { ExportUtils.shareSessionCard(context, session) }, modifier = Modifier.weight(1f)) { Text("SHARE CARD") }'
    $ShareButtonReplacement = @'
                    Button(
                        onClick = {
                            if (intelligence?.story != null) {
                                DriveIntelligenceExport.shareStoryCard(context, session, intelligence)
                            } else {
                                ExportUtils.shareSessionCard(context, session)
                            }
                        },
                        modifier = Modifier.weight(1f)
                    ) { Text(if (intelligence?.story != null) "SHARE STORY" else "SHARE CARD") }
'@
    $UiText = Replace-TextOnce $UiText $ShareButtonAnchor $ShareButtonReplacement.TrimEnd() "Session story share button"
    Write-Utf8File $Ui $UiText

    $UpdateText = Read-Utf8File $UpdateUi
    $CurrentCount = ([regex]::Matches($UpdateText, [regex]::Escape('label = "CURRENT RELEASE"'))).Count
    if ($CurrentCount -ne 1) { throw "In-app changelog expected one current release but found $CurrentCount." }
    $UpdateText = $UpdateText.Replace('label = "CURRENT RELEASE"', 'label = "PREVIOUS RELEASE"')
    $ReleaseEntry = @'
private val ReleaseHistory = listOf(
    ReleaseEntry(
        version = "2.4.0",
        label = "CURRENT RELEASE",
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
    $UpdateText = Replace-TextOnce $UpdateText 'private val ReleaseHistory = listOf(' $ReleaseEntry "In-app 2.4.0 changelog"
    Write-Utf8File $UpdateUi $UpdateText

    $ChangelogText = Read-Utf8File $Changelog
    $ChangelogEntry = @'
# DriveLab Telem Changelog

## 2.4.0

- Added Drive Intelligence with live stunt and maneuver detection.
- Added donuts, burnouts, J-turns, reverse 180s, Scandinavian flicks, handbrake-style turns, drift transitions, two-wheel driving, wheelies, and stoppies.
- Added clean jumps, big jumps, hard landings, barrel rolls, front flips, backflips, and flat spins.
- Added high-speed saves and near-rollover recoveries.
- Added confidence scoring, cooldowns, repeat-event XP reduction, optional large event cards, and optional spoken maneuver names.
- Added optional Driver DNA with twelve slow-changing driving traits. It defaults to off and remains stored locally.
- Added locally generated Drive Stories with major moments and shareable story cards.
- Added Drive Stories and maneuver history to completed-drive summaries and saved sessions.
- Preserved licenses, TrackLab courses and laps, Auto Co-Driver settings and note edits, RaceLink data, Achievement Vault progress, sessions, crashes, and permanent Android signing compatibility.
'@
    $ChangelogText = Replace-TextOnce $ChangelogText '# DriveLab Telem Changelog' $ChangelogEntry.TrimEnd() "Project changelog"
    Write-Utf8File $Changelog $ChangelogText

    $ReleaseNotesText = @'
DriveLab Telem 2.4.0 — Drive Intelligence

- Full stunt and maneuver detection using the existing BeamNG OutGauge and MotionSim telemetry
- Donuts, burnouts, J-turns, reverse 180s, Scandinavian flicks, handbrake-style turns, drift transitions, two-wheel driving, wheelies, stoppies, jumps, landings, flips, flat spins, and saves
- Confidence scoring, event cooldowns, repeat-event XP reduction, optional event cards, and optional spoken callouts
- Optional Driver DNA with twelve slow-changing traits; disabled by default and stored only on the phone
- Locally generated Drive Stories with major moments and shareable story cards
- Existing licenses, settings, Achievement Vault progress, TrackLab courses, Co-Driver data, RaceLink data, sessions, crashes, and signing compatibility are preserved

Install directly over the existing DriveLab installation. Do not uninstall first.
'@
    Write-Utf8File $ReleaseNotes $ReleaseNotesText

    foreach ($File in @($Models, $Storage, $ViewModel, $Ui, $AutomaticDrive, $UpdateUi, $DriveIntelligence)) {
        Assert-CleanUtf8 $File
    }

    $env:JAVA_HOME = $JavaHome
    $env:Path = "$JavaHome\bin;$env:Path"
    Set-Location $Project

    Write-Host ""
    Write-Host "===== BUILDING DRIVELAB 2.4.0 =====" -ForegroundColor Cyan
    Write-Host "Do not press Ctrl+C while Gradle is running. The build may pause for a minute." -ForegroundColor Yellow
    & ".\gradlew.bat" --no-daemon clean :app:testDebugUnitTest :app:lintRelease :app:assembleRelease
    if ($LASTEXITCODE -ne 0) { throw "Gradle returned exit code $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $BuiltApk)) { throw "The signed release APK was not created." }

    New-Item -ItemType Directory -Force -Path $ReleaseOutput | Out-Null
    Copy-Item -LiteralPath $BuiltApk -Destination $CustomerApk -Force
    $Hash = (Get-FileHash -LiteralPath $CustomerApk -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText("$CustomerApk.sha256", "$Hash  $([System.IO.Path]::GetFileName($CustomerApk))`r`n", $Utf8Write)

    Write-Host ""
    Write-Host "BUILD SUCCESSFUL" -ForegroundColor Green
    Write-Host "APK: $CustomerApk"
    Write-Host "SHA-256: $Hash"

    if (Test-Path -LiteralPath $Adb) {
        & $Adb start-server | Out-Null
        $Devices = @(& $Adb devices | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -match '^(\S+)\s+device$') { $matches[1] }
        })
        foreach ($Serial in $Devices) {
            Write-Host "Installing on $Serial..." -ForegroundColor Cyan
            & $Adb -s $Serial install -r -g $CustomerApk
            if ($LASTEXITCODE -ne 0) { throw "APK installation failed on $Serial" }
            & $Adb -s $Serial shell am force-stop $PackageName
            & $Adb -s $Serial shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null
        }
        if ($Devices.Count -eq 0) {
            Write-Host "No authorized Android device was connected. The APK is ready in release-output." -ForegroundColor Yellow
        }
    } else {
        Write-Host "ADB was not found. The APK is ready in release-output." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "DRIVELAB 2.4.0 DRIVE INTELLIGENCE IS READY" -ForegroundColor Green
    Write-Host "Driver DNA defaults to OFF." -ForegroundColor Cyan
    Write-Host "Spoken maneuver announcements default to OFF." -ForegroundColor Cyan
    Write-Host "Visual maneuver detection and Drive Stories default to ON." -ForegroundColor Cyan
    Write-Host "Test this build before publishing it to the update server." -ForegroundColor Yellow
}
catch {
    Write-Host ""
    Write-Host "PATCH OR BUILD FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Restore-Backup -BackupRoot $BackupRoot -OriginalFiles $OriginalFiles -NewFile $DriveIntelligence
    Write-Host "DriveLab 2.3.0 was restored. The backup remains at:" -ForegroundColor Yellow
    Write-Host $BackupRoot
    exit 1
}
