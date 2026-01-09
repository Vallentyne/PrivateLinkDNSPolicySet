# Build comprehensive policy set with all validated Azure services

Write-Host "`n=== Building Comprehensive Azure Private DNS Policy Set ===" -ForegroundColor Cyan

# Define all validated policy definitions (only those that exist in Azure)
$policyDefs = @(
    @{id="ac673a9a-f77d-4846-b2d8-a57f8e1c01d4"; ref="DINE-Private-DNS-Azure-KeyVault"; param="azureKeyVaultPrivateDnsZoneId"; display="Key Vault"},
    @{id="75973700-529f-4de2-b794-fb9b6781b6b0"; ref="DINE-Private-DNS-Azure-Storage-Blob"; param="azureStorageBlobPrivateDnsZoneId"; display="Storage Blob"},
    @{id="6df98d03-368a-4438-8730-a93c4d7693d6"; ref="DINE-Private-DNS-Azure-Storage-File"; param="azureStorageFilePrivateDnsZoneId"; display="Storage File"},
    @{id="bcff79fb-2b0d-47c9-97e5-3023479b00d1"; ref="DINE-Private-DNS-Azure-Storage-Queue"; param="azureStorageQueuePrivateDnsZoneId"; display="Storage Queue"},
    @{id="028bbd88-e9b5-461f-9424-a1b63a7bee1a"; ref="DINE-Private-DNS-Azure-Storage-Table"; param="azureStorageTablePrivateDnsZoneId"; display="Storage Table"},
    @{id="83c6fe0f-2316-444a-99a1-1ecd8a7872ca"; ref="DINE-Private-DNS-Azure-Storage-DFS"; param="azureStorageDFSPrivateDnsZoneId"; display="Storage DFS (ADLS Gen2)"},
    @{id="9adab2a5-05ba-4fbd-831a-5bf958d04218"; ref="DINE-Private-DNS-Azure-Storage-StaticWeb"; param="azureStorageStaticWebPrivateDnsZoneId"; display="Storage Static Web"},
    @{id="c4bc6f10-cb41-49eb-b000-d5ab82e2a091"; ref="DINE-Private-DNS-Azure-CognitiveServices"; param="azureCognitiveServicesPrivateDnsZoneId"; display="Cognitive Services"},
    @{id="b318f84a-b872-429b-ac6d-a01b96814452"; ref="DINE-Private-DNS-Azure-AppServices"; param="azureAppServicesPrivateDnsZoneId"; display="App Services"},
    @{id="e9585a95-5b8c-4d03-b193-dc7eb5ac4c32"; ref="DINE-Private-DNS-Azure-ACR"; param="azureAcrPrivateDnsZoneId"; display="Container Registry (ACR)"},
    @{id="b0e86710-7fb7-4a6c-a064-32e9b829509e"; ref="DINE-Private-DNS-Azure-SignalR"; param="azureSignalRPrivateDnsZoneId"; display="SignalR"},
    @{id="baf19753-7502-405f-8745-370519b20483"; ref="DINE-Private-DNS-Azure-EventGridTopics"; param="azureEventGridTopicsPrivateDnsZoneId"; display="Event Grid Topics"},
    @{id="d389df0a-e0d7-4607-833c-75a6fdac2c2d"; ref="DINE-Private-DNS-Azure-EventGridDomains"; param="azureEventGridDomainsPrivateDnsZoneId"; display="Event Grid Domains"},
    @{id="ed66d4f5-8220-45dc-ab4a-20d1749c74e6"; ref="DINE-Private-DNS-Azure-EventHubNamespace"; param="azureEventHubNamespacePrivateDnsZoneId"; display="Event Hub Namespace"},
    @{id="f0fcf93c-c063-4071-9668-c47474bd3564"; ref="DINE-Private-DNS-Azure-ServiceBusNamespace"; param="azureServiceBusNamespacePrivateDnsZoneId"; display="Service Bus Namespace"},
    @{id="c99ce9c1-ced7-4c3e-aca0-10e69ce0cb02"; ref="DINE-Private-DNS-Azure-IoTHubs"; param="azureIotHubsPrivateDnsZoneId"; display="IoT Hubs"},
    @{id="e016b22b-e0eb-436d-8fd7-160c4eaed6e2"; ref="DINE-Private-DNS-Azure-RedisCache"; param="azureRedisCachePrivateDnsZoneId"; display="Redis Cache"},
    @{id="fbc14a67-53e4-4932-abcc-2049c6706009"; ref="DINE-Private-DNS-Azure-CognitiveSearch"; param="azureCognitiveSearchPrivateDnsZoneId"; display="Cognitive Search"},
    @{id="bc05b96c-0b36-4ca9-82f0-5c53f96ce05a"; ref="DINE-Private-DNS-Azure-DiskAccess"; param="azureDiskAccessPrivateDnsZoneId"; display="Disk Access"},
    @{id="4ec38ebc-381f-4e25-9f61-b86e51d7aa0f"; ref="DINE-Private-DNS-Azure-Batch"; param="azureBatchPrivateDnsZoneId"; display="Batch"},
    @{id="ee40564d-486e-4f68-a5ca-7a621edae0fb"; ref="DINE-Private-DNS-Azure-MachineLearning"; param="azureMachineLearningWorkspacePrivateDnsZoneId"; param2="azureMachineLearningWorkspaceSecondPrivateDnsZoneId"; display="Machine Learning Workspace"},
    @{id="a63cc0bd-cda4-4178-b705-37dc439d3e0f"; ref="DINE-Private-DNS-Azure-Cosmos-SQL"; param="azureCosmosSQLPrivateDnsZoneId"; display="Cosmos DB (SQL API)"},
    @{id="1e5ed725-f16c-478b-bd4b-7bfa2f7940b9"; ref="DINE-Private-DNS-Azure-Synapse-SQL"; param="azureSynapseSQLPrivateDnsZoneId"; display="Synapse (SQL endpoint)"},
    @{id="1e7ca9cd-7c3d-4722-a5f8-79d1c7593f6d"; ref="DINE-Private-DNS-Azure-Synapse-Dev"; param="azureSynapseDevPrivateDnsZoneId"; display="Synapse (Dev endpoint)"},
    @{id="86cd96e1-1745-420d-94d4-d3f2fe415aa4"; ref="DINE-Private-DNS-Azure-DataFactory"; param="azureDataFactoryPrivateDnsZoneId"; display="Data Factory"},
    @{id="06695360-db88-47f6-b976-7500d4297475"; ref="DINE-Private-DNS-Azure-File-Sync"; param="azureFilePrivateDnsZoneId"; display="File Sync (Storage Sync Services)"},
    @{id="6dd01e4f-1be1-4e80-9d0b-d109e04cb064"; ref="DINE-Private-DNS-Azure-Automation-Webhook"; param="azureAutomationWebhookPrivateDnsZoneId"; display="Automation Account (Webhook/Hybrid Worker)"},
    @{id="b4a7f6c1-585e-4177-ad5b-c2c93f4bb991"; ref="DINE-Private-DNS-Azure-MediaServices-Key"; param="azureMediaServicesKeyPrivateDnsZoneId"; display="Media Services (Key Delivery)"},
    @{id="a48d9e19-b6a3-4726-a288-b0e1146c2381"; ref="DINE-Private-DNS-Azure-MediaServices-Live"; param="azureMediaServicesLivePrivateDnsZoneId"; display="Media Services (Live Events)"},
    @{id="a9b426fe-8856-4945-8600-18c5dd1cca2a"; ref="DINE-Private-DNS-Azure-MediaServices-Stream"; param="azureMediaServicesStreamPrivateDnsZoneId"; display="Media Services (Streaming)"},
    @{id="6a4e6f44-f2af-4082-9702-033c9e88b9f8"; ref="DINE-Private-DNS-Azure-BotService"; param="azureBotServicePrivateDnsZoneId"; display="Bot Service"},
    @{id="9427df23-0f42-4e1e-bf99-a6133d841c4a"; ref="DINE-Private-DNS-Azure-VirtualDesktop-Hostpool"; param="azureVirtualDesktopHostpoolPrivateDnsZoneId"; display="Virtual Desktop (Host Pool)"},
    @{id="a222b93a-e6c2-4c01-817f-21e092455b2a"; ref="DINE-Private-DNS-Azure-IoT-DeviceUpdate"; param="azureIotDeviceupdatePrivateDnsZoneId"; display="IoT Device Update"},
    @{id="55c4db33-97b0-437b-8469-c4f4498f5df9"; ref="DINE-Private-DNS-Azure-Arc-HybridResourceProvider"; param="azureArcHybridResourceProviderPrivateDnsZoneId"; display="Arc Hybrid Resource Provider"},
    @{id="d627d7c6-ded5-481a-8f2e-7e16b1e6faf6"; ref="DINE-Private-DNS-Azure-IoTCentral"; param="azureIotCentralPrivateDnsZoneId"; display="IoT Central"},
    @{id="0eddd7f3-3d9b-4927-a07a-806e8ac9486c"; ref="DINE-Private-DNS-Azure-Databricks"; param="azureDatabricksPrivateDnsZoneId"; display="Azure Databricks"}
)

