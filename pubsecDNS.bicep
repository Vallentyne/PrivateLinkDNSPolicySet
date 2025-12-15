// ----------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
//
// THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, 
// EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES 
// OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
// ----------------------------------------------------------------------------------

targetScope = 'managementGroup'

@description('Management Group scope for the policy definition.')
param policyDefinitionManagementGroupId string

/*
Format of the array of objects
[
  {
    privateLinkServiceNamespace: 'Microsoft.AzureCosmosDB/databaseAccounts'
    zone: 'privatelink.documents.azure.com'
    filterLocationLike: '*' // when Private DNS Zone is not scoped to a region
    groupId: 'SQL'
    privateDnsZoneConfigs: [
      'privatelink.documents.azure.com'
    ]
  }
  {
    privateLinkServiceNamespace: 'Microsoft.ContainerService/managedCluster'
    zone: 'privatelink.canadacentral.azmk8s.io'
    filterLocationLike: 'canadacentral' // when Private DNS Zone is scoped to a region
    groupId: 'management'
    privateDnsZoneConfigs: [
      'privatelink.canadacentral.azmk8s.io'
    ]
  }
]
*/
@description('An array of Private DNS Zones to define as policies.')
param privateDNSZones array

var policySetName = 'custom-central-dns-private-endpoints'
var policySetDisplayName = 'Custom - Central DNS for Private Endpoints'

var customPolicyDefinitionMgScope = tenantResourceId('Microsoft.Management/managementGroups', policyDefinitionManagementGroupId)
var customPolicyDefinition = json(loadTextContent('templates/DNS-PrivateEndpoints/azurepolicy.json'))

// Map of services that have built-in policies with their policy GUIDs
var builtInPolicyMap = {
  'Microsoft.KeyVault/vaults-vault': 'ac673a9a-f77d-4846-b2d8-a57f8e1c01d4'
  'Microsoft.Storage/storageAccounts-blob': '75973700-529f-4de2-b794-fb9b6781b6b0'
  'Microsoft.Storage/storageAccounts-file': '6df98d03-368a-4438-8730-a93c4d7693d6'
  'Microsoft.Storage/storageAccounts-queue': 'bcff79fb-2b0d-47c9-97e5-3023479b00d1'
  'Microsoft.Storage/storageAccounts-table': '028bbd88-e9b5-461f-9424-a1b63a7bee1a'
  'Microsoft.Storage/storageAccounts-dfs': '83c6fe0f-2316-444a-99a1-1ecd8a7872ca'
  'Microsoft.Storage/storageAccounts-web': '9adab2a5-05ba-4fbd-831a-5bf958d04218'
  // 'Microsoft.CognitiveServices/accounts-account': 'c4bc6f10-cb41-49eb-b000-d5ab82e2a091' // Removed - needs custom policy for multi-zone support (AI Foundry)
  'Microsoft.Web/sites-sites': 'b318f84a-b872-429b-ac6d-a01b96814452'
  'Microsoft.ContainerRegistry/registries-registry': 'e9585a95-5b8c-4d03-b193-dc7eb5ac4c32'
  'Microsoft.SignalRService/signalR-signalR': 'b0e86710-7fb7-4a6c-a064-32e9b829509e'
  'Microsoft.EventGrid/topics-topic': 'baf19753-7502-405f-8745-370519b20483'
  'Microsoft.EventGrid/domains-domain': 'd389df0a-e0d7-4607-833c-75a6fdac2c2d'
  'Microsoft.EventHub/namespaces-namespace': 'ed66d4f5-8220-45dc-ab4a-20d1749c74e6'
  'Microsoft.ServiceBus/namespaces-namespace': 'f0fcf93c-c063-4071-9668-c47474bd3564'
  'Microsoft.Devices/IotHubs-iotHub': 'c99ce9c1-ced7-4c3e-aca0-10e69ce0cb02'
  'Microsoft.Cache/Redis-redisCache': 'e016b22b-e0eb-436d-8fd7-160c4eaed6e2'
  'Microsoft.Search/searchServices-searchService': 'fbc14a67-53e4-4932-abcc-2049c6706009'
  'Microsoft.Compute/diskAccesses-diskAccess': 'bc05b96c-0b36-4ca9-82f0-5c53f96ce05a'
  'Microsoft.MachineLearningServices/workspaces-amlworkspace': 'ee40564d-486e-4f68-a5ca-7a621edae0fb'
  'Microsoft.Synapse/workspaces-Sql': '1e5ed725-f16c-478b-bd4b-7bfa2f7940b9'
  'Microsoft.DataFactory/factories-dataFactory': '86cd96e1-1745-420d-94d4-d3f2fe415aa4'
  'Microsoft.StorageSync/storageSyncServices-afs': '06695360-db88-47f6-b976-7500d4297475'
  'Microsoft.DeviceUpdate/accounts-deviceUpdate': 'a222b93a-e6c2-4c01-817f-21e092455b2a'
  'Microsoft.IoTCentral/IoTApps-iotApp': 'd627d7c6-ded5-481a-8f2e-7e16b1e6faf6'
}

