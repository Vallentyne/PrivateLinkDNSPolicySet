<#
.SYNOPSIS
    Removes expired DNS policy smoke environments and orphaned smoke policy definitions.
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
. (Join-Path $PSScriptRoot 'Assert-SmokeTestSubscription.ps1')

function Invoke-AzJson([string[]] $Arguments) {
    $Arguments += @('--subscription', $SubscriptionId)
    $output = $null
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $output = & az @Arguments --only-show-errors 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { break }

        $isTransient = $output -match 'ConnectionResetError|Connection aborted|temporarily unavailable|timed out|TooManyRequests|InternalServerError'
        if (-not $isTransient -or $attempt -eq 4) {
            throw "Azure CLI failed: az $($Arguments -join ' ')`n$($output.Trim())"
        }
        Write-Warning "Azure CLI transport failure; retrying in $($attempt * 10) seconds ($attempt/4)."
        Start-Sleep -Seconds ($attempt * 10)
    }
    if ([string]::IsNullOrWhiteSpace($output)) { return $null }
    return $output | ConvertFrom-Json -Depth 100
}

$SubscriptionId = Assert-SmokeTestSubscription -SubscriptionId $SubscriptionId

$now = [DateTimeOffset]::UtcNow
$groups = @(Invoke-AzJson @('group', 'list', '--tag', 'purpose=dns-policy-smoke', '--output', 'json'))
$activeSuffixes = @{}

foreach ($group in $groups) {
    $suffix = $group.name -replace '^rg-dns-policy-smoke-', ''
    $expiresProperty = $group.tags.PSObject.Properties['expiresOn']
    if (-not $expiresProperty) {
        Write-Warning "Skipping '$($group.name)' because it has no expiresOn tag."
        $activeSuffixes[$suffix] = $true
        continue
    }

    $expiresOn = [DateTimeOffset]::Parse($expiresProperty.Value)
    if ($expiresOn -gt $now) {
        $activeSuffixes[$suffix] = $true
        continue
    }

    Write-Host "Removing expired smoke environment '$($group.name)' (expired $expiresOn)."
    & (Join-Path $PSScriptRoot 'Invoke-SmokeTest.ps1') `
        -Action Destroy `
        -SubscriptionId $SubscriptionId `
        -ManagementGroupId $ManagementGroupId `
        -RunId $suffix
    if ($LASTEXITCODE -ne 0) {
        throw "Cleanup failed for '$($group.name)'."
    }
}

$policySets = @(Invoke-AzJson @('policy', 'set-definition', 'list', '--management-group', $ManagementGroupId, '--output', 'json'))
$smokePrefix = 'custom-central-dns-private-endpoints-smoke-'
foreach ($policySet in $policySets | Where-Object { $_.name -like "$smokePrefix*" }) {
    $suffix = $policySet.name.Substring($smokePrefix.Length)
    if (-not $activeSuffixes.ContainsKey($suffix)) {
        Write-Host "Removing orphaned smoke policy set '$($policySet.name)'."
        $null = & az policy set-definition delete --management-group $ManagementGroupId --name $policySet.name --subscription $SubscriptionId --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "Unable to delete '$($policySet.name)'." }
    }
}

$definitions = @(Invoke-AzJson @('policy', 'definition', 'list', '--management-group', $ManagementGroupId, '--output', 'json'))
foreach ($definition in $definitions | Where-Object {
    $versionProperty = $_.metadata.PSObject.Properties['version']
    $versionProperty -and $versionProperty.Value -like 'smoke-*'
}) {
    $suffix = $definition.metadata.version -replace '^smoke-', ''
    if (-not $activeSuffixes.ContainsKey($suffix)) {
        Write-Host "Removing orphaned smoke policy definition '$($definition.name)'."
        $null = & az policy definition delete --management-group $ManagementGroupId --name $definition.name --subscription $SubscriptionId --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "Unable to delete '$($definition.name)'." }
    }
}