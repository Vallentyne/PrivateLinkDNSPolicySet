<#
.SYNOPSIS
    Removes expired regional DNS smoke environments and their exact policy versions.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SubscriptionId,

    [Parameter(Mandatory)]
    [string] $ManagementGroupId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-AzJson([string[]] $Arguments) {
    $output = & az @Arguments --only-show-errors 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: az $($Arguments -join ' ')`n$($output.Trim())"
    }
    if ([string]::IsNullOrWhiteSpace($output)) { return $null }
    return $output | ConvertFrom-Json -Depth 100
}

$null = & az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Unable to select subscription '$SubscriptionId'." }

$now = [DateTimeOffset]::UtcNow
$groups = @(Invoke-AzJson @('group', 'list', '--tag', 'purpose=dns-regional-policy-smoke', '--output', 'json'))
$activeSuffixes = @{}
$expiredSuffixes = @{}

foreach ($group in $groups) {
    $runIdProperty = $group.tags.PSObject.Properties['runId']
    $expiresProperty = $group.tags.PSObject.Properties['expiresOn']
    if (-not $runIdProperty -or -not $expiresProperty) {
        Write-Warning "Skipping '$($group.name)' because its smoke lifecycle tags are incomplete."
        continue
    }

    $suffix = [string] $runIdProperty.Value
    if ([DateTimeOffset]::Parse($expiresProperty.Value) -gt $now) {
        $activeSuffixes[$suffix] = $true
    }
    else {
        $expiredSuffixes[$suffix] = $true
    }
}

foreach ($suffix in $expiredSuffixes.Keys | Where-Object { -not $activeSuffixes.ContainsKey($_) }) {
    Write-Host "Removing expired regional smoke environment '$suffix'."
    & (Join-Path $PSScriptRoot 'Invoke-RegionalRoutingTest.ps1') `
        -Action Destroy `
        -SubscriptionId $SubscriptionId `
        -ManagementGroupId $ManagementGroupId `
        -RunId $suffix
    if ($LASTEXITCODE -ne 0) { throw "Cleanup failed for regional smoke run '$suffix'." }
}

$policySets = @(Invoke-AzJson @('policy', 'set-definition', 'list', '--management-group', $ManagementGroupId, '--output', 'json'))
$prefix = 'custom-regional-dns-private-endpoints-regional-'
foreach ($policySet in $policySets | Where-Object { $_.name -like "$prefix*" }) {
    $suffix = $policySet.name.Substring($prefix.Length)
    if ($activeSuffixes.ContainsKey($suffix)) { continue }

    Write-Host "Removing orphaned regional smoke policy set '$($policySet.name)'."
    $null = & az policy set-definition delete --management-group $ManagementGroupId --name $policySet.name --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Unable to delete '$($policySet.name)'." }

    $definitions = @(Invoke-AzJson @('policy', 'definition', 'list', '--management-group', $ManagementGroupId, '--output', 'json'))
    foreach ($definition in $definitions | Where-Object {
        $version = $_.metadata.PSObject.Properties['version']
        $version -and $version.Value -eq "regional-$suffix"
    }) {
        $null = & az policy definition delete --management-group $ManagementGroupId --name $definition.name --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "Unable to delete '$($definition.name)'." }
    }
}
