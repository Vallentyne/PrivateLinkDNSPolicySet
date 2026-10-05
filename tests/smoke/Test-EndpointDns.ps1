[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Invoke-SmokeTest.ps1'), [ref] $tokens, [ref] $parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw "Smoke runner has PowerShell syntax errors: $($parseErrors -join '; ')"
}
$function = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-EndpointDns'
}, $true)
if (-not $function) { throw 'Test-EndpointDns function was not found.' }
. ([scriptblock]::Create($function.Extent.Text))

$ResourceGroupName = 'mock-smoke'
$recordName = 'redis-smoke.canadaeast'
$endpointIp = '10.42.1.16'
$recordIp = $endpointIp
$zoneName = 'privatelink.redis.azure.net'

function Invoke-AzCli {
    param([string[]] $Arguments, [switch] $Json)
    switch ($Arguments[1]) {
        'private-endpoint' {
            if ($Arguments[2] -eq 'dns-zone-group') {
                return [pscustomobject]@{
                    privateDnsZoneConfigs = @([pscustomobject]@{ privateDnsZoneId = "/privateDnsZones/$zoneName" })
                }
            }
            return [pscustomobject]@{ networkInterfaces = @([pscustomobject]@{ id = '/mock-nic' }) }
        }
        'nic' {
            return [pscustomobject]@{ ipConfigurations = @([pscustomobject]@{ privateIPAddress = $endpointIp }) }
        }
        'private-dns' {
            return [pscustomobject]@{
                name = $recordName
                aRecords = @([pscustomobject]@{ ipv4Address = $recordIp })
            }
        }
        default { throw "Unexpected mocked Azure command: $($Arguments -join ' ')" }
    }
}

foreach ($properties in @(
    @{ }
    @{ expectedRecordNames = @() }
    @{ expectedRecordNames = $null }
    @{ expectedRecordNames = @($recordName) }
)) {
    $case = [pscustomobject]( $properties + @{ endpointName = 'mock'; expectedZones = @($zoneName) } )
    $failure = Test-EndpointDns -TestCase $case
    if ($failure) { throw "Valid DNS case rejected: $failure" }
}

$case.expectedRecordNames = @('missing-record')
if ((Test-EndpointDns -TestCase $case) -notlike '*missing expected A record*') {
    throw 'A missing explicit DNS record must fail.'
}
$case.expectedRecordNames = @()
$recordIp = '10.42.1.99'
if ((Test-EndpointDns -TestCase $case) -notlike '*no A record for endpoint IP*') {
    throw 'An incorrect DNS IP must fail.'
}
$recordIp = $endpointIp
$zoneName = 'privatelink.redisenterprise.cache.azure.net'
if ((Test-EndpointDns -TestCase $case) -notlike '*zone mismatch*') {
    throw 'A legacy Redis zone must not satisfy a Managed Redis test.'
}

Write-Host '  [PASS] DNS assertions: optional record names, explicit records, IPs and exact zones'
