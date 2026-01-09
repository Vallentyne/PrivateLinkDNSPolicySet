# Script to validate all Azure Private DNS policies and build a comprehensive policy set

$allPolicyIds = @(
    @{id="06695360-db88-47f6-b976-7500d4297475"; ref="DINE-Private-DNS-Azure-File-Sync"; param="azureFilePrivateDnsZoneId"; zone="privatelink.afs.azure.net"},
    @{id="6dd01e4f-1be1-4e80-9d0b-d109e04cb064"; ref="DINE-Private-DNS-Azure-Automation-Webhook"; param="azureAutomationWebhookPrivateDnsZoneId"; zone="privatelink.azure-automation.net"},
    @{id="a63cc0bd-cda4-4178-b705-37dc439d3e0f"; ref="DINE-Private-DNS-Azure-Cosmos-SQL"; param="azureCosmosSQLPrivateDnsZoneId"; zone="privatelink.documents.azure.com"},
    @{id="0fcec92b-b7b1-4ad5-aa09-96447c4e0e37"; ref="DINE-Private-DNS-Azure-Cosmos-MongoDB"; param="azureCosmosMongoPrivateDnsZoneId"; zone="privatelink.mongo.cosmos.azure.com"},
    @{id="a64eecf2-3ca5-4954-9e91-c66e9cc9e54b"; ref="DINE-Private-DNS-Azure-Cosmos-Cassandra"; param="azureCosmosCassandraPrivateDnsZoneId"; zone="privatelink.cassandra.cosmos.azure.com"},
    @{id="73a7e382-4c42-434a-91b1-0b929280361e"; ref="DINE-Private-DNS-Azure-Cosmos-Gremlin"; param="azureCosmosGremlinPrivateDnsZoneId"; zone="privatelink.gremlin.cosmos.azure.com"},
    @{id="f8d36f6d-9b6d-4e60-a134-e97bf43e1e8e"; ref="DINE-Private-DNS-Azure-Cosmos-Table"; param="azureCosmosTablePrivateDnsZoneId"; zone="privatelink.table.cosmos.azure.com"},
    @{id="86cd96e1-1745-420d-94d4-d3f2fe415aa4"; ref="DINE-Private-DNS-Azure-DataFactory"; param="azureDataFactoryPrivateDnsZoneId"; zone="privatelink.datafactory.azure.net"},
    @{id="0eddd7f3-3d9b-4927-a07a-806e8ac9486c"; ref="DINE-Private-DNS-Azure-Databricks"; param="azureDatabricksPrivateDnsZoneId"; zone="privatelink.azuredatabricks.net"},
    @{id="43d6e3bd-fc6a-4b44-8b4d-ac1f52f84e8b"; ref="DINE-Private-DNS-Azure-HDInsight"; param="azureHDInsightPrivateDnsZoneId"; zone="privatelink.azurehdinsight.net"},
    @{id="7590a335-57cf-4c95-babd-adc564f8959e"; ref="DINE-Private-DNS-Azure-Migrate"; param="azureMigratePrivateDnsZoneId"; zone="privatelink.prod.migration.windowsazure.com"},
    @{id="75973700-529f-4de2-b794-fb9b6781b6b0"; ref="DINE-Private-DNS-Azure-Storage-Blob"; param="azureStorageBlobPrivateDnsZoneId"; zone="privatelink.blob.core.windows.net"},
    @{id="d847d34b-9337-4e2d-99a5-767e5ac9c582"; ref="DINE-Private-DNS-Azure-Storage-Blob-Sec"; param="azureStorageBlobSecPrivateDnsZoneId"; zone="privatelink.blob.core.windows.net"},
    @{id="bcff79fb-2b0d-47c9-97e5-3023479b00d1"; ref="DINE-Private-DNS-Azure-Storage-Queue"; param="azureStorageQueuePrivateDnsZoneId"; zone="privatelink.queue.core.windows.net"},
    @{id="da9b4ae8-5ddc-48c5-b9c0-25f8abf7a3d6"; ref="DINE-Private-DNS-Azure-Storage-Queue-Sec"; param="azureStorageQueueSecPrivateDnsZoneId"; zone="privatelink.queue.core.windows.net"},
    @{id="6df98d03-368a-4438-8730-a93c4d7693d6"; ref="DINE-Private-DNS-Azure-Storage-File"; param="azureStorageFilePrivateDnsZoneId"; zone="privatelink.file.core.windows.net"},
    @{id="9adab2a5-05ba-4fbd-831a-5bf958d04218"; ref="DINE-Private-DNS-Azure-Storage-StaticWeb"; param="azureStorageStaticWebPrivateDnsZoneId"; zone="privatelink.web.core.windows.net"},
    @{id="d19ae5f1-b303-4b82-9ca8-7682749faf0c"; ref="DINE-Private-DNS-Azure-Storage-StaticWeb-Sec"; param="azureStorageStaticWebSecPrivateDnsZoneId"; zone="privatelink.web.core.windows.net"},
    @{id="83c6fe0f-2316-444a-99a1-1ecd8a7872ca"; ref="DINE-Private-DNS-Azure-Storage-DFS"; param="azureStorageDFSPrivateDnsZoneId"; zone="privatelink.dfs.core.windows.net"},
    @{id="90bd4cb3-9f59-45f7-a6ca-f69db2726671"; ref="DINE-Private-DNS-Azure-Storage-DFS-Sec"; param="azureStorageDFSSecPrivateDnsZoneId"; zone="privatelink.dfs.core.windows.net"},
    @{id="028bbd88-e9b5-461f-9424-a1b63a7bee1a"; ref="DINE-Private-DNS-Azure-Storage-Table"; param="azureStorageTablePrivateDnsZoneId"; zone="privatelink.table.core.windows.net"},
    @{id="c1d634a5-f73d-4cdd-889f-2cc7006eb47f"; ref="DINE-Private-DNS-Azure-Storage-Table-Sec"; param="azureStorageTableSecondaryPrivateDnsZoneId"; zone="privatelink.table.core.windows.net"},
    @{id="1e5ed725-f16c-478b-bd4b-7bfa2f7940b9"; ref="DINE-Private-DNS-Azure-Synapse-SQL"; param="azureSynapseSQLPrivateDnsZoneId"; zone="privatelink.sql.azuresynapse.net"},
    @{id="1e7ca9cd-7c3d-4722-a5f8-79d1c7593f6d"; ref="DINE-Private-DNS-Azure-Synapse-Dev"; param="azureSynapseDevPrivateDnsZoneId"; zone="privatelink.dev.azuresynapse.net"},
    @{id="b4a7f6c1-585e-4177-ad5b-c2c93f4bb991"; ref="DINE-Private-DNS-Azure-MediaServices-Key"; param="azureMediaServicesKeyPrivateDnsZoneId"; zone="privatelink.media.azure.net"},
    @{id="a48d9e19-b6a3-4726-a288-b0e1146c2381"; ref="DINE-Private-DNS-Azure-MediaServices-Live"; param="azureMediaServicesLivePrivateDnsZoneId"; zone="privatelink.media.azure.net"},
    @{id="a9b426fe-8856-4945-8600-18c5dd1cca2a"; ref="DINE-Private-DNS-Azure-MediaServices-Stream"; param="azureMediaServicesStreamPrivateDnsZoneId"; zone="privatelink.media.azure.net"},
    @{id="0eb8c575-589c-4afc-b0e6-7e6f989f01f5"; ref="DINE-Private-DNS-Azure-Web"; param="azureWebPrivateDnsZoneId"; zone="privatelink.webpubsub.azure.com"},
    @{id="4ec38ebc-381f-4e25-9f61-b86e51d7aa0f"; ref="DINE-Private-DNS-Azure-Batch"; param="azureBatchPrivateDnsZoneId"; zone="privatelink.batch.azure.com"},
    @{id="7d0e2da6-e7af-4e60-bd6e-06e561e4f4f7"; ref="DINE-Private-DNS-Azure-App"; param="azureAppPrivateDnsZoneId"; zone="privatelink.azconfig.io"},
    @{id="942bd215-1a66-44be-af65-6a1c0318dbe2"; ref="DINE-Private-DNS-Azure-SiteRecovery"; param="azureAsrPrivateDnsZoneId"; zone="privatelink.siterecovery.windowsazure.com"},
    @{id="d8f7ea08-7232-4ac0-ad75-7c6a0fcbd72f"; ref="DINE-Private-DNS-Azure-IoT-DPS"; param="azureIotPrivateDnsZoneId"; zone="privatelink.azure-devices-provisioning.net"},
    @{id="ac673a9a-f77d-4846-b2d8-a57f8e1c01d4"; ref="DINE-Private-DNS-Azure-KeyVault"; param="azureKeyVaultPrivateDnsZoneId"; zone="privatelink.vaultcore.azure.net"},
    @{id="b0e86710-7fb7-4a6c-a064-32e9b829509e"; ref="DINE-Private-DNS-Azure-SignalR"; param="azureSignalRPrivateDnsZoneId"; zone="privatelink.service.signalr.net"},
    @{id="b318f84a-b872-429b-ac6d-a01b96814452"; ref="DINE-Private-DNS-Azure-AppServices"; param="azureAppServicesPrivateDnsZoneId"; zone="privatelink.azurewebsites.net"},
    @{id="baf19753-7502-405f-8745-370519b20483"; ref="DINE-Private-DNS-Azure-EventGridTopics"; param="azureEventGridTopicsPrivateDnsZoneId"; zone="privatelink.eventgrid.azure.net"},
    @{id="bc05b96c-0b36-4ca9-82f0-5c53f96ce05a"; ref="DINE-Private-DNS-Azure-DiskAccess"; param="azureDiskAccessPrivateDnsZoneId"; zone="privatelink.blob.core.windows.net"},
    @{id="c4bc6f10-cb41-49eb-b000-d5ab82e2a091"; ref="DINE-Private-DNS-Azure-CognitiveServices"; param="azureCognitiveServicesPrivateDnsZoneId"; zone="privatelink.cognitiveservices.azure.com"},
    @{id="c99ce9c1-ced7-4c3e-aca0-10e69ce0cb02"; ref="DINE-Private-DNS-Azure-IoTHubs"; param="azureIotHubsPrivateDnsZoneId"; zone="privatelink.azure-devices.net"},
    @{id="d389df0a-e0d7-4607-833c-75a6fdac2c2d"; ref="DINE-Private-DNS-Azure-EventGridDomains"; param="azureEventGridDomainsPrivateDnsZoneId"; zone="privatelink.eventgrid.azure.net"},
    @{id="e016b22b-e0eb-436d-8fd7-160c4eaed6e2"; ref="DINE-Private-DNS-Azure-RedisCache"; param="azureRedisCachePrivateDnsZoneId"; zone="privatelink.redis.cache.windows.net"},
    @{id="e9585a95-5b8c-4d03-b193-dc7eb5ac4c32"; ref="DINE-Private-DNS-Azure-ACR"; param="azureAcrPrivateDnsZoneId"; zone="privatelink.azurecr.io"},
    @{id="ed66d4f5-8220-45dc-ab4a-20d1749c74e6"; ref="DINE-Private-DNS-Azure-EventHubNamespace"; param="azureEventHubNamespacePrivateDnsZoneId"; zone="privatelink.servicebus.windows.net"},
    @{id="ee40564d-486e-4f68-a5ca-7a621edae0fb"; ref="DINE-Private-DNS-Azure-MachineLearning"; param="azureMachineLearningWorkspacePrivateDnsZoneId"; zone="privatelink.api.azureml.ms"; param2="azureMachineLearningWorkspaceSecondPrivateDnsZoneId"; zone2="privatelink.notebooks.azure.net"},
    @{id="f0fcf93c-c063-4071-9668-c47474bd3564"; ref="DINE-Private-DNS-Azure-ServiceBusNamespace"; param="azureServiceBusNamespacePrivateDnsZoneId"; zone="privatelink.servicebus.windows.net"},
    @{id="fbc14a67-53e4-4932-abcc-2049c6706009"; ref="DINE-Private-DNS-Azure-CognitiveSearch"; param="azureCognitiveSearchPrivateDnsZoneId"; zone="privatelink.search.windows.net"},
    @{id="6a4e6f44-f2af-4082-9702-033c9e88b9f8"; ref="DINE-Private-DNS-Azure-BotService"; param="azureBotServicePrivateDnsZoneId"; zone="privatelink.directline.botframework.com"},
    @{id="4c8537f8-cd1b-49ec-b704-18e82a42fd3d"; ref="DINE-Private-DNS-Azure-ManagedGrafana"; param="azureManagedGrafanaWorkspacePrivateDnsZoneId"; zone="privatelink.grafana.azure.com"},
    @{id="9427df23-0f42-4e1e-bf99-a6133d841c4a"; ref="DINE-Private-DNS-Azure-VirtualDesktop-Hostpool"; param="azureVirtualDesktopHostpoolPrivateDnsZoneId"; zone="privatelink.wvd.microsoft.com"},
    @{id="0f8c9e94-5e97-4d77-85e6-5656cb899a8c"; ref="DINE-Private-DNS-Azure-VirtualDesktop-Workspace"; param="azureVirtualDesktopWorkspacePrivateDnsZoneId"; zone="privatelink.wvd.microsoft.com"},
    @{id="a222b93a-e6c2-4c01-817f-21e092455b2a"; ref="DINE-Private-DNS-Azure-IoT-DeviceUpdate"; param="azureIotDeviceupdatePrivateDnsZoneId"; zone="privatelink.azure-devices.net"},
    @{id="9b7c6f1c-c96a-4418-8b7f-4e9e564d4427"; ref="DINE-Private-DNS-Azure-Arc-GuestConfiguration"; param="azureArcGuestconfigurationPrivateDnsZoneId"; zone="privatelink.guestconfiguration.azure.com"},
    @{id="55c4db33-97b0-437b-8469-c4f4498f5df9"; ref="DINE-Private-DNS-Azure-Arc-HybridResourceProvider"; param="azureArcHybridResourceProviderPrivateDnsZoneId"; zone="privatelink.his.arc.azure.com"},
    @{id="0eddd701-78c6-4fc4-9e49-99fc8c4dd647"; ref="DINE-Private-DNS-Azure-Arc-Kubernetes"; param="azureArcKubernetesConfigurationPrivateDnsZoneId"; zone="privatelink.dp.kubernetesconfiguration.azure.com"},
    @{id="d627d7c6-ded5-481a-8f2e-7e16b1e6faf6"; ref="DINE-Private-DNS-Azure-IoTCentral"; param="azureIotCentralPrivateDnsZoneId"; zone="privatelink.azureiotcentral.com"},
    @{id="af783da1-4ad1-42be-800d-d19c70038820"; ref="DINE-Private-DNS-Azure-Backup"; param="azureSiteRecoveryBackupPrivateDnsZoneId"; zone="privatelink.{region}.backup.windowsazure.com"},
    @{id="af783da1-4ad1-42be-800d-d19c70038821"; ref="DINE-Private-DNS-Azure-SiteRecovery-Blob"; param="azureSiteRecoveryBlobPrivateDnsZoneId"; zone="privatelink.blob.core.windows.net"},
    @{id="af783da1-4ad1-42be-800d-d19c70038822"; ref="DINE-Private-DNS-Azure-SiteRecovery-Queue"; param="azureSiteRecoveryQueuePrivateDnsZoneId"; zone="privatelink.queue.core.windows.net"}
)

