@description('Azure region')
param location string

@description('Name prefix')
param namePrefix string

@description('Tags applied to resources')
param tags object

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
  tags: tags
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${namePrefix}-appi'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
  tags: tags
}

output logAnalyticsWorkspaceResourceId string = logAnalytics.id
output logAnalyticsWorkspaceCustomerId string = logAnalytics.properties.customerId
output applicationInsightsConnectionString string = appInsights.properties.ConnectionString
