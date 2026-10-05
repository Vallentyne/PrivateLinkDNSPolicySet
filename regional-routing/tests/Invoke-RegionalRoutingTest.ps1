<#
.SYNOPSIS
    Runs the reproducible two-region Private DNS policy smoke test.

.EXAMPLE
    ./Invoke-RegionalRoutingTest.ps1 -Action All -SubscriptionId <id> -ManagementGroupId DNStest

.EXAMPLE
    ./Invoke-RegionalRoutingTest.ps1 -Action Destroy -SubscriptionId <id> -ManagementGroupId DNStest -RunId regional0918
#>
[CmdletBinding()]
param(
    [ValidateSet('Validate', 'Deploy', 'Test', 'Destroy', 'All')]
    [string] $Action = 'All',

    [string] $SubscriptionId,

    [string] $ManagementGroupId,

    [string] $PrimaryLocation = 'canadacentral',

    [string] $SecondaryLocation = 'canadaeast',

    [string] $RunId = (Get-Date -Format 'yyyyMMddHHmmss'),

    [ValidateRange(10, 120)]
    [int] $TimeoutMinutes = 45,

    [Alias('KeepResources')]
    [switch] $KeepOnFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RegionalRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RepoRoot = (Resolve-Path (Join-Path $RegionalRoot '..')).Path
$PolicyTemplate = Join-Path $RegionalRoot 'pubsecDNS.regional.bicep'
$PolicyParameters = Join-Path $RegionalRoot 'pubsecDNS.regional.bicepparam'
$FoundationTemplate = Join-Path $PSScriptRoot 'foundation.bicep'
$EndpointTemplate = Join-Path $PSScriptRoot 'private-endpoints.bicep'
$SmokeMatrixPath = Join-Path $PSScriptRoot 'smoke-matrix.json'
$CoverageTest = Join-Path $RepoRoot 'Test-PolicyCoverage.ps1'
$SmokeMatrix = Get-Content -LiteralPath $SmokeMatrixPath -Raw | ConvertFrom-Json -Depth 20

$normalizedRunId = ($RunId.ToLowerInvariant() -replace '[^a-z0-9]', '')
if ($normalizedRunId.Length -lt 3) {
    throw 'RunId must contain at least three letters or numbers.'
}
$NameSuffix = $normalizedRunId.Substring([Math]::Max(0, $normalizedRunId.Length - [Math]::Min(12, $normalizedRunId.Length)))
$PolicyVersion = "regional-$NameSuffix"
$PolicySetName = "custom-regional-dns-private-endpoints-$PolicyVersion"
$AssignmentName = "dns-regional-$NameSuffix"
$WorkloadResourceGroupName = "rg-dns-regional-test-$NameSuffix"
$PrimaryDnsResourceGroupName = "rg-dns-regional-cc-$NameSuffix"
$SecondaryDnsResourceGroupName = "rg-dns-regional-ce-$NameSuffix"
$ResultPath = Join-Path $PSScriptRoot "results/$NameSuffix.json"
$SubscriptionScope = "/subscriptions/$SubscriptionId"
$WorkloadScope = "$SubscriptionScope/resourceGroups/$WorkloadResourceGroupName"
$PrimaryDnsScope = "$SubscriptionScope/resourceGroups/$PrimaryDnsResourceGroupName"
$SecondaryDnsScope = "$SubscriptionScope/resourceGroups/$SecondaryDnsResourceGroupName"

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-AzCli {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $Json
    )

    $output = $null
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        Write-Verbose "az $($Arguments -join ' ')"
        $output = & az @Arguments --only-show-errors 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { break }

        $isTransient = $output -match 'ConnectionResetError|Connection aborted|temporarily unavailable|timed out|TooManyRequests|InternalServerError'
        if (-not $isTransient -or $attempt -eq 4) {
            throw "Azure CLI failed: az $($Arguments -join ' ')`n$($output.Trim())"
        }
        Write-Warning "Azure CLI transport failure; retrying in $($attempt * 10) seconds ($attempt/4)."
        Start-Sleep -Seconds ($attempt * 10)
    }
    if ($Json) {
        if ([string]::IsNullOrWhiteSpace($output)) { return $null }
        return $output | ConvertFrom-Json -Depth 100
    }
    return $output.Trim()
}