// Separate zones into those with built-in policies and those needing custom policies
var zonesWithBuiltInPolicies = [for zone in privateDNSZones: contains(builtInPolicyMap, '${zone.privateLinkServiceNamespace}-${zone.groupId}') ? zone : null]
var zonesNeedingCustomPolicies = [for zone in privateDNSZones: contains(builtInPolicyMap, '${zone.privateLinkServiceNamespace}-${zone.groupId}') ? null : zone]
var filteredBuiltInZones = filter(zonesWithBuiltInPolicies, z => z != null)
var filteredCustomZones = filter(zonesNeedingCustomPolicies, z => z != null)

// Built-in policy definitions (use Azure built-in policies)
var policySetDefinitionsBuiltIn = [for zone in filteredBuiltInZones: {
  groupNames: [
    'NETWORK'
  ]
  policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/${builtInPolicyMap['${zone.privateLinkServiceNamespace}-${zone.groupId}']}'
  policyDefinitionReferenceId: toLower('builtin-${zone.zone}-${zone.groupId}-${uniqueString(zone.privateLinkServiceNamespace)}')
  parameters: {
    privateDnsZoneId: {
      value: '[[concat(\'/subscriptions/\',parameters(\'privateDNSZoneSubscriptionId\'),\'/resourcegroups/\',parameters(\'privateDNSZoneResourceGroupName\'),\'/providers/Microsoft.Network/privateDnsZones/${zone.zone}\')]'
    }
    effect: {
      value: 'DeployIfNotExists'
    }
  }
}]

// Custom policy definitions (for services without built-in policies)
var policySetDefinitionsCustom = [for (privateDNSZone, i) in filteredCustomZones: {
  groupNames: [
    'NETWORK'
  ]
  policyDefinitionId: extensionResourceId(customPolicyDefinitionMgScope, 'Microsoft.Authorization/policyDefinitions', customPolicy[i].name)
  policyDefinitionReferenceId: toLower('custom-${privateDNSZone.zone}-${privateDNSZone.groupId}-${uniqueString(privateDNSZone.privateLinkServiceNamespace)}')
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
    privateDnsZoneSubscriptionId: {
      value: '[[parameters(\'privateDNSZoneSubscriptionId\')]'
    }
    privateDnsZoneResourceGroupName: {
      value: '[[parameters(\'privateDNSZoneResourceGroupName\')]'
    }
    privateDnsZoneConfigs: {
      value: privateDNSZone.privateDnsZoneConfigs
    }
  }
}]

// Deny policy commented out as it doesn't exist in the management group yet
// var policySetDefinitionsPrivateDNSZonesDeny = [
//   {
//     groupNames: [
//       'NETWORK'
//     ]
//     policyDefinitionId: extensionResourceId(customPolicyDefinitionMgScope, 'Microsoft.Authorization/policyDefinitions', 'DNS-PE-BlockPrivateDNSZones-PrivateLinks')
//     policyDefinitionReferenceId: toLower(replace('DNS - Deny privatelinks Private DNS Zones', ' ', '-'))
//     parameters: {}
//   }
// ]

// To batch delete policies using Azure CLI, use:
// az policy definition list --management-group pubsec --query "[?contains(id,'dns-pe-')].name" -o tsv | xargs -tn1 -P 5 az policy definition delete --management-group pubsec --name

// Only create custom policies for services that don't have built-in policies
resource customPolicy 'Microsoft.Authorization/policyDefinitions@2020-09-01' = [for privateDNSZone in filteredCustomZones: {
  name: 'dns-pe-${uniqueString(privateDNSZone.privateLinkServiceNamespace, privateDNSZone.zone, privateDNSZone.groupId)}'
  properties: {
    metadata: {
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

resource policySet 'Microsoft.Authorization/policySetDefinitions@2020-09-01' = {
  name: policySetName
  dependsOn: [
    customPolicy
  ]
  properties: {
    displayName: policySetDisplayName
    parameters: {
      privateDNSZoneSubscriptionId: {
        type: 'String'
      }
      privateDNSZoneResourceGroupName: {
        type: 'String'
      }
    }
    policyDefinitionGroups: [
      {
        name: 'NETWORK'
        displayName: 'DNS for Private Endpoints'
      }
    ]
    policyDefinitions: union(policySetDefinitionsBuiltIn, policySetDefinitionsCustom)
  }
}

output builtInPolicyCount int = length(filteredBuiltInZones)
output customPolicyCount int = length(filteredCustomZones)
output totalPolicyCount int = length(privateDNSZones)
