<#
.SYNOPSIS
    Deploys, validates, and removes an Azure Private DNS Policy smoke environment.

.EXAMPLE
    ./tests/smoke/Invoke-SmokeTest.ps1 -Action All -SubscriptionId <subscription-id> -ManagementGroupId <management-group-id>

.EXAMPLE
    ./tests/smoke/Invoke-SmokeTest.ps1 -Action Destroy -SubscriptionId <subscription-id> -ManagementGroupId <management-group-id> -RunId local20260908
#>
[CmdletBinding()]
param(
    [ValidateSet('Validate', 'Deploy', 'Test', 'Destroy', 'All')]
    [string] $Action = 'All',

    [string] $SubscriptionId,

    [string] $ManagementGroupId,

    [string] $Location = 'canadacentral',

    [string] $RunId = (Get-Date -Format 'yyyyMMddHHmmss'),

    [ValidateRange(10, 120)]
    [int] $TimeoutMinutes = 45,

    [switch] $KeepOnFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$FoundationTemplate = Join-Path $PSScriptRoot 'foundation.bicep'
$EndpointTemplate = Join-Path $PSScriptRoot 'private-endpoints.bicep'
$PolicyTemplate = Join-Path $RepoRoot 'pubsecDNS.bicep'
$PolicyParameters = Join-Path $RepoRoot 'pubsecDNS.parameters.json'
$CoverageTest = Join-Path $RepoRoot 'Test-PolicyCoverage.ps1'
. (Join-Path $PSScriptRoot 'Assert-SmokeTestSubscription.ps1')

$normalizedRunId = ($RunId.ToLowerInvariant() -replace '[^a-z0-9]', '')
if ($normalizedRunId.Length -lt 3) {
    throw 'RunId must contain at least three letters or numbers.'
}
$NameSuffix = $normalizedRunId.Substring([Math]::Max(0, $normalizedRunId.Length - [Math]::Min(12, $normalizedRunId.Length)))
$ResourceGroupName = "rg-dns-policy-smoke-$NameSuffix"
$PolicyVersion = "smoke-$NameSuffix"
$PolicySetName = "custom-central-dns-private-endpoints-$PolicyVersion"
$AssignmentName = "dns-policy-smoke-$NameSuffix"
$ResultPath = Join-Path $PSScriptRoot "results/$NameSuffix.json"

$ExpectedPolicies = @(
    [pscustomobject]@{ Name = 'storage-blob'; BuiltInId = '75973700-529f-4de2-b794-fb9b6781b6b0'; Namespace = $null; GroupId = $null }
    [pscustomobject]@{ Name = 'key-vault'; BuiltInId = 'ac673a9a-f77d-4846-b2d8-a57f8e1c01d4'; Namespace = $null; GroupId = $null }
    [pscustomobject]@{ Name = 'machine-learning'; BuiltInId = 'ee40564d-486e-4f68-a5ca-7a621edae0fb'; Namespace = $null; GroupId = $null }
    [pscustomobject]@{ Name = 'app-configuration'; BuiltInId = $null; Namespace = 'Microsoft.AppConfiguration/configurationStores'; GroupId = 'configurationStores' }
    [pscustomobject]@{ Name = 'ai-services'; BuiltInId = $null; Namespace = 'Microsoft.CognitiveServices/accounts'; GroupId = 'account' }
    [pscustomobject]@{ Name = 'managed-redis'; BuiltInId = $null; Namespace = 'Microsoft.Cache/redisEnterprise'; GroupId = 'redisEnterprise' }
    [pscustomobject]@{ Name = 'batch-account'; BuiltInId = '4ec38ebc-381f-45ee-81a4-acbc4be878f8'; Namespace = $null; GroupId = $null }
    [pscustomobject]@{ Name = 'batch-node-management'; BuiltInId = $null; Namespace = 'Microsoft.Batch/batchAccounts'; GroupId = 'nodeManagement' }
)

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-AzCli {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $Json
    )

    if ($Arguments[0] -ne 'bicep') {
        $Arguments += @('--subscription', $SubscriptionId)
    }

    $output = $null
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        Write-Verbose "az $($Arguments -join ' ')"
        $output = & az @Arguments --only-show-errors 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            break
        }

        $isTransient = $output -match 'ConnectionResetError|Connection aborted|temporarily unavailable|timed out|TooManyRequests|InternalServerError'
        if (-not $isTransient -or $attempt -eq 4) {
            throw "Azure CLI failed: az $($Arguments -join ' ')`n$($output.Trim())"
        }

        Write-Warning "Azure CLI transport failure; retrying in $($attempt * 10) seconds ($attempt/4)."
        Start-Sleep -Seconds ($attempt * 10)
    }

    if ($Json) {
        if ([string]::IsNullOrWhiteSpace($output)) {
            return $null
        }
        return $output | ConvertFrom-Json -Depth 100
    }

    return $output.Trim()
}

