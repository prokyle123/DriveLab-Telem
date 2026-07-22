param([string]$ProjectPath = "")

$ErrorActionPreference = "Stop"
$sourcePath = Join-Path $PSScriptRoot "APPLY-DRIVELAB-ACHIEVEMENT-VAULT-V2.3.0-FIXED.ps1"
$runtimePath = Join-Path $PSScriptRoot ".APPLY-DRIVELAB-ACHIEVEMENT-VAULT-V2.3.0-RUNTIME.ps1"
$runtimePayloadPath = Join-Path $PSScriptRoot "payload\app\src\main\java\com\auroramediagroup\drivelab\AchievementRuntime.kt"

try {
    if (!(Test-Path $sourcePath)) {
        throw "The Achievement Vault applier is missing: $sourcePath"
    }
    if (!(Test-Path $runtimePayloadPath)) {
        throw "The Achievement Vault runtime payload is missing: $runtimePayloadPath"
    }

    # Keep the runtime limited to fields already exposed by DriveLab's public telemetry model.
    $runtimePayload = [System.IO.File]::ReadAllText($runtimePayloadPath)
    $runtimePayload = $runtimePayload.Replace(
        'val rollDeg = abs(derived?.rollDeg ?: motion?.rollDeg ?: 0.0)',
        'val rollDeg = abs(derived?.rollDeg ?: 0.0)'
    )
    $runtimePayload = $runtimePayload.Replace(
        'val pitchDeg = abs(derived?.pitchDeg ?: motion?.pitchDeg ?: 0.0)',
        'val pitchDeg = abs(derived?.pitchDeg ?: 0.0)'
    )
    $runtimePayload = $runtimePayload.Replace(
        'val verticalSpeed = abs(derived?.verticalSpeedMps ?: motion?.velZ ?: 0.0)',
        'val verticalSpeed = abs(derived?.verticalSpeedMps ?: 0.0)'
    )
    $runtimePayload = $runtimePayload.Replace(
        'if (newBrake100 || analyzer.brake.startSpeedMph >= 80.0) add(AchievementMetric.HIGH_SPEED_STOPS)',
        'if (newBrake100) add(AchievementMetric.HIGH_SPEED_STOPS)'
    )
    [System.IO.File]::WriteAllText(
        $runtimePayloadPath,
        $runtimePayload,
        [System.Text.UTF8Encoding]::new($false)
    )

    $source = [System.IO.File]::ReadAllText($sourcePath)
    $source = $source.Replace(
        '$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)',
        '$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)'
    )
    $source = $source.Replace(
        '$candidates = New-Object System.Collections.Generic.List[string]',
        '$candidates = [System.Collections.Generic.List[string]]::new()'
    )
    $source = $source.Replace(
        '$absent = New-Object System.Collections.Generic.List[string]',
        '$absent = [System.Collections.Generic.List[string]]::new()'
    )
    $source = $source.Replace(
        '& $apksigner.FullName verify --verbose --print-certs $apk.FullName',
        '& ($apksigner.FullName) verify --verbose --print-certs $apk.FullName'
    )

    # Use the stable ready flag instead of depending on the name of an internal bucket variable.
    $source = $source.Replace(
        "        previousTopSpeedBucket = floor(progress.topSpeedMph / 5.0).toInt()`n        ready = true",
        "        ready = true"
    )
    $source = $source.Replace(
        "        previousTopSpeedBucket = floor(progress.topSpeedMph / 5.0).toInt()`n        achievementRuntime.sync(progress, analyzer)`n        ready = true",
        "        achievementRuntime.sync(progress, analyzer)`n        ready = true"
    )

    $oldRegexConstructor = @'
    $regex = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
'@
    $newRegexConstructor = @'
    $regex = [System.Text.RegularExpressions.Regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
'@
    $source = $source.Replace($oldRegexConstructor, $newRegexConstructor)

    [System.IO.File]::WriteAllText(
        $runtimePath,
        $source,
        [System.Text.UTF8Encoding]::new($false)
    )

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $runtimePath,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors.Count -gt 0) {
        $details = $parseErrors | ForEach-Object {
            "Line $($_.Extent.StartLineNumber): $($_.Message)"
        }
        throw "PowerShell validation failed:`n$($details -join "`n")"
    }

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $runtimePath
    )
    if ($ProjectPath) {
        $arguments += @("-ProjectPath", $ProjectPath)
    }

    & powershell.exe @arguments
    exit $LASTEXITCODE
}
catch {
    Write-Host "PATCH STARTUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    Remove-Item $runtimePath -Force -ErrorAction SilentlyContinue
}
