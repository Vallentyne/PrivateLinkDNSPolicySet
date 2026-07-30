<#
.SYNOPSIS
    Validates that pubsecDNS.parameters.json and pubsecDNS.bicep are fully consistent with service-catalog.json.

.DESCRIPTION
    service-catalog.json is the single source of truth for all supported Private Link DNS services.
    This script performs four cross-checks:

      Check 1 - Catalog vs Parameters  : every catalog entry has a matching zone entry in parameters.json
      Check 2 - Parameters vs Catalog  : every parameters.json zone has a matching catalog entry (no undocumented zones)
      Check 3 - Catalog vs Bicep Map   : every 'builtin' catalog entry is in pubsecDNS.bicep builtInPolicyMap with correct policy ID
      Check 4 - Bicep Map vs Catalog   : every builtInPolicyMap entry has a catalog entry (no orphaned map entries)

    Exits with code 0 on full pass, 1 if any check fails. Safe to use in CI/CD pipelines.

.EXAMPLE
    .\Test-PolicyCoverage.ps1
    .\Test-PolicyCoverage.ps1 -Verbose
    .\Test-PolicyCoverage.ps1 -CatalogPath .\service-catalog.json -ParametersPath .\pubsecDNS.parameters.json -BicepPath .\pubsecDNS.bicep