function Assert-AzureContext {
    if ($Action -eq 'Validate') { return }
    if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or [string]::IsNullOrWhiteSpace($ManagementGroupId)) {
        throw 'SubscriptionId and ManagementGroupId are required for Azure actions.'
    }
    $null = Invoke-AzCli -Arguments @('account', 'set', '--subscription', $SubscriptionId)
    $account = Invoke-AzCli -Arguments @('account', 'show', '--output', 'json') -Json
    if ($account.id -ne $SubscriptionId) {
        throw "Azure CLI selected subscription '$($account.id)' instead of '$SubscriptionId'."
    }
    Write-Host "  [READY] $($account.name) ($($account.id))"
}

function Invoke-Validation {
    Write-Step 'Running static validation'
    if ($SmokeMatrix.schemaVersion -ne 1) { throw "Unsupported smoke matrix schema version '$($SmokeMatrix.schemaVersion)'." }
    if (@($SmokeMatrix.routes).Count -ne 6 -or $SmokeMatrix.regionsPerRoute -ne 2) {
        throw 'The regional smoke contract must contain exactly six routes across two regions.'
    }
    $routeKeys = @($SmokeMatrix.routes.key)
    if (@($routeKeys | Sort-Object -Unique).Count -ne $routeKeys.Count) { throw 'Smoke matrix route keys must be unique.' }
    foreach ($route in $SmokeMatrix.routes) {
        if ([string]::IsNullOrWhiteSpace($route.key) -or [string]::IsNullOrWhiteSpace($route.targetResourceKey) -or
            [string]::IsNullOrWhiteSpace($route.resourceNamespace) -or [string]::IsNullOrWhiteSpace($route.groupId) -or
            @($route.expectedZones).Count -eq 0) {
            throw "Smoke matrix route '$($route.key)' is incomplete."
        }
    }
    Write-Host "  [PASS] smoke-matrix.json ($(@($SmokeMatrix.routes).Count) routes, $(@($SmokeMatrix.routes).Count * 2) cases)"
    & $CoverageTest
    if ($LASTEXITCODE -ne 0) { throw 'Test-PolicyCoverage.ps1 failed.' }

    foreach ($template in @($PolicyTemplate, $FoundationTemplate, $EndpointTemplate)) {
        $null = Invoke-AzCli -Arguments @('bicep', 'build', '--file', $template, '--stdout')
        Write-Host "  [PASS] $(Split-Path $template -Leaf)"
    }
    $null = Invoke-AzCli -Arguments @('bicep', 'build-params', '--file', $PolicyParameters, '--stdout')
    Write-Host "  [PASS] $(Split-Path $PolicyParameters -Leaf)"
}

function Register-TestProviders {
    Write-Step 'Registering required resource providers'
    foreach ($provider in @('Microsoft.AppConfiguration', 'Microsoft.Authorization', 'Microsoft.Batch', 'Microsoft.CognitiveServices', 'Microsoft.KeyVault', 'Microsoft.Network', 'Microsoft.PolicyInsights', 'Microsoft.Storage')) {
        $state = Invoke-AzCli -Arguments @('provider', 'show', '--namespace', $provider, '--query', 'registrationState', '--output', 'tsv')
        if ($state -ne 'Registered') {
            $null = Invoke-AzCli -Arguments @('provider', 'register', '--namespace', $provider, '--wait')
        }
        Write-Host "  [READY] $provider"
    }
}

function Assert-CleanRun {
    foreach ($resourceGroup in @($WorkloadResourceGroupName, $PrimaryDnsResourceGroupName, $SecondaryDnsResourceGroupName)) {
        if ((Invoke-AzCli -Arguments @('group', 'exists', '--name', $resourceGroup)) -eq 'true') {
            throw "RunId '$RunId' is already in use by '$resourceGroup'. Choose a new RunId or run -Action Destroy first."
        }
    }
}

