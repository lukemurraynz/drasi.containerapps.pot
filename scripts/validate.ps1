param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$EnvironmentName,

    [Parameter()]
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command azd -ErrorAction SilentlyContinue)) {
    throw 'Azure Developer CLI (azd) is not installed or not on PATH.'
}

Write-Host "Selecting azd environment '$EnvironmentName'..."
azd env select $EnvironmentName --no-prompt
if ($LASTEXITCODE -ne 0) {
    throw "Failed to select azd environment '$EnvironmentName'."
}

Write-Host 'Running azd provision preview...'
azd provision --preview --no-prompt
if ($LASTEXITCODE -ne 0) {
    throw 'azd provision --preview failed.'
}

if ($Apply) {
    Write-Host 'Applying infrastructure changes with azd provision...'
    azd provision --no-prompt
    if ($LASTEXITCODE -ne 0) {
        throw 'azd provision failed.'
    }
}

Write-Host 'Validation completed.'