function Assert-AzureContext {
    if ($Action -eq 'Validate') {
        return
    }
    if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or [string]::IsNullOrWhiteSpace($ManagementGroupId)) {
        throw 'SubscriptionId and ManagementGroupId are required for Azure actions.'
    }

    $script:SubscriptionId = Assert-SmokeTestSubscription -SubscriptionId $SubscriptionId
}

function Invoke-Validation {
    Write-Step 'Running static policy and Bicep validation'
    & (Join-Path $PSScriptRoot 'Test-SmokeTestSubscription.ps1')
    & (Join-Path $PSScriptRoot 'Test-EndpointDns.ps1')
    & $CoverageTest
    if ($LASTEXITCODE -ne 0) {
        throw 'Test-PolicyCoverage.ps1 failed.'
    }

    foreach ($template in @($PolicyTemplate, $FoundationTemplate, $EndpointTemplate)) {
        $null = Invoke-AzCli -Arguments @('bicep', 'build', '--file', $template, '--stdout')
        Write-Host "  [PASS] $(Split-Path $template -Leaf)"
    }
}

function Register-TestProviders {
    Write-Step 'Registering required resource providers'
    $providers = @(
        'Microsoft.AppConfiguration'
        'Microsoft.Authorization'
        'Microsoft.Batch'
        'Microsoft.Cache'
        'Microsoft.CognitiveServices'
        'Microsoft.KeyVault'
        'Microsoft.Insights'
        'Microsoft.MachineLearningServices'
        'Microsoft.Network'
        'Microsoft.PolicyInsights'
        'Microsoft.Storage'
    )
    foreach ($provider in $providers) {
        $registrationState = Invoke-AzCli -Arguments @(
            'provider', 'show',
            '--namespace', $provider,
            '--query', 'registrationState',
            '--output', 'tsv'
        )
        if ($registrationState -eq 'Registered') {
            Write-Host "  [READY] $provider"
            continue
        }

        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $null = Invoke-AzCli -Arguments @('provider', 'register', '--namespace', $provider, '--wait')
                Write-Host "  [READY] $provider"
                break
            }
            catch {
                if ($attempt -eq 3) { throw }
                Write-Warning "Provider registration for '$provider' failed transiently; retrying ($attempt/3)."
                Start-Sleep -Seconds (10 * $attempt)
            }
        }
    }
}

function Get-PolicySet {
    return Invoke-AzCli -Arguments @(
        'policy', 'set-definition', 'show',
        '--management-group', $ManagementGroupId,
        '--name', $PolicySetName,
        '--output', 'json'
    ) -Json
}

function Get-ExpectedPolicyReferences($PolicySet) {
    $references = @()
    foreach ($expected in $ExpectedPolicies) {
        $matches = @($PolicySet.policyDefinitions | Where-Object {
            if ($expected.BuiltInId) {
                return $_.policyDefinitionId -like "*/$($expected.BuiltInId)"
            }

            $namespaceProperty = $_.parameters.PSObject.Properties['privateLinkServiceNamespace']
            $groupProperty = $_.parameters.PSObject.Properties['groupId']
            return $namespaceProperty -and $groupProperty -and
                $namespaceProperty.Value.value -eq $expected.Namespace -and
                $groupProperty.Value.value -eq $expected.GroupId
        })

        if ($matches.Count -ne 1) {
            throw "Expected one initiative reference for '$($expected.Name)', found $($matches.Count)."
        }
        $references += [pscustomobject]@{
            Name = $expected.Name
            ReferenceId = $matches[0].policyDefinitionReferenceId
        }
    }
    return $references
}

function Add-DnsRoleAssignment([string] $PrincipalId, [string] $Scope) {
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            $null = Invoke-AzCli -Arguments @(
                'role', 'assignment', 'create',
                '--assignee-object-id', $PrincipalId,
                '--assignee-principal-type', 'ServicePrincipal',
                '--role', 'Private DNS Zone Contributor',
                '--scope', $Scope
            )
            return
        }
        catch {
            if ($attempt -eq 12) { throw }
            Write-Host "  Waiting for policy identity replication (attempt $attempt/12)..."
            Start-Sleep -Seconds 10
        }
    }
}

