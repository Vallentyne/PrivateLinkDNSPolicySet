[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Assert-SmokeTestSubscription.ps1')

$testSubscriptionId = '11111111-1111-1111-1111-111111111111'
$accountResponse = @{ id = $testSubscriptionId; name = 'covallen3-dnstest'; state = 'Enabled' }
$cliExitCode = 0
$cliCalls = [System.Collections.Generic.List[object]]::new()

function az {
    $cliCalls.Add(@($args))
    $global:LASTEXITCODE = $cliExitCode
    if (($args[0..1] -join ' ') -ne 'account show') {
        $subscriptionIndex = [array]::IndexOf($args, '--subscription')
        if ($subscriptionIndex -lt 0 -or $args[$subscriptionIndex + 1] -ne $testSubscriptionId) {
            throw 'Azure command did not explicitly target the verified smoke subscription.'
        }
        throw 'Subscription scope probe complete.'
    }
    $accountResponse | ConvertTo-Json -Compress
}

function Assert-Rejected([scriptblock] $Operation, [string] $ExpectedMessage) {
    $cliCalls.Clear()
    $failure = $null
    try {
        & $Operation
    }
    catch {
        $failure = $_.Exception.Message
    }
    if (-not $failure -or $failure -notlike "*$ExpectedMessage*") {
        throw "Expected rejection containing '$ExpectedMessage'; got '$failure'."
    }
    if ($cliCalls.Count -ne 1 -or ($cliCalls[0][0..1] -join ' ') -ne 'account show') {
        throw 'Subscription rejection must occur before any other Azure command.'
    }
}

foreach ($requested in @($testSubscriptionId, 'covallen3-dnstest')) {
    if ((Assert-SmokeTestSubscription -SubscriptionId $requested) -ne $testSubscriptionId) {
        throw 'The allowed subscription must resolve to its GUID.'
    }
}

foreach ($scriptName in @('Invoke-SmokeTest.ps1', 'Remove-ExpiredSmokeTests.ps1')) {
    $cliCalls.Clear()
    $failure = $null
    try {
        $parameters = @{ SubscriptionId = 'covallen3-dnstest'; ManagementGroupId = 'test' }
        if ($scriptName -eq 'Invoke-SmokeTest.ps1') {
            $parameters.Action = 'Deploy'
            $parameters.RunId = 'guardtest'
        }
        & (Join-Path $PSScriptRoot $scriptName) @parameters
    }
    catch {
        $failure = $_.Exception.Message
    }
    if ($failure -ne 'Subscription scope probe complete.' -or $cliCalls.Count -ne 2) {
        throw "Expected '$scriptName' to explicitly scope its first Azure operation; got '$failure'."
    }
}

$accountResponse.name = 'production'
foreach ($action in @('Deploy', 'Test', 'Destroy', 'All')) {
    Assert-Rejected {
        & (Join-Path $PSScriptRoot 'Invoke-SmokeTest.ps1') -Action $action -SubscriptionId $testSubscriptionId -ManagementGroupId 'test' -RunId 'guardtest'
    } 'Smoke tests may only use subscription'
}
Assert-Rejected {
    & (Join-Path $PSScriptRoot 'Remove-ExpiredSmokeTests.ps1') -SubscriptionId $testSubscriptionId -ManagementGroupId 'test'
} 'Smoke tests may only use subscription'

$accountResponse.name = 'covallen3-dnstest'
$accountResponse.state = 'Disabled'
Assert-Rejected { Assert-SmokeTestSubscription -SubscriptionId $testSubscriptionId } 'is not enabled'
$accountResponse.state = 'Enabled'
$accountResponse.id = 'invalid'
Assert-Rejected { Assert-SmokeTestSubscription -SubscriptionId $testSubscriptionId } 'invalid subscription ID'
$accountResponse.id = $testSubscriptionId
$cliExitCode = 1
Assert-Rejected { Assert-SmokeTestSubscription -SubscriptionId $testSubscriptionId } 'Unable to verify smoke subscription'

$global:LASTEXITCODE = 0
Write-Host '  [PASS] Standard smoke subscription guard and all Azure action entry points'
