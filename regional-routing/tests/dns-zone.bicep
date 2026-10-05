targetScope = 'resourceGroup'

@description('Private DNS zone names used by the regional routing test.')
param zoneNames array

@description('Tags applied to the Private DNS zone.')
param tags object = {}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in zoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]