function Invoke-Deployment {
    Register-TestProviders

    $expiresOn = (Get-Date).ToUniversalTime().AddHours(6).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Step "Creating disposable resource group $ResourceGroupName"
    $resourceGroup = Invoke-AzCli -Arguments @(
        'group', 'create',
        '--name', $ResourceGroupName,
        '--location', $Location,
        '--tags', 'purpose=dns-policy-smoke', "runId=$RunId", "expiresOn=$expiresOn",
        '--output', 'json'
    ) -Json

    Write-Step "Deploying initiative version $PolicyVersion"
    $null = Invoke-AzCli -Arguments @(
        'deployment', 'mg', 'create',
        '--management-group-id', $ManagementGroupId,
        '--location', $Location,
        '--name', "dns-policy-$NameSuffix",
        '--template-file', $PolicyTemplate,
        '--parameters', "@$PolicyParameters", "policyDefinitionManagementGroupId=$ManagementGroupId", "policyVersion=$PolicyVersion"
    )
    $policySet = Get-PolicySet
    $policyReferences = Get-ExpectedPolicyReferences -PolicySet $policySet

    Write-Step 'Deploying backing services and private DNS zones'
    $foundationOutputs = Invoke-AzCli -Arguments @(
        'deployment', 'group', 'create',
        '--resource-group', $ResourceGroupName,
        '--name', "foundation-$NameSuffix",
        '--template-file', $FoundationTemplate,
        '--parameters', "location=$Location", "nameSuffix=$NameSuffix",
        '--query', 'properties.outputs',
        '--output', 'json'
    ) -Json

    $assignmentParameters = @{
        privateDNSZoneSubscriptionId = @{ value = $SubscriptionId }
        privateDNSZoneResourceGroupName = @{ value = $ResourceGroupName }
    } | ConvertTo-Json -Depth 5 -Compress

    Write-Step 'Assigning the initiative and configuring its managed identity'
    $assignment = Invoke-AzCli -Arguments @(
        'policy', 'assignment', 'create',
        '--name', $AssignmentName,
        '--display-name', "DNS policy smoke test $NameSuffix",
        '--scope', $resourceGroup.id,
        '--policy-set-definition', $policySet.id,
        '--params', $assignmentParameters,
        '--mi-system-assigned',
        '--identity-scope', $resourceGroup.id,
        '--role', 'Network Contributor',
        '--location', $Location,
        '--output', 'json'
    ) -Json
    # Both remediation roles use this scope because the endpoints and DNS zones share the disposable resource group.
    Add-DnsRoleAssignment -PrincipalId $assignment.identity.principalId -Scope $resourceGroup.id

    Write-Step 'Deploying private endpoints without DNS zone groups'
    $endpointOutputs = Invoke-AzCli -Arguments @(
        'deployment', 'group', 'create',
        '--resource-group', $ResourceGroupName,
        '--name', "endpoints-$NameSuffix",
        '--template-file', $EndpointTemplate,
        '--parameters',
        "location=$Location",
        "nameSuffix=$NameSuffix",
        "subnetId=$($foundationOutputs.subnetId.value)",
        "storageBlobResourceId=$($foundationOutputs.targetResourceIds.value.storageBlob)",
        "keyVaultResourceId=$($foundationOutputs.targetResourceIds.value.keyVault)",
        "appConfigurationResourceId=$($foundationOutputs.targetResourceIds.value.appConfiguration)",
        "aiServicesResourceId=$($foundationOutputs.targetResourceIds.value.aiServices)",
        "machineLearningResourceId=$($foundationOutputs.targetResourceIds.value.machineLearning)",
        "batchResourceId=$($foundationOutputs.targetResourceIds.value.batch)",
        "batchSecondaryResourceId=$($foundationOutputs.targetResourceIds.value.batchSecondary)",
        "batchSecondaryAccountName=$($foundationOutputs.batchSecondaryAccountName.value)",
        "batchSecondaryNodeRecordName=$($foundationOutputs.batchSecondaryNodeRecordName.value)",
        "managedRedisResourceId=$($foundationOutputs.targetResourceIds.value.managedRedis)",
        '--query', 'properties.outputs',
        '--output', 'json'
    ) -Json

    return [pscustomobject]@{
        AssignmentId = $assignment.id
        PolicyReferences = $policyReferences
        TestCases = @($endpointOutputs.testCases.value)
    }
}