Write-Host "Building policy set with $($policyDefs.Count) services..." -ForegroundColor Green
Write-Host ""

# Build parameters object
$parameters = @{
    effect = @{
        type = "String"
        metadata = @{
            displayName = "Effect"
            description = "Enable or disable the execution of the policy"
        }
        allowedValues = @("DeployIfNotExists", "Disabled")
        defaultValue = "DeployIfNotExists"
    }
}

# Build policy definitions array
$policies = @()

foreach ($pol in $policyDefs) {
    # Add parameter for this service (with default empty string for new parameters)
    $parameters[$pol.param] = @{
        type = "String"
        metadata = @{
            displayName = "$($pol.display) Private DNS Zone ID"
        }
        defaultValue = ""
    }
    
    # Build policy definition reference
    $policyRef = @{
        policyDefinitionReferenceId = $pol.ref
        policyDefinitionId = "/providers/Microsoft.Authorization/policyDefinitions/$($pol.id)"
        parameters = @{
            privateDnsZoneId = @{
                value = "[parameters('$($pol.param)')]"
            }
            effect = @{
                value = "[parameters('effect')]"
            }
        }
        groupNames = @()
    }
    
    # Handle multi-parameter policies (like Machine Learning)
    if ($pol.param2) {
        $parameters[$pol.param2] = @{
            type = "String"
            metadata = @{
                displayName = "$($pol.display) Secondary Private DNS Zone ID"
            }
            defaultValue = ""
        }
        $policyRef.parameters["secondPrivateDnsZoneId"] = @{
            value = "[parameters('$($pol.param2)')]"
        }
    }
    
    $policies += $policyRef
    Write-Host "  ✓ $($pol.display)" -ForegroundColor Gray
}

