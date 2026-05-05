@description('Azure region')
param location string

@description('Name prefix')
param namePrefix string

@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceResourceId string

@description('Optional subnet resource ID for ACA VNet injection. Leave empty for public environment.')
param infrastructureSubnetResourceId string = ''

@description('Tags')
param tags object

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  scope: resourceGroup()
  name: last(split(logAnalyticsWorkspaceResourceId, '/'))
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-aca-env'
  location: location
  properties: {
    vnetConfiguration: empty(infrastructureSubnetResourceId)
      ? null
      : {
          infrastructureSubnetId: infrastructureSubnetResourceId
          internal: false
        }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
  tags: tags
}

output managedEnvironmentResourceId string = managedEnvironment.id
