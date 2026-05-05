@description('Azure region')
param location string

@description('Container App name')
param appName string

@description('Container Apps managed environment resource ID')
param managedEnvironmentResourceId string

@description('Immutable Drasi image reference')
param containerImage string

@description('Key Vault secret URI for runtime server.yaml')
param runtimeConfigSecretUri string

@description('PostgreSQL host')
param postgresHost string

@description('PostgreSQL database')
param postgresDatabaseName string

@description('PostgreSQL user')
param postgresUserName string

@description('Key Vault secret URI for PostgreSQL password')
param postgresPasswordSecretUri string

@description('Redis host')
param redisHost string

@description('Key Vault secret URI for Redis password')
param redisPasswordSecretUri string

@description('Optional container registry server for managed-identity image pulls')
param containerRegistryServer string = ''

@description('Optional user-assigned identity resource ID used for registry pulls and Key Vault secret references')
param workloadIdentityResourceId string = ''

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Tags')
param tags object

@description('Azure Files share name for durable runtime state and config')
param runtimeFileShareName string = 'drasi-runtime'

var storageNameBase = toLower(replace(appName, '-', ''))
var storageAccountName = '${take(storageNameBase, 16)}${take(uniqueString(resourceGroup().id, appName, 'drasi-storage'), 8)}'
var useWorkloadIdentity = !empty(workloadIdentityResourceId)
var registryIdentity = useWorkloadIdentity ? workloadIdentityResourceId : 'system'
var secretIdentity = useWorkloadIdentity ? workloadIdentityResourceId : 'system'

resource runtimeStorage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
  tags: tags
}

resource runtimeShareService 'Microsoft.Storage/storageAccounts/fileServices@2024-01-01' = {
  parent: runtimeStorage
  name: 'default'
}

resource runtimeShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2024-01-01' = {
  parent: runtimeShareService
  name: runtimeFileShareName
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  scope: resourceGroup()
  name: last(split(managedEnvironmentResourceId, '/'))
}

resource managedEnvironmentStorage 'Microsoft.App/managedEnvironments/storages@2025-01-01' = {
  parent: managedEnvironment
  name: 'drasi-runtime-storage'
  properties: {
    azureFile: {
      accessMode: 'ReadWrite'
      accountName: runtimeStorage.name
      accountKey: runtimeStorage.listKeys().keys[0].value
      shareName: runtimeShare.name
    }
  }
}

resource drasiApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: useWorkloadIdentity
    ? {
        type: 'SystemAssigned,UserAssigned'
        userAssignedIdentities: {
          '${workloadIdentityResourceId}': {}
        }
      }
    : {
        type: 'SystemAssigned'
      }
  properties: {
    environmentId: managedEnvironmentResourceId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 8080
        transport: 'http'
      }
      registries: empty(containerRegistryServer)
        ? []
        : [
            {
              server: containerRegistryServer
              identity: registryIdentity
            }
          ]
      secrets: [
        {
          name: 'runtime-config'
          keyVaultUrl: runtimeConfigSecretUri
          identity: secretIdentity
        }
        {
          name: 'postgres-password'
          keyVaultUrl: postgresPasswordSecretUri
          identity: secretIdentity
        }
        {
          name: 'redis-password'
          keyVaultUrl: redisPasswordSecretUri
          identity: secretIdentity
        }
      ]
    }
    template: {
      terminationGracePeriodSeconds: 120
      containers: [
        {
          name: 'drasi-server'
          image: containerImage
          command: [
            '/bin/sh'
            '-c'
            'mkdir -p /drasi-persist && if [ ! -s /drasi-persist/server.yaml ]; then cp /config-secret/server.yaml /drasi-persist/server.yaml; fi && drasi-server --config /drasi-persist/server.yaml'
          ]
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsightsConnectionString
            }
            {
              name: 'POSTGRES_HOST'
              value: postgresHost
            }
            {
              name: 'POSTGRES_DATABASE'
              value: postgresDatabaseName
            }
            {
              name: 'POSTGRES_USER'
              value: postgresUserName
            }
            {
              name: 'POSTGRES_PASSWORD'
              secretRef: 'postgres-password'
            }
            {
              name: 'REDIS_HOST'
              value: redisHost
            }
            {
              name: 'REDIS_PASSWORD'
              secretRef: 'redis-password'
            }
            {
              name: 'STATE_STORE_PATH'
              value: '/drasi-persist/state.redb'
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 60
              periodSeconds: 10
              timeoutSeconds: 10
              failureThreshold: 30
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 20
              periodSeconds: 5
              timeoutSeconds: 5
              failureThreshold: 6
            }
          ]
          resources: {
            cpu: 4
            memory: '8Gi'
          }
          volumeMounts: [
            {
              volumeName: 'config-volume'
              mountPath: '/config-secret'
            }
            {
              volumeName: 'runtime-volume'
              mountPath: '/drasi-persist'
            }
          ]
        }
      ]
      volumes: [
        {
          name: 'config-volume'
          storageType: 'Secret'
          secrets: [
            {
              secretRef: 'runtime-config'
              path: 'server.yaml'
            }
          ]
        }
        {
          name: 'runtime-volume'
          storageType: 'AzureFile'
          storageName: managedEnvironmentStorage.name
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  tags: tags
}

output drasiUrl string = 'https://${drasiApp.properties.configuration.ingress.fqdn}'
output docsUrl string = 'https://${drasiApp.properties.configuration.ingress.fqdn}/api/v1/docs/'
output principalId string = drasiApp.identity.principalId