# Build complete policy set definition
$policySet = @{
    properties = @{
        displayName = "Deploy Private DNS Zones for Azure Services"
        description = "Comprehensive policy set that deploys private DNS zones for $($policyDefs.Count) Azure PaaS services that support private endpoints. Includes Storage, Compute, AI/ML, IoT, Data, Media, and Networking services."
        metadata = @{
            version = "2.0.0"
            category = "Network"
        }
        parameters = $parameters
        policyDefinitions = $policies
        policyDefinitionGroups = @()
    }
}

# Save complete policy set
$policySet | ConvertTo-Json -Depth 100 | Set-Content ".\comprehensivePolicySet.json"
Write-Host "`n✓ Created comprehensivePolicySet.json" -ForegroundColor Green

# Extract for PowerShell cmdlet
$policies | ConvertTo-Json -Depth 100 | Set-Content ".\comprehensivePolicies.json"
Write-Host "✓ Created comprehensivePolicies.json ($($policies.Count) policies)" -ForegroundColor Green

$parameters | ConvertTo-Json -Depth 100 | Set-Content ".\comprehensiveParameters.json"
Write-Host "✓ Created comprehensiveParameters.json ($($parameters.Count) parameters)" -ForegroundColor Green

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Total services: $($policyDefs.Count)"
Write-Host "Ready to deploy with: Set-AzPolicySetDefinition" -ForegroundColor Yellow