function Start-PolicyRemediations($PolicyReferences) {
    Write-Step 'Starting targeted policy remediations with fresh resource discovery'
    $remediations = @()
    $index = 0
    foreach ($reference in $PolicyReferences) {
        $index++
        $remediationName = "rem-$index-$NameSuffix"
        $null = Invoke-AzCli -Arguments @(
            'policy', 'remediation', 'create',
            '--name', $remediationName,
            '--resource-group', $ResourceGroupName,
            '--policy-assignment', $AssignmentName,
            '--definition-reference-id', $reference.ReferenceId,
            '--resource-discovery-mode', 'ReEvaluateCompliance'
        )
        $remediations += $remediationName
        Write-Host "  [STARTED] $($reference.Name)"
    }
    return $remediations
}

function Wait-PolicyRemediations([string[]] $RemediationNames) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        $pending = @()
        foreach ($name in $RemediationNames) {
            $remediation = Invoke-AzCli -Arguments @(
                'policy', 'remediation', 'show',
                '--name', $name,
                '--resource-group', $ResourceGroupName,
                '--output', 'json'
            ) -Json
            if ($remediation.provisioningState -in @('Failed', 'Canceled')) {
                throw "Remediation '$name' ended in state '$($remediation.provisioningState)'."
            }
            if ($remediation.provisioningState -ne 'Succeeded') {
                $pending += "$name=$($remediation.provisioningState)"
            }
        }
        if ($pending.Count -eq 0) { return }
        Write-Host "  Waiting for remediation: $($pending -join ', ')"
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $deadline)

    throw "Policy remediation did not finish within $TimeoutMinutes minutes."
}

function Test-EndpointDns($TestCase) {
    $groups = @(Invoke-AzCli -Arguments @(
        'network', 'private-endpoint', 'dns-zone-group', 'list',
        '--endpoint-name', $TestCase.endpointName,
        '--resource-group', $ResourceGroupName,
        '--output', 'json'
    ) -Json)
    if ($groups.Count -ne 1) {
        return "expected one DNS zone group, found $($groups.Count)"
    }

    $actualZones = @($groups[0].privateDnsZoneConfigs | ForEach-Object {
        Split-Path $_.privateDnsZoneId -Leaf
    } | Sort-Object -Unique)
    $expectedZones = @($TestCase.expectedZones | Sort-Object -Unique)
    if (@(Compare-Object -ReferenceObject $expectedZones -DifferenceObject $actualZones).Count -gt 0) {
        return "zone mismatch; expected [$($expectedZones -join ', ')], actual [$($actualZones -join ', ')]"
    }

    $privateEndpoint = Invoke-AzCli -Arguments @(
        'network', 'private-endpoint', 'show',
        '--name', $TestCase.endpointName,
        '--resource-group', $ResourceGroupName,
        '--output', 'json'
    ) -Json
    $nic = Invoke-AzCli -Arguments @(
        'network', 'nic', 'show',
        '--ids', $privateEndpoint.networkInterfaces[0].id,
        '--output', 'json'
    ) -Json
    $endpointIps = @($nic.ipConfigurations.privateIPAddress)
    if ($endpointIps.Count -eq 0 -or -not ($endpointIps | Where-Object { $_ })) {
        return 'private endpoint NIC has no private IP address'
    }

    foreach ($zone in $expectedZones) {
        $recordSets = @(Invoke-AzCli -Arguments @(
            'network', 'private-dns', 'record-set', 'a', 'list',
            '--resource-group', $ResourceGroupName,
            '--zone-name', $zone,
            '--output', 'json'
        ) -Json)
        $expectedRecordNamesProperty = $TestCase.PSObject.Properties['expectedRecordNames']
        [string[]] $expectedRecordNames = @(
            if ($expectedRecordNamesProperty) {
                $expectedRecordNamesProperty.Value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            }
        )
        $matchingRecordSets = if (@($expectedRecordNames).Count -gt 0) {
            @($recordSets | Where-Object { $_.name -in $expectedRecordNames })
        } else {
            $recordSets
        }
        if (@($expectedRecordNames).Count -gt 0 -and @($matchingRecordSets).Count -ne @($expectedRecordNames).Count) {
            $actualRecordNames = @($recordSets.name | Sort-Object -Unique)
            return "zone '$zone' is missing expected A record set(s) [$($expectedRecordNames -join ', ')]; actual [$($actualRecordNames -join ', ')]"
        }
        $recordIps = @($matchingRecordSets | ForEach-Object { $_.aRecords } | ForEach-Object { $_.ipv4Address })
        if (-not ($endpointIps | Where-Object { $_ -in $recordIps })) {
            return "zone '$zone' has no A record for endpoint IP [$($endpointIps -join ', ')]"
        }
    }

    return $null
}