#>
[CmdletBinding()]
param(
    [string] $CatalogPath,
    [string] $ParametersPath,
    [string] $BicepPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve script directory robustly (works with .\script.ps1, -File, and dot-sourcing)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
if (-not $CatalogPath)    { $CatalogPath    = Join-Path $ScriptDir 'service-catalog.json' }
if (-not $ParametersPath) { $ParametersPath = Join-Path $ScriptDir 'pubsecDNS.parameters.json' }
if (-not $BicepPath)      { $BicepPath      = Join-Path $ScriptDir 'pubsecDNS.bicep' }

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Header([string]$text) {
    Write-Host "`n$('─' * 70)" -ForegroundColor DarkGray
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host "$('─' * 70)" -ForegroundColor DarkGray
}

function Write-Pass([string]$msg)  { Write-Host "  [PASS]  $msg" -ForegroundColor Green  }
function Write-Fail([string]$msg)  { Write-Host "  [FAIL]  $msg" -ForegroundColor Red    }
function Write-Info([string]$msg)  { Write-Host "  [INFO]  $msg" -ForegroundColor Gray   }
function Write-Warn([string]$msg)  { Write-Host "  [WARN]  $msg" -ForegroundColor Yellow }

# Canonical key for a zone entry — unique across the whole catalog
function Get-ZoneKey([string]$namespace, [string]$groupId, [string]$filter, [string]$zone) {
    return "$namespace|$groupId|$filter|$zone"
}

# Key used by the Bicep builtInPolicyMap (no filter, no zone)
function Get-BicepKey([string]$namespace, [string]$groupId) {
    return "$namespace-$groupId"
}

# ── Load files ────────────────────────────────────────────────────────────────

Write-Header "Loading files"

foreach ($path in @($CatalogPath, $ParametersPath, $BicepPath)) {
    if (-not (Test-Path $path)) {
        Write-Fail "File not found: $path"
        exit 1
    }
    Write-Info (Split-Path $path -Leaf)
}

$catalog    = (Get-Content $CatalogPath    -Raw | ConvertFrom-Json).entries
$parameters = (Get-Content $ParametersPath -Raw | ConvertFrom-Json).parameters.privateDNSZones.value
$bicepRaw   = Get-Content $BicepPath       -Raw

# Parse builtInPolicyMap from Bicep: lines of the form
#   'Namespace/type-groupId': 'guid'
$bicepMapEntries = @{}
$mapBlock = ($bicepRaw -split '(?ms)var builtInPolicyMap\s*=\s*\{')[1] -split '\}' | Select-Object -First 1
$mapBlock -split "`n" | ForEach-Object {
    if ($_ -match "^\s*'([^']+)'\s*:\s*'([0-9a-f\-]+)'") {
        $bicepMapEntries[$Matches[1]] = $Matches[2]
    }
}

Write-Pass "Catalog     : $($catalog.Count) entries"
Write-Pass "Parameters  : $($parameters.Count) zone entries"
Write-Pass "Bicep map   : $($bicepMapEntries.Count) built-in policy entries"

# ── Build lookup tables ───────────────────────────────────────────────────────

# Catalog indexed by zone key
$catalogByZoneKey = @{}
foreach ($entry in $catalog) {
    $key = Get-ZoneKey $entry.resourceNamespace $entry.groupId $entry.filterLocationLike $entry.dnsZone
    if ($catalogByZoneKey.ContainsKey($key)) {
        Write-Fail "CATALOG DUPLICATE KEY: $key"
        exit 1
    }
    $catalogByZoneKey[$key] = $entry
}

# Parameters indexed by zone key
$paramsByZoneKey = @{}
foreach ($zone in $parameters) {
    $key = Get-ZoneKey $zone.privateLinkServiceNamespace $zone.groupId $zone.filterLocationLike $zone.zone
    if ($paramsByZoneKey.ContainsKey($key)) {
        Write-Warn "Parameters has duplicate zone key: $key"
    }
    $paramsByZoneKey[$key] = $zone
}

# ── Check 1: Catalog → Parameters ────────────────────────────────────────────

Write-Header "Check 1: Catalog → Parameters (every catalog entry exists in parameters.json)"

$check1Failures = @()
foreach ($entry in $catalog) {
    $key = Get-ZoneKey $entry.resourceNamespace $entry.groupId $entry.filterLocationLike $entry.dnsZone
    if ($paramsByZoneKey.ContainsKey($key)) {
        Write-Verbose "  ✅ $($entry.logicalService)"
    } else {
        $check1Failures += $entry
        Write-Fail "MISSING from parameters.json: $($entry.logicalService)"
        Write-Fail "      namespace : $($entry.resourceNamespace)"
        Write-Fail "      groupId   : $($entry.groupId)"
        Write-Fail "      filter    : $($entry.filterLocationLike)"
        Write-Fail "      zone      : $($entry.dnsZone)"
    }
}

if ($check1Failures.Count -eq 0) {
    Write-Pass "All $($catalog.Count) catalog entries found in parameters.json"
} else {
    Write-Fail "$($check1Failures.Count) catalog entries missing from parameters.json"
}

# ── Check 2: Parameters → Catalog ────────────────────────────────────────────

Write-Header "Check 2: Parameters → Catalog (no undocumented zone entries in parameters.json)"

$check2Failures = @()
foreach ($zone in $parameters) {
    $key = Get-ZoneKey $zone.privateLinkServiceNamespace $zone.groupId $zone.filterLocationLike $zone.zone
    if ($catalogByZoneKey.ContainsKey($key)) {
        Write-Verbose "  ✅ $($zone.privateLinkServiceNamespace) | $($zone.groupId)"
    } else {
        $check2Failures += $zone
        Write-Fail "NOT IN CATALOG: $($zone.privateLinkServiceNamespace) | groupId=$($zone.groupId) | filter=$($zone.filterLocationLike) | zone=$($zone.zone)"
        Write-Warn "      → Add this entry to service-catalog.json before the next deployment"
    }
}

if ($check2Failures.Count -eq 0) {
    Write-Pass "All $($parameters.Count) parameter zones are documented in the catalog"
} else {
    Write-Fail "$($check2Failures.Count) undocumented zone(s) found in parameters.json"
}

# ── Check 3: Catalog builtins → Bicep map ─────────────────────────────────────

Write-Header "Check 3: Catalog (builtin) → Bicep builtInPolicyMap"

$check3Failures = @()
$builtinCatalogEntries = $catalog | Where-Object { $_.policyType -eq 'builtin' }

foreach ($entry in $builtinCatalogEntries) {
    $bicepKey = Get-BicepKey $entry.resourceNamespace $entry.groupId

    # Validate builtInPolicyId is set in catalog
    if ([string]::IsNullOrEmpty($entry.builtInPolicyId)) {
        $check3Failures += $entry
        Write-Fail "Catalog entry has policyType='builtin' but builtInPolicyId is null: $($entry.logicalService)"
        continue
    }

    # Validate entry exists in Bicep map
    if (-not $bicepMapEntries.ContainsKey($bicepKey)) {
        $check3Failures += $entry
        Write-Fail "MISSING from Bicep builtInPolicyMap: $($entry.logicalService)"
        Write-Fail "      Expected key : '$bicepKey'"
        Write-Fail "      Policy ID    : $($entry.builtInPolicyId)"
        continue
    }

    # Validate policy ID matches
    $actualId = $bicepMapEntries[$bicepKey]
    if ($actualId -ne $entry.builtInPolicyId) {
        $check3Failures += $entry
        Write-Fail "POLICY ID MISMATCH for: $($entry.logicalService)"
        Write-Fail "      Catalog   : $($entry.builtInPolicyId)"
        Write-Fail "      Bicep map : $actualId"
    } else {
        Write-Verbose "  ✅ $($entry.logicalService) → $actualId"
    }
}

if ($check3Failures.Count -eq 0) {
    Write-Pass "All $($builtinCatalogEntries.Count) builtin catalog entries match the Bicep builtInPolicyMap"
} else {
    Write-Fail "$($check3Failures.Count) builtin catalog entry issue(s) found"
}

# ── Check 4: Bicep map → Catalog ──────────────────────────────────────────────

Write-Header "Check 4: Bicep builtInPolicyMap → Catalog (no orphaned map entries)"

$check4Failures = @()
foreach ($bicepKey in $bicepMapEntries.Keys) {
    # bicepKey format: "Namespace/type-groupId"
    # Find any catalog entry whose builtin key matches
    $match = $catalog | Where-Object {
        $_.policyType -eq 'builtin' -and
        (Get-BicepKey $_.resourceNamespace $_.groupId) -eq $bicepKey
    }
    if ($match) {
        Write-Verbose "  ✅ $bicepKey"
    } else {
        $check4Failures += $bicepKey
        Write-Fail "ORPHANED Bicep map entry (not in catalog): '$bicepKey' → $($bicepMapEntries[$bicepKey])"
        Write-Warn "      → Either add a catalog entry for this service, or remove it from builtInPolicyMap"
    }
}

if ($check4Failures.Count -eq 0) {
    Write-Pass "All $($bicepMapEntries.Count) Bicep map entries have matching catalog entries"
} else {
    Write-Fail "$($check4Failures.Count) orphaned Bicep map entry/entries found"
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Header "Summary"

$builtinCount = ($catalog | Where-Object { $_.policyType -eq 'builtin' }).Count
$customCount  = ($catalog | Where-Object { $_.policyType -eq 'custom'  }).Count

$categoryReport = $catalog | Group-Object category | Sort-Object Name | ForEach-Object {
    $groupItems = @($_.Group)
    $b = @($groupItems | Where-Object { $_.policyType -eq 'builtin' }).Count
    $c = @($groupItems | Where-Object { $_.policyType -eq 'custom'  }).Count
    "    {0,-40} {1,3} total  ({2} builtin, {3} custom)" -f $_.Name, $_.Count, $b, $c
}

Write-Host ""
Write-Host "  Catalog totals:" -ForegroundColor White
Write-Host "    Total entries : $($catalog.Count)" -ForegroundColor White
Write-Host "    Built-in      : $builtinCount" -ForegroundColor Green
Write-Host "    Custom        : $customCount"  -ForegroundColor Yellow
Write-Host ""
Write-Host "  By category:" -ForegroundColor White
$categoryReport | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
Write-Host ""

$allChecksPassed = ($check1Failures.Count + $check2Failures.Count + $check3Failures.Count + $check4Failures.Count) -eq 0

if ($allChecksPassed) {
    Write-Host "  ALL CHECKS PASSED -- policy set is fully consistent with the catalog." -ForegroundColor Green
    exit 0
} else {
    $totalFails = $check1Failures.Count + $check2Failures.Count + $check3Failures.Count + $check4Failures.Count
    Write-Host "  $totalFails ISSUE(S) FOUND -- resolve before deploying." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Failures by check:" -ForegroundColor Red
    $c1color = if ($check1Failures.Count -gt 0) { 'Red' } else { 'Green' }
    $c2color = if ($check2Failures.Count -gt 0) { 'Red' } else { 'Green' }
    $c3color = if ($check3Failures.Count -gt 0) { 'Red' } else { 'Green' }
    $c4color = if ($check4Failures.Count -gt 0) { 'Red' } else { 'Green' }
    Write-Host "    Check 1 (catalog -> params)    : $($check1Failures.Count)" -ForegroundColor $c1color
    Write-Host "    Check 2 (params -> catalog)    : $($check2Failures.Count)" -ForegroundColor $c2color
    Write-Host "    Check 3 (builtin -> bicep map) : $($check3Failures.Count)" -ForegroundColor $c3color
    Write-Host "    Check 4 (bicep map -> catalog) : $($check4Failures.Count)" -ForegroundColor $c4color
    exit 1
}