function Invoke-WhatIf([string] $ExpiresOn) {
    Write-Step 'Previewing management-group policy changes'
    $null = Invoke-AzCli -Arguments @(
        'deployment', 'mg', 'what-if',
        '--management-group-id', $ManagementGroupId,
        '--location', $PrimaryLocation,
        '--name', "regional-policy-$NameSuffix",
        '--template-file', $PolicyTemplate,
        '--parameters', "policyDefinitionManagementGroupId=$ManagementGroupId", "policyVersion=$PolicyVersion"
    )

    Write-Step 'Previewing subscription lab changes'
    $null = Invoke-AzCli -Arguments @(
        'deployment', 'sub', 'what-if',
        '--location', $PrimaryLocation,
        '--name', "regional-foundation-$NameSuffix",
        '--template-file', $FoundationTemplate,
        '--parameters', "nameSuffix=$NameSuffix", "primaryLocation=$PrimaryLocation", "secondaryLocation=$SecondaryLocation", "expiresOn=$ExpiresOn"
    )
}

function Add-RoleAssignment([string] $PrincipalId, [string] $Role, [string] $Scope) {
    $null = Invoke-AzCli -Arguments @(
        'role', 'assignment', 'create',
        '--assignee-object-id', $PrincipalId,
        '--assignee-principal-type', 'ServicePrincipal',
        '--role', $Role,
        '--scope', $Scope
    )
}

function Get-PolicySet {
    return Invoke-AzCli -Arguments @(
        'policy', 'set-definition', 'show',
        '--management-group', $ManagementGroupId,
        '--name', $PolicySetName,
        '--output', 'json'
    ) -Json
}