function Wait-EndpointAssertions($TestCases) {
    Write-Step 'Validating exact DNS zone groups and A-record IPs'
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        $failures = @()
        foreach ($testCase in $TestCases) {
            $failure = Test-EndpointDns -TestCase $testCase
            if ($failure) {
                $failures += "$($testCase.endpointName): $failure"
            }
        }
        if ($failures.Count -eq 0) {
            foreach ($testCase in $TestCases) {
                Write-Host "  [PASS] $($testCase.endpointName)"
            }
            return
        }
        Write-Host "  Pending: $($failures -join '; ')"
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $deadline)

    throw "DNS assertions did not pass within $TimeoutMinutes minutes: $($failures -join '; ')"
}

function Invoke-PolicyTest($DeploymentResult) {
    $policySet = Get-PolicySet
    $policyReferences = if ($DeploymentResult) {
        $DeploymentResult.PolicyReferences
    } else {
        Get-ExpectedPolicyReferences -PolicySet $policySet
    }
    $testCases = if ($DeploymentResult) {
        $DeploymentResult.TestCases
    } else {
        $batchSecondary = Invoke-AzCli -Arguments @(
            'batch', 'account', 'show',
            '--name', "basesmoke$NameSuffix",
            '--resource-group', $ResourceGroupName,
            '--output', 'json'
        ) -Json
        if ([string]::IsNullOrWhiteSpace($batchSecondary.nodeManagementEndpoint) -or
            -not $batchSecondary.nodeManagementEndpoint.EndsWith('.batch.azure.com')) {
            throw 'The secondary Batch account has no valid node-management endpoint.'
        }
        $batchSecondaryNodeRecordName = $batchSecondary.nodeManagementEndpoint -replace '\.batch\.azure\.com$', ''
        @(
            [pscustomobject]@{ endpointName = "pe-storage-blob-$NameSuffix"; expectedZones = @('privatelink.blob.core.windows.net') }
            [pscustomobject]@{ endpointName = "pe-key-vault-$NameSuffix"; expectedZones = @('privatelink.vaultcore.azure.net') }
            [pscustomobject]@{ endpointName = "pe-app-configuration-$NameSuffix"; expectedZones = @('privatelink.azconfig.io') }
            [pscustomobject]@{ endpointName = "pe-ai-services-$NameSuffix"; expectedZones = @('privatelink.cognitiveservices.azure.com', 'privatelink.openai.azure.com', 'privatelink.services.ai.azure.com') }
            [pscustomobject]@{ endpointName = "pe-machine-learning-$NameSuffix"; expectedZones = @('privatelink.api.azureml.ms', 'privatelink.notebooks.azure.net') }
            [pscustomobject]@{ endpointName = "pe-managed-redis-$NameSuffix"; expectedZones = @('privatelink.redis.azure.net') }
            [pscustomobject]@{ endpointName = "pe-batch-account-$NameSuffix"; expectedZones = @('privatelink.batch.azure.com') }
            [pscustomobject]@{ endpointName = "pe-batch-node-management-$NameSuffix"; expectedZones = @('privatelink.batch.azure.com') }
            [pscustomobject]@{ endpointName = "pe-batch-account-canada-east-$NameSuffix"; expectedZones = @('privatelink.batch.azure.com'); expectedRecordNames = @("basesmoke$NameSuffix.canadaeast") }
            [pscustomobject]@{ endpointName = "pe-batch-node-management-canada-east-$NameSuffix"; expectedZones = @('privatelink.batch.azure.com'); expectedRecordNames = @($batchSecondaryNodeRecordName) }
        )
    }

    $remediations = Start-PolicyRemediations -PolicyReferences $policyReferences
    Wait-PolicyRemediations -RemediationNames $remediations
    Wait-EndpointAssertions -TestCases $testCases

    Write-Step 'Refreshing and checking policy compliance'
    $null = Invoke-AzCli -Arguments @('policy', 'state', 'trigger-scan', '--resource-group', $ResourceGroupName)
    $assignment = Invoke-AzCli -Arguments @(
        'policy', 'assignment', 'show',
        '--name', $AssignmentName,
        '--scope', "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName",
        '--output', 'json'
    ) -Json
    $states = @(Invoke-AzCli -Arguments @('policy', 'state', 'list', '--resource-group', $ResourceGroupName, '--output', 'json') -Json)
    $nonCompliant = @($states | Where-Object {
        $_.policyAssignmentId -eq $assignment.id -and $_.complianceState -eq 'NonCompliant'
    })
    if ($nonCompliant.Count -gt 0) {
        throw "The final policy scan reports $($nonCompliant.Count) non-compliant resource state(s)."
    }
    Write-Host '  [PASS] Final policy scan has no non-compliant states for the smoke assignment.'

    return $testCases
}

