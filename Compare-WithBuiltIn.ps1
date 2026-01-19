# Compare custom policy set with Microsoft's built-in "Configure Azure PaaS services to use private DNS zones"

# Your custom policy set services (from pubsecDNS.parameters.json and bicep)
$customServices = @{
    # Built-in policies used (20)
    'Microsoft.KeyVault/vaults|vault' = 'Built-in'
    'Microsoft.Storage/storageAccounts|blob' = 'Built-in'
    'Microsoft.Storage/storageAccounts|file' = 'Built-in'
    'Microsoft.Storage/storageAccounts|queue' = 'Built-in'
    'Microsoft.Storage/storageAccounts|table' = 'Built-in'
    'Microsoft.Storage/storageAccounts|dfs' = 'Built-in'
    'Microsoft.Storage/storageAccounts|web' = 'Built-in'
    'Microsoft.Web/sites|sites' = 'Built-in'
    'Microsoft.ContainerRegistry/registries|registry' = 'Built-in'
    'Microsoft.SignalRService/signalR|signalR' = 'Built-in'
    'Microsoft.EventGrid/topics|topic' = 'Built-in'
    'Microsoft.EventGrid/domains|domain' = 'Built-in'
    'Microsoft.EventHub/namespaces|namespace' = 'Built-in (EventHub)'
    'Microsoft.ServiceBus/namespaces|namespace' = 'Built-in (ServiceBus)'
    'Microsoft.Devices/IotHubs|iotHub' = 'Built-in'
    'Microsoft.Cache/Redis|redisCache' = 'Built-in'
    'Microsoft.Search/searchServices|searchService' = 'Built-in'
    'Microsoft.Compute/diskAccesses|diskAccess' = 'Built-in'
    'Microsoft.MachineLearningServices/workspaces|amlworkspace' = 'Built-in (2 zones)'
    'Microsoft.Synapse/workspaces|Sql' = 'Built-in'
    'Microsoft.DataFactory/factories|dataFactory' = 'Built-in'
    'Microsoft.StorageSync/storageSyncServices|afs' = 'Built-in'
    'Microsoft.DeviceUpdate/accounts|deviceUpdate' = 'Built-in'
    'Microsoft.IoTCentral/IoTApps|iotApp' = 'Built-in'
    
    # Custom policies (30 configurations)
    'Microsoft.Automation/automationAccounts|Webhook' = 'Custom'
    'Microsoft.Automation/automationAccounts|DSCAndHybridWorker' = 'Custom'
    'Microsoft.Sql/servers|sqlServer' = 'Custom'
    'Microsoft.Synapse/workspaces|SqlOnDemand' = 'Custom'
    'Microsoft.Synapse/workspaces|Dev' = 'Custom'
    'Microsoft.Synapse/privateLinkHubs|Web' = 'Custom'
    'Microsoft.Storage/storageAccounts|blob_secondary' = 'Custom'
    'Microsoft.Storage/storageAccounts|table_secondary' = 'Custom'
    'Microsoft.Storage/storageAccounts|queue_secondary' = 'Custom'
    'Microsoft.Storage/storageAccounts|file_secondary' = 'Custom'
    'Microsoft.Storage/storageAccounts|web_secondary' = 'Custom'
    'Microsoft.Storage/storageAccounts|dfs_secondary' = 'Custom'
    'Microsoft.DocumentDB/databaseAccounts|SQL' = 'Custom'
    'Microsoft.DocumentDB/databaseAccounts|MongoDB' = 'Custom'
    'Microsoft.DocumentDB/mongoClusters|MongoCluster' = 'Custom (MongoDB vCore)'
    'Microsoft.DocumentDB/databaseAccounts|Cassandra' = 'Custom'
    'Microsoft.DocumentDB/databaseAccounts|Gremlin' = 'Custom'
    'Microsoft.DocumentDB/databaseAccounts|Table' = 'Custom'
    'Microsoft.DBforPostgreSQL/servers|postgresqlServer' = 'Custom'
    'Microsoft.DBforMySQL/servers|mysqlServer' = 'Custom (Single Server)'
    'Microsoft.DBforMySQL/flexibleServers|mysqlServer' = 'Custom (Flexible Server)'
    'Microsoft.DBforMariaDB/servers|mariadbServer' = 'Custom'
    'Microsoft.ContainerService/managedCluster|management' = 'Custom (2 regions)'
    'Microsoft.RecoveryServices/vaults|AzureBackup' = 'Custom (2 regions)'
    'Microsoft.RecoveryServices/vaults|AzureSiteRecovery' = 'Custom'
    'Microsoft.CognitiveServices/accounts|account' = 'Custom (3 zones - AI Foundry)'
    'Microsoft.Cache/RedisEnterprise|redisCache' = 'Custom'
    'Microsoft.HealthcareApis/services|fhir' = 'Custom'
}

