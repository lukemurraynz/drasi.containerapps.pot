param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$EnvironmentName,

    [Parameter()]
    [switch]$SkipDeploy
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

Write-Host 'Provisioning infrastructure with azd...'
azd provision --no-prompt
if ($LASTEXITCODE -ne 0) {
    throw 'azd provision failed.'
}

if ($SkipDeploy) {
    Write-Warning 'Skipping azd deploy because -SkipDeploy was provided.'
    Write-Host 'azd deployment completed successfully (provision only).'
    return
}

Write-Host 'Deploying services with azd...'
azd deploy --no-prompt
if ($LASTEXITCODE -ne 0) {
    throw 'azd deploy failed.'
}

Write-Host 'azd deployment completed successfully.'
