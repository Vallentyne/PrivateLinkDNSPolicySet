targetScope = 'resourceGroup'

@description('Azure region used for the smoke-test resources.')
param location string = resourceGroup().location

@description('Short, lowercase identifier used to make globally unique resource names.')
@minLength(3)
@maxLength(12)
param nameSuffix string

@description('Tags applied to every smoke-test resource that supports tags.')
param tags object = {}

// These are the public Azure DNS zones that this repository's policy initiative targets.
var dnsZoneNames = [
  #disable-next-line no-hardcoded-env-urls
  'privatelink.blob.core.windows.net'
  'privatelink.vaultcore.azure.net'
  'privatelink.azconfig.io'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.api.azureml.ms'
  'privatelink.notebooks.azure.net'
]

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-dns-policy-smoke-${nameSuffix}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.42.0.0/16'
      ]
    }
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: virtualNetwork
  name: 'private-endpoints'
  properties: {
    addressPrefix: '10.42.1.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in dnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'stsmoke${nameSuffix}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-smoke-${nameSuffix}'
  location: location
  tags: tags
  properties: {
    accessPolicies: []
    enableRbacAuthorization: true
    enableSoftDelete: true
    publicNetworkAccess: 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
    softDeleteRetentionInDays: 7
    tenantId: tenant().tenantId
  }
}

resource appConfiguration 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: 'appcs-smoke-${nameSuffix}'
  location: location
  tags: tags
  sku: {
    name: 'standard'
  }
  properties: {
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'ais-smoke-${nameSuffix}'
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: 'ais-smoke-${nameSuffix}'
    publicNetworkAccess: 'Enabled'
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-smoke-${nameSuffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource machineLearningWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: 'mlw-smoke-${nameSuffix}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    applicationInsights: applicationInsights.id
    keyVault: keyVault.id
    publicNetworkAccess: 'Enabled'
    storageAccount: storageAccount.id
  }
}

output subnetId string = privateEndpointSubnet.id
output targetResourceIds object = {
  aiServices: aiServices.id
  appConfiguration: appConfiguration.id
  keyVault: keyVault.id
  machineLearning: machineLearningWorkspace.id
  storageBlob: storageAccount.id
}
output dnsZoneNames array = dnsZoneNames