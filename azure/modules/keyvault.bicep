@description('Azure region')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('PostgreSQL admin password to store')
@secure()
param postgresPassword string

@description('Runtime config YAML to store')
param runtimeConfig string

@description('Tags')
param tags object = {}

var keyVaultBase = toLower(replace(namePrefix, '-', ''))
var keyVaultName = 'kv${take(keyVaultBase, 12)}${take(uniqueString(resourceGroup().id), 8)}'

// Create Key Vault with RBAC authorization
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: az.tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
  tags: tags
}

// Store PostgreSQL password
resource postgresPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'drasi-postgres-password'
  properties: {
    value: postgresPassword
  }
}

// Store runtime config
resource runtimeConfigSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'drasi-runtime-config'
  properties: {
    value: runtimeConfig
  }
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
