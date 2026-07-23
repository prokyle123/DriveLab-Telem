$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$SourceUrl = "https://raw.githubusercontent.com/prokyle123/BeamNG-Android-Telemetry/main/patches/v2.4.0/UPLOAD-DRIVELAB-V2.4.0-TO-VIRUSTOTAL.ps1"
$Temporary = Join-Path $env:TEMP "UPLOAD-DRIVELAB-V2.4.0-TO-VIRUSTOTAL-corrected.ps1"
$Utf8Read = [System.Text.UTF8Encoding]::new($false, $true)
$Utf8Write = [System.Text.UTF8Encoding]::new($false)

Invoke-WebRequest `
    -Uri $SourceUrl `
    -OutFile $Temporary `
    -UseBasicParsing

$Text = [System.IO.File]::ReadAllText(
    $Temporary,
    $Utf8Read
)

$OriginalCount = ([regex]::Matches($Text, '\\\r?\n\s*')).Count

if ($OriginalCount -ne 8) {
    throw "Could not prepare the VirusTotal uploader. Expected eight continuation markers but found $OriginalCount."
}

$Text = [regex]::Replace(
    $Text,
    '\\\r?\n\s*',
    ' '
)

[System.IO.File]::WriteAllText(
    $Temporary,
    $Text,
    $Utf8Write
)

powershell.exe `
    -ExecutionPolicy Bypass `
    -File $Temporary

if ($LASTEXITCODE -ne 0) {
    throw "The VirusTotal upload tool failed."
}

Remove-Item `
    -LiteralPath $Temporary `
    -Force `
    -ErrorAction SilentlyContinue