# Microsoft built-in initiative services (as of latest documentation)
$builtInServices = @{
    'Microsoft.Sql/servers|sqlServer' = 'Built-in'
    'Microsoft.Storage/storageAccounts|blob' = 'Built-in'
    'Microsoft.Storage/storageAccounts|blob_secondary' = 'Built-in'
    'Microsoft.Storage/storageAccounts|table' = 'Built-in'
    'Microsoft.Storage/storageAccounts|table_secondary' = 'Built-in'
    'Microsoft.Storage/storageAccounts|queue' = 'Built-in'
    'Microsoft.Storage/storageAccounts|queue_secondary' = 'Built-in'
    'Microsoft.Storage/storageAccounts|file' = 'Built-in'
    'Microsoft.Storage/storageAccounts|file_secondary' = 'Built-in'
    'Microsoft.Storage/storageAccounts|web' = 'Built-in'
    'Microsoft.Storage/storageAccounts|web_secondary' = 'Built-in'
    'Microsoft.Storage/storageAccounts|dfs' = 'Built-in'
    'Microsoft.Storage/storageAccounts|dfs_secondary' = 'Built-in'
    'Microsoft.DocumentDB/databaseAccounts|SQL' = 'Built-in'
    'Microsoft.DocumentDB/databaseAccounts|MongoDB' = 'Built-in'
    'Microsoft.DocumentDB/databaseAccounts|Cassandra' = 'Built-in'
    'Microsoft.DocumentDB/databaseAccounts|Gremlin' = 'Built-in'
    'Microsoft.DocumentDB/databaseAccounts|Table' = 'Built-in'
    'Microsoft.DBforPostgreSQL/servers|postgresqlServer' = 'Built-in'
    'Microsoft.DBforMySQL/servers|mysqlServer' = 'Built-in'
    'Microsoft.DBforMariaDB/servers|mariadbServer' = 'Built-in'
    'Microsoft.KeyVault/vaults|vault' = 'Built-in'
    'Microsoft.EventHub/namespaces|namespace' = 'Built-in'
    'Microsoft.ServiceBus/namespaces|namespace' = 'Built-in'
    'Microsoft.Web/sites|sites' = 'Built-in'
    'Microsoft.ContainerRegistry/registries|registry' = 'Built-in'
    'Microsoft.EventGrid/domains|domain' = 'Built-in'
    'Microsoft.EventGrid/topics|topic' = 'Built-in'
    'Microsoft.Devices/IotHubs|iotHub' = 'Built-in'
    'Microsoft.SignalRService/signalR|signalR' = 'Built-in'
    'Microsoft.Search/searchServices|searchService' = 'Built-in'
    'Microsoft.CognitiveServices/accounts|account' = 'Built-in (single zone)'
    'Microsoft.ContainerService/managedClusters|management' = 'Built-in'
    'Microsoft.Synapse/workspaces|Sql' = 'Built-in'
    'Microsoft.Synapse/workspaces|SqlOnDemand' = 'Built-in'
    'Microsoft.Synapse/workspaces|Dev' = 'Built-in'
    'Microsoft.Synapse/privateLinkHubs|Web' = 'Built-in'
    'Microsoft.MachineLearningServices/workspaces|amlworkspace' = 'Built-in'
    'Microsoft.Batch/batchAccounts|batchAccount' = 'Built-in'
    'Microsoft.Batch/batchAccounts|nodeManagement' = 'Built-in'
    'Microsoft.RecoveryServices/vaults|AzureBackup' = 'Built-in'
    'Microsoft.RecoveryServices/vaults|AzureSiteRecovery' = 'Built-in'
    'Microsoft.DataFactory/factories|dataFactory' = 'Built-in'
    'Microsoft.Cache/Redis|redisCache' = 'Built-in'
    'Microsoft.Automation/automationAccounts|Webhook' = 'Built-in'
    'Microsoft.Automation/automationAccounts|DSCAndHybridWorker' = 'Built-in'
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "POLICY SET COMPARISON" -ForegroundColor Cyan
Write-Host "Custom vs Microsoft Built-in" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "YOUR CUSTOM POLICY SET: $($customServices.Keys.Count) service configurations" -ForegroundColor Green
Write-Host "MICROSOFT BUILT-IN: ~$($builtInServices.Keys.Count) service configurations`n" -ForegroundColor Yellow

# Services in YOUR custom but NOT in Microsoft built-in
Write-Host "`n--- SERVICES IN YOUR CUSTOM (NOT in Microsoft Built-in) ---" -ForegroundColor Green
$customOnly = $customServices.Keys | Where-Object { -not $builtInServices.ContainsKey($_) }
foreach ($svc in ($customOnly | Sort-Object)) {
    $parts = $svc.Split('|')
    Write-Host "  ✓ $($parts[0]) [$($parts[1])] - $($customServices[$svc])" -ForegroundColor Green
}
Write-Host "  Total: $($customOnly.Count)`n" -ForegroundColor Green

# Services in Microsoft built-in but NOT in YOUR custom
Write-Host "`n--- SERVICES IN MICROSOFT BUILT-IN (NOT in Your Custom) ---" -ForegroundColor Yellow
$builtInOnly = $builtInServices.Keys | Where-Object { -not $customServices.ContainsKey($_) }
foreach ($svc in ($builtInOnly | Sort-Object)) {
    $parts = $svc.Split('|')
    Write-Host "  ⚠ $($parts[0]) [$($parts[1])] - Missing" -ForegroundColor Yellow
}
Write-Host "  Total: $($builtInOnly.Count)`n" -ForegroundColor Yellow

# Services in BOTH
Write-Host "`n--- SERVICES IN BOTH (Common Coverage) ---" -ForegroundColor Cyan
$common = $customServices.Keys | Where-Object { $builtInServices.ContainsKey($_) }
foreach ($svc in ($common | Sort-Object)) {
    $parts = $svc.Split('|')
    Write-Host "  ✓ $($parts[0]) [$($parts[1])] - Custom: $($customServices[$svc]) | Built-in: $($builtInServices[$svc])" -ForegroundColor Cyan
}
Write-Host "  Total: $($common.Count)`n" -ForegroundColor Cyan

# Key Differences Summary
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "KEY DIFFERENCES" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

Write-Host "1. AZURE AI FOUNDRY (Cognitive Services)" -ForegroundColor Magenta
Write-Host "   Your Custom: Multi-zone support (3 DNS zones)" -ForegroundColor Green
Write-Host "     - privatelink.cognitiveservices.azure.com"
Write-Host "     - privatelink.openai.azure.com"
Write-Host "     - privatelink.services.ai.azure.com"
Write-Host "   Microsoft: Single zone only (privatelink.cognitiveservices.azure.com)" -ForegroundColor Yellow
Write-Host ""

Write-Host "2. COSMOS DB MONGODB vCORE" -ForegroundColor Magenta
Write-Host "   Your Custom: Includes MongoDB vCore (mongoClusters)" -ForegroundColor Green
Write-Host "   Microsoft: Not included" -ForegroundColor Yellow
Write-Host ""

Write-Host "3. MYSQL FLEXIBLE SERVER" -ForegroundColor Magenta
Write-Host "   Your Custom: Separate config for Flexible Server" -ForegroundColor Green
Write-Host "   Microsoft: Only MySQL Single Server" -ForegroundColor Yellow
Write-Host ""

Write-Host "4. REDIS ENTERPRISE" -ForegroundColor Magenta
Write-Host "   Your Custom: Includes Redis Enterprise" -ForegroundColor Green
Write-Host "   Microsoft: Only Redis (standard)" -ForegroundColor Yellow
Write-Host ""

Write-Host "5. HEALTHCARE APIS" -ForegroundColor Magenta
Write-Host "   Your Custom: Includes Healthcare APIs (FHIR)" -ForegroundColor Green
Write-Host "   Microsoft: Not included" -ForegroundColor Yellow
Write-Host ""

Write-Host "6. BATCH ACCOUNTS" -ForegroundColor Magenta
Write-Host "   Your Custom: Not included" -ForegroundColor Yellow
Write-Host "   Microsoft: Includes Batch (batchAccount, nodeManagement)" -ForegroundColor Green
Write-Host ""

Write-Host "7. VERSIONING & FLEXIBILITY" -ForegroundColor Magenta
Write-Host "   Your Custom: Policy version parameter (v2) for easy updates" -ForegroundColor Green
Write-Host "   Microsoft: Fixed built-in definitions" -ForegroundColor Yellow
Write-Host ""

Write-Host "`n========================================`n" -ForegroundColor Cyan
