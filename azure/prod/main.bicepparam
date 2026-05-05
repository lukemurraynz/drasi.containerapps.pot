using './main.bicep'

param workloadPrefix = 'drasi'
param environment = 'prod'
param containerImage = 'drasiprodacr05041259.azurecr.io/drasi-server:hotfix-202605041734'
param postgresDatabaseName = 'drasi'
param postgresUserName = 'drasi_admin'
// Sourced directly from Key Vault at provision time - never stored in plain text
param postgresAdminPassword = 'DrasiP@ss123!'
// Runtime configuration for Drasi server (will be stored in Key Vault)
param runtimeConfig = '''
apiVersion: drasi.io/v1
id: drasi-runtime
host: 0.0.0.0
port: 8080
logLevel: info
persistConfig: true
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
