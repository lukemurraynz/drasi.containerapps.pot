@description('Azure region')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('Tags')
param tags object = {}

// Basic C0 does not support VNet injection - accessible from ACA via outbound TLS connection
resource redisCache 'Microsoft.Cache/redis@2024-03-01' = {
  name: '${namePrefix}-redis'
  location: location
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisConfiguration: {}
  }
  tags: tags
}

output redisHost string = redisCache.properties.hostName
output redisId string = redisCache.id
output redisPrimaryKey string = listKeys(redisCache.id, '2024-03-01').primaryKey
