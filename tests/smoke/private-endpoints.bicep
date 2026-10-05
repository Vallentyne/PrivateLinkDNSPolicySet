targetScope = 'resourceGroup'

@description('Azure region used for the private endpoints.')
param location string = resourceGroup().location

@description('Short identifier shared with the foundation deployment.')
param nameSuffix string

@description('Subnet resource ID produced by foundation.bicep.')
param subnetId string

@description('Storage account resource ID produced by foundation.bicep.')
param storageBlobResourceId string

@description('Key Vault resource ID produced by foundation.bicep.')
param keyVaultResourceId string

@description('App Configuration resource ID produced by foundation.bicep.')
param appConfigurationResourceId string

@description('AI Services account resource ID produced by foundation.bicep.')
param aiServicesResourceId string

@description('Azure Machine Learning workspace resource ID produced by foundation.bicep.')
param machineLearningResourceId string

@description('Azure Batch account resource ID produced by foundation.bicep.')
param batchResourceId string

@description('Canada East Azure Batch account resource ID produced by foundation.bicep.')
param batchSecondaryResourceId string

@description('Canada East Azure Batch account name produced by foundation.bicep.')
param batchSecondaryAccountName string

@description('DNS record name derived from the secondary Batch account node-management endpoint.')
param batchSecondaryNodeRecordName string

@description('Azure Managed Redis resource ID produced by foundation.bicep.')
param managedRedisResourceId string

@description('Tags applied to every private endpoint.')
param tags object = {}

var endpointDefinitions = [
  {
    name: 'pe-storage-blob-${nameSuffix}'
    targetResourceId: storageBlobResourceId
    groupId: 'blob'
    expectedZones: [
      #disable-next-line no-hardcoded-env-urls
      'privatelink.blob.core.windows.net'
    ]
  }
  {
    name: 'pe-key-vault-${nameSuffix}'
    targetResourceId: keyVaultResourceId
    groupId: 'vault'
    expectedZones: [
      'privatelink.vaultcore.azure.net'
    ]
  }
  {
    name: 'pe-app-configuration-${nameSuffix}'
    targetResourceId: appConfigurationResourceId
    groupId: 'configurationStores'
    expectedZones: [
      'privatelink.azconfig.io'
    ]
  }
  {
    name: 'pe-ai-services-${nameSuffix}'
    targetResourceId: aiServicesResourceId
    groupId: 'account'
    expectedZones: [
      'privatelink.cognitiveservices.azure.com'
      'privatelink.openai.azure.com'
      'privatelink.services.ai.azure.com'
    ]
  }
  {
    name: 'pe-machine-learning-${nameSuffix}'
    targetResourceId: machineLearningResourceId
    groupId: 'amlworkspace'
    expectedZones: [
      'privatelink.api.azureml.ms'
      'privatelink.notebooks.azure.net'
    ]
  }
  {
    name: 'pe-managed-redis-${nameSuffix}'
    targetResourceId: managedRedisResourceId
    groupId: 'redisEnterprise'
    expectedZones: [
      'privatelink.redis.azure.net'
    ]
  }
  {
    name: 'pe-batch-account-${nameSuffix}'
    targetResourceId: batchResourceId
    groupId: 'batchAccount'
    expectedZones: [
      'privatelink.batch.azure.com'
    ]
  }
  {
    name: 'pe-batch-node-management-${nameSuffix}'
    targetResourceId: batchResourceId
    groupId: 'nodeManagement'
    expectedZones: [
      'privatelink.batch.azure.com'
    ]
  }
  {
    name: 'pe-batch-account-canada-east-${nameSuffix}'
    targetResourceId: batchSecondaryResourceId
    groupId: 'batchAccount'
    expectedZones: [
      'privatelink.batch.azure.com'
    ]
    expectedRecordNames: [
      '${batchSecondaryAccountName}.canadaeast'
    ]
  }
  {
    name: 'pe-batch-node-management-canada-east-${nameSuffix}'
    targetResourceId: batchSecondaryResourceId
    groupId: 'nodeManagement'
    expectedZones: [
      'privatelink.batch.azure.com'
    ]
    expectedRecordNames: [
      batchSecondaryNodeRecordName
    ]
  }
]

resource privateEndpoints 'Microsoft.Network/privateEndpoints@2024-05-01' = [for endpoint in endpointDefinitions: {
  name: endpoint.name
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: endpoint.groupId
        properties: {
          groupIds: [
            endpoint.groupId
          ]
          privateLinkServiceId: endpoint.targetResourceId
        }
      }
    ]
    subnet: {
      id: subnetId
    }
  }
}]

output testCases array = [for endpoint in endpointDefinitions: {
  endpointName: endpoint.name
  expectedZones: endpoint.expectedZones
  expectedRecordNames: endpoint.?expectedRecordNames ?? []
  groupId: endpoint.groupId
}]