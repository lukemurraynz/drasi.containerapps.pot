@description('Azure region')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('Virtual network name for private subnet creation and DNS zone linking')
param vnetName string

@description('PostgreSQL subnet resource ID (from network module)')
param postgresSubnetResourceId string

@description('PostgreSQL administrator login')
param postgresAdminLogin string

@secure()
@description('PostgreSQL administrator password')
param postgresAdminPassword string

@description('Database name to create')
param postgresDatabaseName string

@description('Tags')
param tags object = {}

var serverName = '${namePrefix}-postgres'

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: vnetName
}

// Note: postgresSubnet is now passed as a resource ID parameter from network module

// Private DNS zone required for VNet-integrated Flexible Server; zone name must match server name
resource postgresDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${serverName}.private.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

resource postgresDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: postgresDnsZone
  name: '${serverName}-vnet-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    network: {
      delegatedSubnetResourceId: postgresSubnetResourceId
      privateDnsZoneArmResourceId: postgresDnsZone.id
    }
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
  }
  tags: tags
  // DNS zone link must exist before server can register its private DNS entry
  dependsOn: [
    postgresDnsZoneLink
  ]
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgresServer
  name: postgresDatabaseName
}

output postgresHost string = postgresServer.properties.fullyQualifiedDomainName
output postgresServerId string = postgresServer.id
