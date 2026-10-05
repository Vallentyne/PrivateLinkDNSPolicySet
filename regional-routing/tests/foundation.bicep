targetScope = 'subscription'

@description('Short lowercase identifier used to isolate a regional routing test run.')
@minLength(3)
@maxLength(12)
param nameSuffix string

@description('First private endpoint and DNS target region.')
param primaryLocation string = 'canadacentral'

@description('Second private endpoint and DNS target region.')
param secondaryLocation string = 'canadaeast'

@description('UTC timestamp after which the disposable smoke environment can be removed.')
param expiresOn string

var workloadResourceGroupName = 'rg-dns-regional-test-${nameSuffix}'
var primaryDnsResourceGroupName = 'rg-dns-regional-cc-${nameSuffix}'
var secondaryDnsResourceGroupName = 'rg-dns-regional-ce-${nameSuffix}'
#disable-next-line no-hardcoded-env-urls
var zoneNames = [
  #disable-next-line no-hardcoded-env-urls
  'privatelink.blob.core.windows.net'
  'privatelink.vaultcore.azure.net'
  'privatelink.azconfig.io'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.batch.azure.com'
]
var tags = {
  purpose: 'dns-regional-policy-smoke'
  runId: nameSuffix
  expiresOn: expiresOn
}

resource workloadResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: workloadResourceGroupName
  location: primaryLocation
  tags: tags
}

resource primaryDnsResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: primaryDnsResourceGroupName
  location: primaryLocation
  tags: tags
}

resource secondaryDnsResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: secondaryDnsResourceGroupName
  location: secondaryLocation
  tags: tags
}

module workload 'workload.bicep' = {
  scope: workloadResourceGroup
  params: {
    nameSuffix: nameSuffix
    primaryLocation: primaryLocation
    secondaryLocation: secondaryLocation
    tags: tags
  }
}

module primaryDnsZone 'dns-zone.bicep' = {
  scope: primaryDnsResourceGroup
  params: {
    zoneNames: zoneNames
    tags: tags
  }
}

module secondaryDnsZone 'dns-zone.bicep' = {
  scope: secondaryDnsResourceGroup
  params: {
    zoneNames: zoneNames
    tags: tags
  }
}

output primaryDnsResourceGroupName string = primaryDnsResourceGroup.name
output primaryLocation string = primaryLocation
output primarySubnetId string = workload.outputs.primarySubnetId
output secondaryDnsResourceGroupName string = secondaryDnsResourceGroup.name
output secondaryLocation string = secondaryLocation
output secondarySubnetId string = workload.outputs.secondarySubnetId
output targetResourceIds object = workload.outputs.targetResourceIds
output workloadResourceGroupId string = workloadResourceGroup.id
output workloadResourceGroupName string = workloadResourceGroup.name