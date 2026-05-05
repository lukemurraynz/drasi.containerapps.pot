@description('Azure region')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('Virtual network address space (CIDR)')
param vnetAddressSpace string = '10.50.0.0/16'

@description('Container Apps infrastructure subnet address prefix')
param acaSubnetAddressPrefix string = '10.50.0.0/23'

@description('PostgreSQL subnet address prefix')
param postgresSubnetAddressPrefix string = '10.50.2.0/24'

@description('Tags')
param tags object = {}

var vnetName = '${namePrefix}-vnet'
var acaSubnetName = '${namePrefix}-aca-infra-snet'
var postgresSubnetName = '${namePrefix}-postgres-snet'

// Virtual network shell. Subnets are managed as child resources for idempotent re-deployments.
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
  }
  tags: tags
}

resource acaSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: acaSubnetName
  properties: {
    addressPrefix: acaSubnetAddressPrefix
    delegations: [
      {
        name: 'aca-delegation'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
    serviceEndpoints: [
      {
        service: 'Microsoft.KeyVault'
      }
      {
        service: 'Microsoft.Storage'
      }
    ]
  }
}

// PostgreSQL subnet with delegation (created separately to allow dependent resources to reference it)
resource postgresSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: postgresSubnetName
  properties: {
    addressPrefix: postgresSubnetAddressPrefix
    delegations: [
      {
        name: 'postgres-delegation'
        properties: {
          serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output acaSubnetResourceId string = acaSubnet.id
output postgresSubnetResourceId string = postgresSubnet.id
