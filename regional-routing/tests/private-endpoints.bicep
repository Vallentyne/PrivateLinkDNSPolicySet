targetScope = 'resourceGroup'

@description('Short identifier shared with the foundation deployment.')
param nameSuffix string

@description('First private endpoint region.')
param primaryLocation string = 'canadacentral'

@description('Second private endpoint region.')
param secondaryLocation string = 'canadaeast'

@description('Subnet resource ID in the first region.')
param primarySubnetId string

@description('Subnet resource ID in the second region.')
param secondarySubnetId string

@description('Resource IDs targeted by the private endpoints.')
param targetResourceIds object

@description('Tags applied to the private endpoints.')
param tags object = {}

var serviceEndpoints = loadJsonContent('smoke-matrix.json').routes

var primaryEndpointDefinitions = [for service in serviceEndpoints: {
  name: 'pe-${service.key}-cc-${nameSuffix}'
  connectionName: 'pe-${service.key}-cc-${nameSuffix}'
  location: primaryLocation
  subnetId: primarySubnetId
  targetResourceId: targetResourceIds[service.targetResourceKey]
  groupId: service.groupId
  resourceNamespace: service.resourceNamespace
  expectedZones: service.expectedZones
  route: 'primary'
}]

var secondaryEndpointDefinitions = [for service in serviceEndpoints: {
  name: 'pe-${service.key}-ce-${nameSuffix}'
  connectionName: 'pe-${service.key}-ce-${nameSuffix}'
  location: secondaryLocation
  subnetId: secondarySubnetId
  targetResourceId: targetResourceIds[service.targetResourceKey]
  groupId: service.groupId
  resourceNamespace: service.resourceNamespace
  expectedZones: service.expectedZones
  route: 'secondary'
}]

var endpointDefinitions = concat(primaryEndpointDefinitions, secondaryEndpointDefinitions)

@batchSize(1)
resource privateEndpoints 'Microsoft.Network/privateEndpoints@2024-05-01' = [for endpoint in endpointDefinitions: {
  name: endpoint.name
  location: endpoint.location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: endpoint.connectionName
        properties: {
          groupIds: [
            endpoint.groupId
          ]
          privateLinkServiceId: endpoint.targetResourceId
        }
      }
    ]
    subnet: {
      id: endpoint.subnetId
    }
  }
}]

output testCases array = [for endpoint in endpointDefinitions: {
  endpointName: endpoint.name
  expectedZones: endpoint.expectedZones
  groupId: endpoint.groupId
  resourceNamespace: endpoint.resourceNamespace
  route: endpoint.route
}]
