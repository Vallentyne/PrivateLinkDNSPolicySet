# Compare Excel policies with deployed policy set

Write-Host "`n=== POLICY SET COMPARISON ===" -ForegroundColor Cyan -BackgroundColor Black

# Get policies from Excel
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$workbook = $excel.Workbooks.Open("$PWD\JDCP PolicyDefinitionTabExport.xlsx")
$worksheet = $workbook.Worksheets.Item(1)
$range = $worksheet.UsedRange
$rows = $range.Rows.Count

$excelPolicies = @()
for ($i = 2; $i -le $rows; $i++) {
    $name = $worksheet.Cells.Item($i, 1).Text.Trim()
    if ($name -and $name -notlike '*Deny privatelinks*') {
        # Parse the policy name to extract service details
        if ($name -match 'DNS - (.*) - (.*) - (.*)') {
            $zone = $matches[1]
            $namespace = $matches[2]
            $groupId = $matches[3]
            $excelPolicies += [PSCustomObject]@{
                FullName = $name
                Zone = $zone
                Namespace = $namespace
                GroupId = $groupId
                Key = "$namespace-$groupId"
            }
        }
    }
}
$workbook.Close($false)
$excel.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null

# Built-in policy mapping from bicep
$builtInMap = @{
    'Microsoft.KeyVault/vaults-vault' = 'Key Vault'
    'Microsoft.Storage/storageAccounts-blob' = 'Storage Blob'
    'Microsoft.Storage/storageAccounts-file' = 'Storage File'
    'Microsoft.Storage/storageAccounts-queue' = 'Storage Queue'
    'Microsoft.Storage/storageAccounts-table' = 'Storage Table'
    'Microsoft.Storage/storageAccounts-dfs' = 'Storage DFS'
    'Microsoft.Storage/storageAccounts-web' = 'Storage Web'
    'Microsoft.CognitiveServices/accounts-account' = 'Cognitive Services'
    'Microsoft.Web/sites-sites' = 'App Services'
    'Microsoft.ContainerRegistry/registries-registry' = 'Container Registry'
    'Microsoft.SignalRService/signalR-signalR' = 'SignalR'
    'Microsoft.EventGrid/topics-topic' = 'Event Grid Topics'
    'Microsoft.EventGrid/domains-domain' = 'Event Grid Domains'
    'Microsoft.EventHub/namespaces-namespace' = 'Event Hub'
    'Microsoft.ServiceBus/namespaces-namespace' = 'Service Bus'
    'Microsoft.Devices/IotHubs-iotHub' = 'IoT Hubs'
    'Microsoft.Cache/Redis-redisCache' = 'Redis Cache'
    'Microsoft.Search/searchServices-searchService' = 'Search'
    'Microsoft.Compute/diskAccesses-diskAccess' = 'Disk Access'
    'Microsoft.MachineLearningServices/workspaces-amlworkspace' = 'Machine Learning'
    'Microsoft.Synapse/workspaces-Sql' = 'Synapse SQL'
    'Microsoft.DataFactory/factories-dataFactory' = 'Data Factory'
    'Microsoft.StorageSync/storageSyncServices-afs' = 'File Sync'
    'Microsoft.DeviceUpdate/accounts-deviceUpdate' = 'IoT Device Update'
    'Microsoft.IoTCentral/IoTApps-iotApp' = 'IoT Central'
}

# Get deployed custom policies
$customPolicies = Get-AzPolicyDefinition -ManagementGroupName "DND" -Custom | Where-Object { $_.Name -like 'dns-pe-*' }

Write-Host "`n=== SUMMARY ===" -ForegroundColor Yellow
Write-Host "Excel policies (excl. Deny): $($excelPolicies.Count)" -ForegroundColor White
Write-Host "Built-in policies used: $($builtInMap.Count)" -ForegroundColor White
Write-Host "Custom policies deployed: $($customPolicies.Count)" -ForegroundColor White
Write-Host "Total deployed: $($builtInMap.Count + $customPolicies.Count)" -ForegroundColor White

Write-Host "`n=== BUILT-IN POLICIES (using Azure native policies) ===" -ForegroundColor Green
$builtInMatched = 0
foreach ($key in $builtInMap.Keys | Sort-Object) {
    $matched = $excelPolicies | Where-Object { $_.Key -eq $key }
    if ($matched) {
        Write-Host "  ✓ $($builtInMap[$key])" -ForegroundColor Green
        $builtInMatched++
    } else {
        Write-Host "  ✗ $($builtInMap[$key]) (not in Excel)" -ForegroundColor Red
    }
}

Write-Host "`n=== CUSTOM POLICIES (services without built-in support) ===" -ForegroundColor Yellow
$customMatched = 0
$customServices = $excelPolicies | Where-Object { -not $builtInMap.ContainsKey($_.Key) }
foreach ($svc in $customServices | Sort-Object Zone) {
    Write-Host "  • $($svc.Zone) - $($svc.GroupId)" -ForegroundColor Gray
    $customMatched++
}

Write-Host "`n=== COMPARISON RESULT ===" -ForegroundColor Cyan
Write-Host "Excel services mapped to built-in policies: $builtInMatched / $($builtInMap.Count)" -ForegroundColor $(if($builtInMatched -eq $builtInMap.Count){'Green'}else{'Yellow'})
Write-Host "Excel services requiring custom policies: $customMatched" -ForegroundColor $(if($customMatched -eq $customPolicies.Count){'Green'}else{'Yellow'})
Write-Host "Custom policies deployed: $($customPolicies.Count)" -ForegroundColor $(if($customMatched -eq $customPolicies.Count){'Green'}else{'Yellow'})

if ($builtInMatched + $customMatched -eq $excelPolicies.Count) {
    Write-Host "`n✓ ALL EXCEL POLICIES ARE COVERED!" -ForegroundColor Green -BackgroundColor Black
} else {
    Write-Host "`n⚠ Policy count mismatch" -ForegroundColor Red
}

Write-Host "`n=== MISSING FROM EXCEL ===" -ForegroundColor Magenta
$allExcelKeys = $excelPolicies | ForEach-Object { $_.Key }
foreach ($key in $builtInMap.Keys | Sort-Object) {
    $matched = $excelPolicies | Where-Object { $_.Key -eq $key }
    if (-not $matched) {
        Write-Host "  - $key ($($builtInMap[$key]))" -ForegroundColor Magenta
    }
}