Write-Host "Validating $($allPolicyIds.Count) policy definitions..." -ForegroundColor Cyan
Write-Host ""

$validPolicies = @()
$invalidPolicies = @()
$differentParams = @()

foreach ($pol in $allPolicyIds) {
    try {
        $policy = Get-AzPolicyDefinition -Id "/providers/Microsoft.Authorization/policyDefinitions/$($pol.id)" -ErrorAction Stop
        $params = ($policy.Properties.Parameters | Get-Member -MemberType NoteProperty).Name
        
        # Check for standard privateDnsZoneId parameter
        if ($params -contains "privateDnsZoneId") {
            $validPolicies += $pol
            Write-Host "✓ $($pol.ref)" -ForegroundColor Green
        }
        # Check for multi-zone policies (like Monitor and Machine Learning)
        elseif ($params -contains "privateDnsZoneId1") {
            $validPolicies += $pol
            Write-Host "✓ $($pol.ref) [multi-zone]" -ForegroundColor Green
        }
        # Check for Azure Monitor style parameters
        elseif ($params -match "privateDnsZoneId\d+") {
            $validPolicies += $pol
            Write-Host "✓ $($pol.ref) [multi-zone]" -ForegroundColor Green
        }
        else {
            $differentParams += @{policy=$pol; params=$params}
            Write-Host "⚠ $($pol.ref) - Different params: $($params -join ', ')" -ForegroundColor Yellow
        }
    } catch {
        $invalidPolicies += $pol
        Write-Host "✗ $($pol.ref) - Not found" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Valid policies: $($validPolicies.Count)" -ForegroundColor Green
Write-Host "  Policies with different parameters: $($differentParams.Count)" -ForegroundColor Yellow
Write-Host "  Invalid/not found: $($invalidPolicies.Count)" -ForegroundColor Red

# Export valid policies for building the comprehensive policy set
$validPolicies | ConvertTo-Json -Depth 5 | Set-Content ".\validPolicyIds.json"
Write-Host ""
Write-Host "Valid policy IDs exported to validPolicyIds.json" -ForegroundColor Green
