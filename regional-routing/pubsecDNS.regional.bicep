targetScope = 'managementGroup'

@description('Management group scope for the policy definition.')
param policyDefinitionManagementGroupId string

@description('Version identifier used in the regional initiative and policy definition names.')
param policyVersion string

var privateDNSZones = loadJsonContent('../pubsecDNS.parameters.json').parameters.privateDNSZones.value
var policySetName = 'custom-regional-dns-private-endpoints-${policyVersion}'
var policySetDisplayName = 'Custom - Regional DNS for Private Endpoints ${policyVersion}'
var customPolicyDefinitionMgScope = tenantResourceId('Microsoft.Management/managementGroups', policyDefinitionManagementGroupId)
var customPolicyDefinition = json(loadTextContent('templates/DNS-PrivateEndpoints/azurepolicy.json'))

// Multi-zone services are represented by one entry per catalog zone. The primary
// entry carries the complete privateDnsZoneConfigs array and is emitted once.
var routedZones = filter(privateDNSZones, zone => zone.zone == zone.privateDnsZoneConfigs[0])

resource customPolicy 'Microsoft.Authorization/policyDefinitions@2020-09-01' = [for privateDNSZone in routedZones: {
  name: 'dns-pe-regional-${uniqueString(privateDNSZone.privateLinkServiceNamespace, privateDNSZone.zone, privateDNSZone.groupId, policyVersion)}'
  properties: {
    metadata: {
      version: policyVersion
      routingBasis: 'privateEndpointLocation'
      privateLinkServiceNamespace: privateDNSZone.privateLinkServiceNamespace
      zone: privateDNSZone.zone
      groupId: privateDNSZone.groupId
      filterLocationLike: privateDNSZone.filterLocationLike
      privateDnsZoneConfigs: privateDNSZone.privateDnsZoneConfigs
    }
    displayName: '${customPolicyDefinition.properties.displayName} - ${privateDNSZone.zone} - ${privateDNSZone.privateLinkServiceNamespace} - ${privateDNSZone.groupId}'
    mode: customPolicyDefinition.properties.mode
    policyRule: customPolicyDefinition.properties.policyRule
    parameters: customPolicyDefinition.properties.parameters
  }
}]

var policySetDefinitions = [for (privateDNSZone, index) in routedZones: {
  groupNames: [
    'NETWORK'
  ]
  policyDefinitionId: extensionResourceId(customPolicyDefinitionMgScope, 'Microsoft.Authorization/policyDefinitions', customPolicy[index].name)
  policyDefinitionReferenceId: toLower('regional-${privateDNSZone.zone}-${privateDNSZone.groupId}-${uniqueString(privateDNSZone.privateLinkServiceNamespace)}')
  parameters: {
    privateLinkServiceNamespace: {
      value: privateDNSZone.privateLinkServiceNamespace
    }
    groupId: {
      value: privateDNSZone.groupId
    }
    filterLocationLike: {
      value: privateDNSZone.filterLocationLike
    }
    regionalPrivateDnsZoneTargets: {
      value: '[[parameters(\'regionalPrivateDnsZoneTargets\')]'
    }
    privateDnsZoneConfigs: {
      value: privateDNSZone.privateDnsZoneConfigs
    }
  }
}]

resource policySet 'Microsoft.Authorization/policySetDefinitions@2020-09-01' = {
  name: policySetName
  dependsOn: [
    customPolicy
  ]
  properties: {
    displayName: policySetDisplayName
    description: 'Routes private endpoints to a Private DNS zone resource group selected by the private endpoint location.'
    metadata: {
      version: policyVersion
      routingBasis: 'privateEndpointLocation'
      preview: true
    }
    parameters: {
      regionalPrivateDnsZoneTargets: {
        type: 'Object'
        metadata: {
          displayName: 'Regional Private DNS zone targets'
          description: 'Object keyed by lowercase Azure location. Each value contains subscriptionId and resourceGroupName.'
        }
      }
    }
    policyDefinitionGroups: [
      {
        name: 'NETWORK'
        displayName: 'Regional DNS for Private Endpoints'
      }
    ]
    policyDefinitions: policySetDefinitions
  }
}

output customPolicyCount int = length(routedZones)
output sourceZoneCount int = length(privateDNSZones)
