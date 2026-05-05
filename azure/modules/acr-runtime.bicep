@description('Azure region')
param location string

@description('Container registry name')
param registryName string

@description('Tags')
param tags object

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

output registryId string = containerRegistry.id
output registryName string = containerRegistry.name
output loginServer string = containerRegistry.properties.loginServer