function Remove-TestEnvironment {
    Write-Step "Removing smoke environment $NameSuffix"
    $scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    $assignmentExists = $false
    try {
        $null = Invoke-AzCli -Arguments @('policy', 'assignment', 'show', '--name', $AssignmentName, '--scope', $scope)
        $assignmentExists = $true
    }
    catch {
        Write-Verbose "Policy assignment '$AssignmentName' was not found."
    }
    if ($assignmentExists) {
        $null = Invoke-AzCli -Arguments @('policy', 'assignment', 'delete', '--name', $AssignmentName, '--scope', $scope)
    }

    $groupExists = Invoke-AzCli -Arguments @('group', 'exists', '--name', $ResourceGroupName)
    if ($groupExists -eq 'true') {
        $null = Invoke-AzCli -Arguments @('group', 'delete', '--name', $ResourceGroupName, '--yes', '--no-wait')
        Write-Host "  [DELETE STARTED] $ResourceGroupName"
    }

    try {
        $null = Invoke-AzCli -Arguments @('policy', 'set-definition', 'delete', '--management-group', $ManagementGroupId, '--name', $PolicySetName)
    }
    catch {
        Write-Verbose "Policy set '$PolicySetName' was not found."
    }

    $definitions = @(Invoke-AzCli -Arguments @('policy', 'definition', 'list', '--management-group', $ManagementGroupId, '--output', 'json') -Json)
    foreach ($definition in $definitions | Where-Object {
        $versionProperty = $_.metadata.PSObject.Properties['version']
        $versionProperty -and $versionProperty.Value -eq $PolicyVersion
    }) {
        $null = Invoke-AzCli -Arguments @('policy', 'definition', 'delete', '--management-group', $ManagementGroupId, '--name', $definition.name)
    }
    Write-Host '  [DONE] Cleanup requests completed.'
}

function Write-TestResult([string] $Status, $TestCases, [string] $ErrorMessage) {
    $resultDirectory = Split-Path $ResultPath -Parent
    $null = New-Item -ItemType Directory -Path $resultDirectory -Force
    [ordered]@{
        runId = $RunId
        nameSuffix = $NameSuffix
        subscriptionId = $SubscriptionId
        managementGroupId = $ManagementGroupId
        resourceGroup = $ResourceGroupName
        status = $Status
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
        error = $ErrorMessage
        testCases = @($TestCases)
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $ResultPath -Encoding utf8
    Write-Host "Result: $ResultPath"
}

$null = Get-Command az -ErrorAction Stop
Assert-AzureContext

switch ($Action) {
    'Validate' {
        Invoke-Validation
    }
    'Deploy' {
        $null = Invoke-Deployment
    }
    'Test' {
        $testCases = @()
        try {
            $testCases = Invoke-PolicyTest
            Write-TestResult -Status 'Passed' -TestCases $testCases -ErrorMessage $null
        }
        catch {
            Write-TestResult -Status 'Failed' -TestCases $testCases -ErrorMessage $_.Exception.Message
            throw
        }
    }
    'Destroy' {
        Remove-TestEnvironment
    }
    'All' {
        $deploymentResult = $null
        $testCases = @()
        $testPassed = $false
        try {
            Invoke-Validation
            $deploymentResult = Invoke-Deployment
            $testCases = Invoke-PolicyTest -DeploymentResult $deploymentResult
            $testPassed = $true
            Write-TestResult -Status 'Passed' -TestCases $testCases -ErrorMessage $null
        }
        catch {
            Write-TestResult -Status 'Failed' -TestCases $testCases -ErrorMessage $_.Exception.Message
            throw
        }
        finally {
            if ($testPassed -or -not $KeepOnFailure) {
                Remove-TestEnvironment
            }
            else {
                Write-Warning "Smoke resources retained for diagnosis. Run -Action Destroy -RunId '$RunId' to remove them."
            }
        }
    }
}