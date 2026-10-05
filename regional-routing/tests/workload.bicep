targetScope = 'resourceGroup'

@description('Short lowercase identifier used for globally unique resource names.')
@minLength(3)
@maxLength(12)
param nameSuffix string

@description('First private endpoint region.')
param primaryLocation string = 'canadacentral'

@description('Second private endpoint region.')
param secondaryLocation string = 'canadaeast'

@description('Tags applied to test resources.')
param tags object = {}

resource primaryVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-regional-dns-cc-${nameSuffix}'
  location: primaryLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.51.0.0/16'
      ]
    }
  }
}

resource primaryPrivateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: primaryVirtualNetwork
  name: 'private-endpoints'
  properties: {
    addressPrefix: '10.51.1.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource secondaryVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-regional-dns-ce-${nameSuffix}'
  location: secondaryLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.52.0.0/16'
      ]
    }
  }
}

resource secondaryPrivateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: secondaryVirtualNetwork
  name: 'private-endpoints'
  properties: {
    addressPrefix: '10.52.1.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: 'stregional${nameSuffix}'
  location: primaryLocation
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-reg-${nameSuffix}'
  location: primaryLocation
  tags: tags
  properties: {
    accessPolicies: []
    enablePurgeProtection: true
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
  name: 'appcs-reg-${nameSuffix}'
  location: primaryLocation
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
  name: 'ais-reg-${nameSuffix}'
  location: primaryLocation
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: 'ais-reg-${nameSuffix}'
    publicNetworkAccess: 'Enabled'
  }
}

resource batchAccount 'Microsoft.Batch/batchAccounts@2024-07-01' = {
  name: 'bareg${nameSuffix}'
  location: primaryLocation
  tags: tags
  properties: {
    poolAllocationMode: 'BatchService'
    publicNetworkAccess: 'Enabled'
  }
}

output primarySubnetId string = primaryPrivateEndpointSubnet.id
output secondarySubnetId string = secondaryPrivateEndpointSubnet.id
output targetResourceIds object = {
  aiServices: aiServices.id
  appConfiguration: appConfiguration.id
  batch: batchAccount.id
  keyVault: keyVault.id
  storageBlob: storageAccount.id
}