function Invoke-Deployment {
    Register-TestProviders
    Assert-CleanRun
    $expiresOn = (Get-Date).ToUniversalTime().AddHours(6).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Invoke-WhatIf -ExpiresOn $expiresOn

    Write-Step "Deploying regional initiative $PolicyVersion"
    $null = Invoke-AzCli -Arguments @(
        'deployment', 'mg', 'create',
        '--management-group-id', $ManagementGroupId,
        '--location', $PrimaryLocation,
        '--name', "regional-policy-$NameSuffix",
        '--template-file', $PolicyTemplate,
        '--parameters', "policyDefinitionManagementGroupId=$ManagementGroupId", "policyVersion=$PolicyVersion"
    )

    Write-Step 'Deploying regional lab foundation'
    $foundation = Invoke-AzCli -Arguments @(
        'deployment', 'sub', 'create',
        '--location', $PrimaryLocation,
        '--name', "regional-foundation-$NameSuffix",
        '--template-file', $FoundationTemplate,
        '--parameters', "nameSuffix=$NameSuffix", "primaryLocation=$PrimaryLocation", "secondaryLocation=$SecondaryLocation", "expiresOn=$expiresOn",
        '--query', 'properties.outputs',
        '--output', 'json'
    ) -Json

    $targets = @{
        regionalPrivateDnsZoneTargets = @{
            value = @{
                $PrimaryLocation = @{
                    subscriptionId = $SubscriptionId
                    resourceGroupName = $PrimaryDnsResourceGroupName
                }
                $SecondaryLocation = @{
                    subscriptionId = $SubscriptionId
                    resourceGroupName = $SecondaryDnsResourceGroupName
                }
            }
        }
    } | ConvertTo-Json -Depth 8 -Compress

    Write-Step 'Assigning the regional initiative to the disposable workload resource group'
    $policySet = Get-PolicySet
    $assignment = Invoke-AzCli -Arguments @(
        'policy', 'assignment', 'create',
        '--name', $AssignmentName,
        '--display-name', "Regional DNS routing test $NameSuffix",
        '--scope', $WorkloadScope,
        '--policy-set-definition', $policySet.id,
        '--params', $targets,
        '--mi-system-assigned',
        '--identity-scope', $WorkloadScope,
        '--role', 'Network Contributor',
        '--location', $PrimaryLocation,
        '--output', 'json'
    ) -Json

    Add-RoleAssignment -PrincipalId $assignment.identity.principalId -Role 'Private DNS Zone Contributor' -Scope $PrimaryDnsScope
    Add-RoleAssignment -PrincipalId $assignment.identity.principalId -Role 'Private DNS Zone Contributor' -Scope $SecondaryDnsScope

    Write-Step 'Previewing and deploying private endpoints without DNS zone groups'
    $parameterFile = Join-Path ([System.IO.Path]::GetTempPath()) "regional-endpoints-$NameSuffix.parameters.json"
    try {
        [ordered]@{
            '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
            contentVersion = '1.0.0.0'
            parameters = [ordered]@{
                nameSuffix = @{ value = $NameSuffix }
                primaryLocation = @{ value = $PrimaryLocation }
                secondaryLocation = @{ value = $SecondaryLocation }
                primarySubnetId = @{ value = $foundation.primarySubnetId.value }
                secondarySubnetId = @{ value = $foundation.secondarySubnetId.value }
                targetResourceIds = @{ value = $foundation.targetResourceIds.value }
            }
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $parameterFile -Encoding utf8

        $null = Invoke-AzCli -Arguments @(
            'deployment', 'group', 'what-if',
            '--resource-group', $WorkloadResourceGroupName,
            '--name', "regional-endpoints-$NameSuffix",
            '--template-file', $EndpointTemplate,
            '--parameters', "@$parameterFile"
        )
        $endpointOutputs = Invoke-AzCli -Arguments @(
            'deployment', 'group', 'create',
            '--resource-group', $WorkloadResourceGroupName,
            '--name', "regional-endpoints-$NameSuffix",
            '--template-file', $EndpointTemplate,
            '--parameters', "@$parameterFile",
            '--query', 'properties.outputs',
            '--output', 'json'
        ) -Json
    }
    finally {
        Remove-Item -LiteralPath $parameterFile -Force -ErrorAction SilentlyContinue
    }

    $testCases = @($endpointOutputs.testCases.value)
    Assert-TestCaseContract -TestCases $testCases

    return [pscustomobject]@{
        testCases = $testCases
    }
}

function Assert-TestCaseContract($TestCases) {
    $expectedCases = @()
    foreach ($route in $SmokeMatrix.routes) {
        foreach ($region in @(
            [pscustomobject]@{ Code = 'cc'; Route = 'primary' },
            [pscustomobject]@{ Code = 'ce'; Route = 'secondary' }
        )) {
            $expectedCases += [pscustomobject]@{
                endpointName = "pe-$($route.key)-$($region.Code)-$NameSuffix"
                route = $region.Route
                resourceNamespace = $route.resourceNamespace
                groupId = $route.groupId
                expectedZones = @($route.expectedZones)
            }
        }
    }
    if (@($TestCases).Count -ne $expectedCases.Count) {
        throw "Smoke deployment emitted $(@($TestCases).Count) cases; expected $($expectedCases.Count)."
    }
    foreach ($expected in $expectedCases) {
        $actual = @($TestCases | Where-Object { $_.endpointName -eq $expected.endpointName })
        if ($actual.Count -ne 1) { throw "Expected exactly one smoke case named '$($expected.endpointName)', found $($actual.Count)." }
        if ($actual[0].route -ne $expected.route -or $actual[0].resourceNamespace -ne $expected.resourceNamespace -or $actual[0].groupId -ne $expected.groupId) {
            throw "Smoke case '$($expected.endpointName)' does not match smoke-matrix.json."
        }
        if (@(Compare-Object (@($expected.expectedZones | Sort-Object)) (@($actual[0].expectedZones | Sort-Object))).Count -gt 0) {
            throw "Smoke case '$($expected.endpointName)' has unexpected DNS zones."
        }
    }
    Write-Host "  [PASS] Deployment output matches all $($expectedCases.Count) declared smoke cases."
}

function Get-PolicyReferences {
    $policySet = Get-PolicySet
    $references = @()
    foreach ($route in $SmokeMatrix.routes) {
        $matches = @($policySet.policyDefinitions | Where-Object {
            $_.parameters.privateLinkServiceNamespace.value -eq $route.resourceNamespace -and
            $_.parameters.groupId.value -eq $route.groupId
        })
        if ($matches.Count -ne 1) {
            throw "Expected one policy reference for '$($route.resourceNamespace)|$($route.groupId)', found $($matches.Count)."
        }
        $references += [pscustomobject]@{
            Key = $route.key
            ReferenceId = $matches[0].policyDefinitionReferenceId
        }
    }
    return $references
}

function Wait-ForRemediation([string] $Name) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        $remediation = Invoke-AzCli -Arguments @(
            'policy', 'remediation', 'show',
            '--name', $Name,
            '--resource-group', $WorkloadResourceGroupName,
            '--output', 'json'
        ) -Json
        if ($remediation.provisioningState -in @('Failed', 'Canceled')) {
            $status = $remediation.deploymentStatus
            throw "Remediation '$Name' ended in state '$($remediation.provisioningState)' ($($status.successfulDeployments) succeeded, $($status.failedDeployments) failed)."
        }
        if ($remediation.provisioningState -eq 'Succeeded') { return }
        Write-Host "  Waiting for remediation: $($remediation.provisioningState)"
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $deadline)
    throw "Remediation '$Name' did not finish within $TimeoutMinutes minutes."
}

