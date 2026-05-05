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

@description('Drasi runtime configuration (YAML)')
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

module prod './main-prod.bicep' = {
  name: 'main-prod'
  params: {
    location: location
    workloadPrefix: workloadPrefix
    environment: environment
    containerImage: containerImage
    postgresDatabaseName: postgresDatabaseName
    postgresUserName: postgresUserName
    postgresAdminPassword: postgresAdminPassword
    runtimeConfig: runtimeConfig
    tags: tags
  }
}

output drasiUrl string = prod.outputs.drasiUrl
output docsUrl string = prod.outputs.docsUrl
output managedEnvironmentId string = prod.outputs.managedEnvironmentId
output acrLoginServer string = prod.outputs.acrLoginServer
