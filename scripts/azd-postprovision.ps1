Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resourceGroup = $env:AZURE_RESOURCE_GROUP
$workloadPrefix = if ([string]::IsNullOrWhiteSpace($env:WORKLOADPREFIX)) { $env:WORKLOAD_PREFIX } else { $env:WORKLOADPREFIX }
$environmentCode = $env:ENVIRONMENT

if ([string]::IsNullOrWhiteSpace($resourceGroup)) {
    throw 'AZURE_RESOURCE_GROUP is required in the azd environment.'
}

if ([string]::IsNullOrWhiteSpace($workloadPrefix) -or [string]::IsNullOrWhiteSpace($environmentCode)) {
    throw 'WORKLOADPREFIX (or WORKLOAD_PREFIX) and ENVIRONMENT are required in the azd environment.'
}

$appName = "$workloadPrefix-$environmentCode-drasi"

Write-Host "Checking Container App '$appName' in resource group '$resourceGroup'..."

$provisioningState = az containerapp show --name $appName --resource-group $resourceGroup --query properties.provisioningState --output tsv
if ($LASTEXITCODE -ne 0) {
    throw "Unable to retrieve Container App '$appName'."
}

if ($provisioningState -ne 'Succeeded') {
    throw "Container App provisioning state is '$provisioningState' (expected 'Succeeded')."
}

$fqdn = az containerapp show --name $appName --resource-group $resourceGroup --query properties.configuration.ingress.fqdn --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($fqdn)) {
    throw "Container App ingress FQDN not found for '$appName'."
}

$healthUrl = "https://$fqdn/health"
Write-Host "Probing health endpoint: $healthUrl"

$maxAttempts = 10
$lastHealthError = $null
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec 15
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
            Write-Host 'Health check passed.'
            return
        }
    }
    catch {
        $lastHealthError = $_.Exception.Message
        if ($attempt -eq $maxAttempts) {
            break
        }
    }

    Start-Sleep -Seconds 10
}

Write-Warning "Health endpoint probe did not pass after $maxAttempts attempts. Last error: $lastHealthError"
Write-Host 'Falling back to Container App replica state validation...'

$runningReplicas = az containerapp replica list --name $appName --resource-group $resourceGroup --query "[?properties.runningState=='Running'].name" --output tsv
if ($LASTEXITCODE -ne 0) {
    throw "Health endpoint probe failed and replica validation could not be completed for '$appName'."
}

if ([string]::IsNullOrWhiteSpace($runningReplicas)) {
    throw "Health endpoint probe failed and no running replicas were found for '$appName'."
}

Write-Host "Replica validation passed. Running replicas: $runningReplicas"