function Test-EndpointRoute($TestCase) {
    $EndpointName = $TestCase.endpointName
    $expectedScope = if ($TestCase.route -eq 'primary') { $PrimaryDnsScope } else { $SecondaryDnsScope }
    $unexpectedScope = if ($TestCase.route -eq 'primary') { $SecondaryDnsScope } else { $PrimaryDnsScope }
    $expectedLocation = if ($TestCase.route -eq 'primary') { $PrimaryLocation } else { $SecondaryLocation }
    $endpoint = Invoke-AzCli -Arguments @(
        'network', 'private-endpoint', 'show',
        '--name', $EndpointName,
        '--resource-group', $WorkloadResourceGroupName,
        '--output', 'json'
    ) -Json
    if ($endpoint.provisioningState -ne 'Succeeded') { return "private endpoint state is '$($endpoint.provisioningState)'" }
    if ($endpoint.location -ne $expectedLocation) { return "endpoint location is '$($endpoint.location)'; expected '$expectedLocation'" }
    $expectedZoneIds = @($TestCase.expectedZones | ForEach-Object { "$expectedScope/providers/Microsoft.Network/privateDnsZones/$_" })
    $unexpectedZoneIds = @($TestCase.expectedZones | ForEach-Object { "$unexpectedScope/providers/Microsoft.Network/privateDnsZones/$_" })
    $groups = @(Invoke-AzCli -Arguments @(
        'network', 'private-endpoint', 'dns-zone-group', 'list',
        '--endpoint-name', $EndpointName,
        '--resource-group', $WorkloadResourceGroupName,
        '--output', 'json'
    ) -Json)
    if ($groups.Count -ne 1) { return "expected one DNS zone group, found $($groups.Count)" }

    $actualZoneIds = @($groups[0].privateDnsZoneConfigs.privateDnsZoneId)
    if (@(Compare-Object -ReferenceObject $expectedZoneIds -DifferenceObject $actualZoneIds).Count -gt 0) {
        return "zone mismatch; expected [$($expectedZoneIds -join ', ')], actual [$($actualZoneIds -join ', ')]"
    }
    if ($actualZoneIds | Where-Object { $_ -in $unexpectedZoneIds }) {
        return 'zone group unexpectedly references the other regional DNS resource group'
    }

    $nic = Invoke-AzCli -Arguments @('network', 'nic', 'show', '--ids', $endpoint.networkInterfaces[0].id, '--output', 'json') -Json
    $endpointIps = @($nic.ipConfigurations.privateIPAddress)
    foreach ($zoneName in $TestCase.expectedZones) {
        $zoneResourceGroup = ($expectedScope -split '/')[4]
        $recordSets = @(Invoke-AzCli -Arguments @(
            'network', 'private-dns', 'record-set', 'a', 'list',
            '--resource-group', $zoneResourceGroup,
            '--zone-name', $zoneName,
            '--output', 'json'
        ) -Json)
        $recordIps = @($recordSets.aRecords.ipv4Address)
        if (-not ($endpointIps | Where-Object { $_ -in $recordIps })) {
            return "zone '$zoneName' has no A record for endpoint IP [$($endpointIps -join ', ')]"
        }
    }
    return $null
}

