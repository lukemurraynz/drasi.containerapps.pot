targetScope = 'resourceGroup'

@description('Azure region')
param location string = resourceGroup().location

@description('Workload prefix for naming')
@minLength(3)
@maxLength(20)
param workloadPrefix string

@description('Environment code (dev, test, prod)')
param environment string

@description('Immutable Drasi image reference')
param containerImage string

@description('PostgreSQL database name')
param postgresDatabaseName string

@description('PostgreSQL user name')
param postgresUserName string

@secure()
@description('PostgreSQL administrator password')
param postgresAdminPassword string

@description('Runtime config YAML for Drasi')
param runtimeConfig string = '''
apiVersion: drasi.io/v1
id: drasi-runtime
host: 0.0.0.0
port: 8080
logLevel: info
persistConfig: true
stateStore:
  kind: redb
  path: ${STATE_STORE_PATH:-/drasi-persist/state.redb}
sources: []
queries: []
reactions: []
'''

@description('App tags')
param tags object = {}

var namePrefix = '${workloadPrefix}-${environment}'
var keyVaultBase = toLower(replace(namePrefix, '-', ''))
var keyVaultName = 'kv${take(keyVaultBase, 12)}${take(uniqueString(resourceGroup().id), 8)}'
var containerImageRegistryServer = split(containerImage, '/')[0]

// ============================================================================
// Module Execution Order (dependencies flow downward)
// ============================================================================

// 1. Network - creates VNet + subnets (no dependencies)
module network '../modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
  }
}

// 1b. KeyVault - creates Key Vault + initial secrets (no dependencies)
module keyvault '../modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    namePrefix: namePrefix
    postgresPassword: postgresAdminPassword
    runtimeConfig: runtimeConfig
    tags: tags
  }
}

// 2. Observability - creates Log Analytics + App Insights (no dependencies)
module observability '../modules/observability.bicep' = {
  name: 'observability'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
  }
}

// 3. ACA Environment - depends on network (subnet) and observability (log workspace)
module acaEnvironment '../modules/aca-environment.bicep' = {
  name: 'aca-environment'
  params: {
    location: location
    namePrefix: namePrefix
    infrastructureSubnetResourceId: network.outputs.acaSubnetResourceId
    logAnalyticsWorkspaceResourceId: observability.outputs.logAnalyticsWorkspaceResourceId
    tags: tags
  }
}

// 3b. PostgreSQL - depends on network (subnet)
module postgres '../modules/postgres-runtime.bicep' = {
  name: 'postgres-runtime'
  params: {
    location: location
    namePrefix: namePrefix
    vnetName: network.outputs.vnetName
    postgresSubnetResourceId: network.outputs.postgresSubnetResourceId
    postgresAdminLogin: postgresUserName
    postgresAdminPassword: postgresAdminPassword
    postgresDatabaseName: postgresDatabaseName
    tags: tags
  }
}

// 3c. Redis - no dependencies
module redis '../modules/redis-runtime.bicep' = {
  name: 'redis-runtime'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
  }
}

// 3d. User-assigned identity for Drasi runtime (pre-provisioned so RBAC exists before app revision creation)
resource drasiRuntimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-drasi-mi'
  location: location
  tags: tags
}

// Store Redis primary key in Key Vault for Drasi to authenticate
// This runs after redis module completes
resource redisPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: '${keyVaultName}/drasi-redis-password'
  properties: {
    value: redis.outputs.redisPrimaryKey
  }
  dependsOn: [
    keyvault
  ]
}

// Grant Drasi runtime identity access to read secrets from Key Vault (pre-app deployment)
resource drasiKvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, keyVaultName, drasiRuntimeIdentity.id, 'drasi-kv-secrets-user-uami-v2')
  properties: {
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/4633458b-17de-408a-b874-0445c86b69e6'
    principalId: drasiRuntimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    keyvault
  ]
}

// AcrPull for this UAMI already exists in this environment.
// We intentionally avoid recreating role assignments to keep deployment idempotent.

// 4. Drasi Runtime - depends on all infrastructure modules and identity RBAC grants
module drasiRuntime '../modules/drasi-runtime.bicep' = {
  name: 'drasi-runtime'
  params: {
    location: location
    appName: '${namePrefix}-drasi'
    managedEnvironmentResourceId: acaEnvironment.outputs.managedEnvironmentResourceId
    containerImage: containerImage
    runtimeConfigSecretUri: 'https://${keyVaultName}${az.environment().suffixes.keyvaultDns}/secrets/drasi-runtime-config'
    postgresHost: postgres.outputs.postgresHost
    postgresDatabaseName: postgresDatabaseName
    postgresUserName: postgresUserName
    postgresPasswordSecretUri: 'https://${keyVaultName}${az.environment().suffixes.keyvaultDns}/secrets/drasi-postgres-password'
    redisHost: redis.outputs.redisHost
    redisPasswordSecretUri: 'https://${keyVaultName}${az.environment().suffixes.keyvaultDns}/secrets/drasi-redis-password'
    containerRegistryServer: containerImageRegistryServer
    workloadIdentityResourceId: drasiRuntimeIdentity.id
    appInsightsConnectionString: observability.outputs.applicationInsightsConnectionString
    tags: tags
  }
  dependsOn: [
    redisPasswordSecret
    drasiKvRoleAssignment
  ]
}

// ============================================================================
// Outputs
// ============================================================================

output drasiUrl string = drasiRuntime.outputs.drasiUrl
output docsUrl string = drasiRuntime.outputs.docsUrl
output managedEnvironmentId string = acaEnvironment.outputs.managedEnvironmentResourceId
output postgresHost string = postgres.outputs.postgresHost
output redisHost string = redis.outputs.redisHost
output keyVaultName string = keyVaultName
output acrLoginServer string = containerImageRegistryServer
