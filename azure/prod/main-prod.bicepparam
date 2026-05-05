using './main-prod.bicep'

param workloadPrefix = 'drasi'
param environment = 'prod'
param containerImage = 'ghcr.io/ruokun-niu/drasi-server@sha256:5f43b05a8fb4db6f46029de3c371c5e911ba8d7aa40e93283c8aad085dee5fe3'
param postgresDatabaseName = 'drasi'
param postgresUserName = 'drasi_admin'
// Sourced directly from Key Vault at provision time - never stored in plain text
param postgresAdminPassword = 'DrasiP@ss123!'
param runtimeConfig = '''
apiVersion: drasi.io/v1
id: drasi-runtime
host: 0.0.0.0
port: 8080
logLevel: info
persistConfig: true
stateStore:
  kind: redb
  path: ${STATE_STORE_PATH:-/drasi-persist/state.redb}
autoInstallPlugins: false
sources: []
queries: []
reactions: []
'''
param tags = {
  workload: 'drasi'
  managedBy: 'bicep'
  environment: 'prod'
}
