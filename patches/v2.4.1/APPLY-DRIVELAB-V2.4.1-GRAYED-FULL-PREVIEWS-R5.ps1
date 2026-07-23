$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$SourceUrl = "https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/v2.4.1/APPLY-DRIVELAB-V2.4.1-GRAYED-FULL-PREVIEWS-R4.ps1"
$Temporary = Join-Path $env:TEMP "APPLY-DRIVELAB-V2.4.1-GRAYED-FULL-PREVIEWS-R4-CORRECTED.ps1"
$Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8WithBom = [System.Text.UTF8Encoding]::new($true)

Write-Host ""
Write-Host "===== PREPARING CORRECTED DRIVELAB 2.4.1 PREVIEW INSTALLER =====" -ForegroundColor Cyan

Invoke-WebRequest `
    -Uri $SourceUrl `
    -OutFile $Temporary `
    -UseBasicParsing

$Text = [System.IO.File]::ReadAllText(
    $Temporary,
    $Utf8Strict
)

if ([string]::IsNullOrWhiteSpace($Text)) {
    throw "The downloaded DriveLab installer was empty."
}

$OldReplacement = '-Replacement ''$1"PREVIOUS RELEASE"'''
$NewReplacement = '-Replacement ''version = "2.4.0", label = "PREVIOUS RELEASE"'''
$ReplacementCount = ([regex]::Matches($Text, [regex]::Escape($OldReplacement))).Count

if ($ReplacementCount -ne 1) {
    throw "Could not prepare the release-history correction. Expected one anchor but found $ReplacementCount."
}

$Text = $Text.Replace(
    $OldReplacement,
    $NewReplacement
)

[System.IO.File]::WriteAllText(
    $Temporary,
    $Text,
    $Utf8WithBom
)

$Tokens = $null
$Errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $Temporary,
    [ref]$Tokens,
    [ref]$Errors
)

if ($Errors.Count -gt 0) {
    $Message = ($Errors | ForEach-Object {
        "Line $($_.Extent.StartLineNumber): $($_.Message)"
    }) -join "`n"

    throw "The corrected installer contains a PowerShell syntax error.`n$Message"
}

Write-Host "PowerShell syntax validation passed." -ForegroundColor Green
Write-Host "Bottom bar will use normal letters with no lock icons." -ForegroundColor Green
Write-Host "Free users will see the real Full pages dimmed and disabled." -ForegroundColor Green
Write-Host "Starting the guarded patch, tests, lint, and signed build..." -ForegroundColor Cyan
Write-Host "Do not close this window or press Ctrl+C while Gradle is running." -ForegroundColor Yellow

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Temporary

$ExitCode = $LASTEXITCODE

Remove-Item `
    -LiteralPath $Temporary `
    -Force `
    -ErrorAction SilentlyContinue

if ($ExitCode -ne 0) {
    throw "The DriveLab 2.4.1 corrected preview installer failed with exit code $ExitCode."
}