function Invoke-PolicyTest {
    $endpointDeployment = Invoke-AzCli -Arguments @(
        'deployment', 'group', 'show',
        '--resource-group', $WorkloadResourceGroupName,
        '--name', "regional-endpoints-$NameSuffix",
        '--output', 'json'
    ) -Json
    $testCases = @($endpointDeployment.properties.outputs.testCases.value)
    Assert-TestCaseContract -TestCases $testCases

    Write-Step 'Starting targeted policy remediations'
    $references = Get-PolicyReferences
    foreach ($reference in $references) {
        $remediationName = "rem-$($reference.Key)-$NameSuffix"
        $null = Invoke-AzCli -Arguments @(
            'policy', 'remediation', 'create',
            '--name', $remediationName,
            '--resource-group', $WorkloadResourceGroupName,
            '--policy-assignment', $AssignmentName,
            '--definition-reference-id', $reference.ReferenceId,
            '--resource-discovery-mode', 'ReEvaluateCompliance'
        )
        Write-Host "  [STARTED] $($reference.Key)"
        Wait-ForRemediation -Name $remediationName
        Write-Host "  [PASS] $($reference.Key) remediation"
    }

    Write-Step 'Verifying exact regional DNS zone IDs and A records'
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        $failures = @()
        foreach ($testCase in $testCases) {
            $failure = Test-EndpointRoute -TestCase $testCase
            if ($failure) { $failures += "$($testCase.endpointName): $failure" }
        }
        if ($failures.Count -eq 0) {
            foreach ($testCase in $testCases) { Write-Host "  [PASS] $($testCase.endpointName) -> $($testCase.route)" }
            return $testCases
        }
        Write-Host "  Pending: $($failures -join '; ')"
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $deadline)

    throw "Regional DNS assertions did not pass within $TimeoutMinutes minutes: $($failures -join '; ')"
}

function Remove-TestEnvironment {
    Write-Step "Removing regional routing test $NameSuffix"
    try { $null = Invoke-AzCli -Arguments @('policy', 'assignment', 'delete', '--name', $AssignmentName, '--scope', $WorkloadScope) } catch { Write-Verbose $_ }
    foreach ($resourceGroup in @($WorkloadResourceGroupName, $PrimaryDnsResourceGroupName, $SecondaryDnsResourceGroupName)) {
        if ((Invoke-AzCli -Arguments @('group', 'exists', '--name', $resourceGroup)) -eq 'true') {
            $null = Invoke-AzCli -Arguments @('group', 'delete', '--name', $resourceGroup, '--yes', '--no-wait')
            Write-Host "  [DELETE STARTED] $resourceGroup"
        }
    }
    try { $null = Invoke-AzCli -Arguments @('policy', 'set-definition', 'delete', '--management-group', $ManagementGroupId, '--name', $PolicySetName) } catch { Write-Verbose $_ }
    $definitions = @(Invoke-AzCli -Arguments @('policy', 'definition', 'list', '--management-group', $ManagementGroupId, '--output', 'json') -Json)
    foreach ($definition in $definitions | Where-Object { $_.metadata.version -eq $PolicyVersion }) {
        $null = Invoke-AzCli -Arguments @('policy', 'definition', 'delete', '--management-group', $ManagementGroupId, '--name', $definition.name)
    }
}

function Write-TestResult([string] $Status, $Routes, [string] $ErrorMessage) {
    $directory = Split-Path $ResultPath -Parent
    $null = New-Item -ItemType Directory -Path $directory -Force
    [ordered]@{
        runId = $RunId
        subscriptionId = $SubscriptionId
        managementGroupId = $ManagementGroupId
        policySetName = $PolicySetName
        assignmentName = $AssignmentName
        resourceGroups = @($WorkloadResourceGroupName, $PrimaryDnsResourceGroupName, $SecondaryDnsResourceGroupName)
        status = $Status
        completedAt = (Get-Date).ToUniversalTime().ToString('o')
        error = $ErrorMessage
        routes = @($Routes)
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $ResultPath -Encoding utf8
    Write-Host "Result: $ResultPath"
}

$null = Get-Command az -ErrorAction Stop
Assert-AzureContext

switch ($Action) {
    'Validate' { Invoke-Validation }
    'Deploy' { Invoke-Validation; $null = Invoke-Deployment }
    'Test' {
        $routes = @()
        try {
            $routes = Invoke-PolicyTest
            Write-TestResult -Status 'Passed' -Routes $routes -ErrorMessage $null
        }
        catch {
            Write-TestResult -Status 'Failed' -Routes $routes -ErrorMessage $_.Exception.Message
            throw
        }
    }
    'Destroy' { Remove-TestEnvironment }
    'All' {
        $deploymentResult = $null
        $routes = @()
        $testPassed = $false
        try {
            Invoke-Validation
            $deploymentResult = Invoke-Deployment
            $routes = @($deploymentResult.testCases)
            $routes = Invoke-PolicyTest
            $testPassed = $true
            Write-TestResult -Status 'Passed' -Routes $routes -ErrorMessage $null
        }
        catch {
            Write-TestResult -Status 'Failed' -Routes $routes -ErrorMessage $_.Exception.Message
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