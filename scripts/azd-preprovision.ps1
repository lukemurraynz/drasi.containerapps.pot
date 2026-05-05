Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Building azd infra entrypoint (azure/prod/main.bicep)...'
az bicep build --file azure/prod/main.bicep | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'az bicep build failed. Attempting fallback to standalone bicep CLI...'

    $bicepCommand = Get-Command bicep -ErrorAction SilentlyContinue
    if (-not $bicepCommand) {
        throw 'Bicep build failed via az and standalone bicep CLI is not available on PATH.'
    }

    & $bicepCommand.Source build azure/prod/main.bicep | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Bicep build failed for azure/prod/main.bicep using both az bicep and standalone bicep CLI.'
    }
}

Write-Host 'Preprovision validation completed.'
