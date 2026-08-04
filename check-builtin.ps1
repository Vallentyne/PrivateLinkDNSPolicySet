$params = Get-Content .\pubsecDNS.parameters.json | ConvertFrom-Json

$builtInMap = @{
  'Microsoft.KeyVault/vaults-vault' = $true
  'Microsoft.Storage/storageAccounts-blob' = $true
  'Microsoft.Storage/storageAccounts-file' = $true
  'Microsoft.Storage/storageAccounts-queue' = $true
  'Microsoft.Storage/storageAccounts-table' = $true
  'Microsoft.Storage/storageAccounts-dfs' = $true
  'Microsoft.Storage/storageAccounts-web' = $true
  'Microsoft.Web/sites-sites' = $true
  'Microsoft.ContainerRegistry/registries-registry' = $true
  'Microsoft.SignalRService/signalR-signalR' = $true
  'Microsoft.EventGrid/topics-topic' = $true
  'Microsoft.EventGrid/domains-domain' = $true
  'Microsoft.EventHub/namespaces-namespace' = $true
  'Microsoft.ServiceBus/namespaces-namespace' = $true
  'Microsoft.Devices/IotHubs-iotHub' = $true
  'Microsoft.Cache/Redis-redisCache' = $true
  'Microsoft.Search/searchServices-searchService' = $true
  'Microsoft.Compute/diskAccesses-diskAccess' = $true
  'Microsoft.MachineLearningServices/workspaces-amlworkspace' = $true
  'Microsoft.Synapse/workspaces-Sql' = $true
  'Microsoft.DataFactory/factories-dataFactory' = $true
  'Microsoft.StorageSync/storageSyncServices-afs' = $true
  'Microsoft.DeviceUpdate/accounts-deviceUpdate' = $true
  'Microsoft.IoTCentral/IoTApps-iotApp' = $true
}

Write-Host "`n=== Built-In Policy Usage Check ===" -ForegroundColor Cyan
Write-Host "`nServices that have built-in policies available:" -ForegroundColor Green

$usingBuiltIn = @()
$shouldUseBuiltIn = @()

foreach ($zone in $params.parameters.privateDNSZones.value) {
    $key = "$($zone.privateLinkServiceNamespace)-$($zone.groupId)"
    if ($builtInMap.ContainsKey($key)) {
        $usingBuiltIn += $key
    }
}

Write-Host "  Found $($usingBuiltIn.Count) services using built-in policies" -ForegroundColor Green
Write-Host "`nBreakdown:" -ForegroundColor Cyan
Write-Host "  - Built-in policies (from map): $($builtInMap.Count)" -ForegroundColor White
Write-Host "  - Services in parameters: $($params.parameters.privateDNSZones.value.Count)" -ForegroundColor White
Write-Host "  - Using built-in: $($usingBuiltIn.Count)" -ForegroundColor Green
Write-Host "  - Custom policies needed: $($params.parameters.privateDNSZones.value.Count - $usingBuiltIn.Count)" -ForegroundColor Yellow

Write-Host "`n=== Services Using Built-In Policies ===" -ForegroundColor Green
$usingBuiltIn | Sort-Object | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }

Write-Host "`n=== Services Requiring Custom Policies ===" -ForegroundColor Yellow
$params.parameters.privateDNSZones.value | ForEach-Object {
    $key = "$($_.privateLinkServiceNamespace)-$($_.groupId)"
    if (-not $builtInMap.ContainsKey($key)) {
        Write-Host "  • $key" -ForegroundColor Yellow
    }
} | Sort-Object
