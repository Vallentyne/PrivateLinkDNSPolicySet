# Azure Private DNS Zone Automation Policy

This policy initiative automatically configures private DNS zones for Azure private endpoints across your management group, ensuring private connectivity is properly configured without manual intervention.

## Overview

When you create a private endpoint in Azure, you need to create DNS records in private DNS zones so resources can resolve the private IP address. This policy set automates that process by:

1. Detecting when private endpoints are created
2. Automatically creating DNS zone group configurations
3. Linking the private endpoint to the appropriate private DNS zones

## What It Does

- **Monitors**: All private endpoint resources created under the management group scope
- **Evaluates**: Whether each private endpoint has the required private DNS zone configurations
- **Remediates**: Automatically creates DNS zone groups with the correct DNS zones when missing

## Architecture

The policy set uses a hybrid approach with **61 total policy configurations**:

### Built-In Policies (25 configurations)
Uses Microsoft's native Azure Policy definitions for common services:
- Storage Accounts (blob, file, queue, table, dfs, web)
- Key Vault
- Container Registry
- Event Hub, Service Bus, Event Grid (topics + domains)
- Web Apps
- Azure Cache for Redis
- Cognitive Search
- Machine Learning workspaces
- Azure Synapse (SQL)
- Data Factory
- Storage Sync
- Compute Disk Access
- IoT Hub, IoT Central, Device Update
- SignalR
- App Configuration

### Custom Policies (36 configurations)
Deploys custom policy definitions for services without built-in policies or requiring special configuration:
- Azure Automation (Webhook, DSC and Hybrid Worker)
- Azure SQL Database
- Azure Synapse (SQL On-Demand, Dev, Private Link Hub)
- Storage secondary endpoints (blob, file, queue, table, dfs, web)
- Cosmos DB (SQL, MongoDB, MongoDB vCore, Cassandra, Gremlin, Table)
- Database services (PostgreSQL, MySQL Single + Flexible Server, MariaDB)
- AKS clusters (region-specific zones)
- Azure Batch (region-specific zones)
- Backup and Site Recovery (region-specific zones)
- **Azure AI Foundry** (special multi-zone configuration)
- Machine Learning (notebooks secondary zone)
- Redis Enterprise
- Healthcare APIs (FHIR)

## Azure AI Foundry (Multi-Zone Support)

Azure AI Foundry resources (`Microsoft.CognitiveServices/accounts` with kind `AIServices`) require special handling because a single private endpoint must create DNS records in **three** private DNS zones simultaneously:

1. `privatelink.cognitiveservices.azure.com`
2. `privatelink.openai.azure.com`
3. `privatelink.services.ai.azure.com`

The custom policy template includes logic to:
- Accept an array of DNS zones via `privateDnsZoneConfigs` parameter
- Create multiple DNS zone configurations within a single zone group
- Verify compliance by checking that **all** required zones exist (not just one)

This ensures Azure AI Foundry endpoints work correctly for all service scenarios (Cognitive Services, OpenAI, AI Services).

## Deployment

### Prerequisites

- Management group where policies will be deployed
- Subscription containing the central private DNS zones
- Resource group containing the private DNS zones
- Policy version number, used in custom definition and names, eg "v3", "v4", etc.

### Deploy the Policy Set

Be sure to edit the pubsecDNS.parameters.json file with the managementgroupID that should be used to contain the definition.  The deployment should also refer to this same management group ID, as below.

```powershell
# Deploy the policies and policy set
New-AzManagementGroupDeployment `
  -ManagementGroupId "alz" `
  -Location "canadacentral" `
  -TemplateFile ".\pubsecDNS.bicep" `
  -TemplateParameterFile ".\pubsecDNS.parameters.json" `
  -policyVersion "vX"
```

### Assign the Policy Set

```powershell
# Assign to management group with managed identity
New-AzPolicyAssignment `
  -Name "dns-private-endpoints" `
  -DisplayName "Central DNS for Private Endpoints" `
  -PolicySetDefinition (Get-AzPolicySetDefinition -Name 'custom-central-dns-private-endpoints' -ManagementGroupName "SLZ") `
  -Scope "/providers/Microsoft.Management/managementGroups/SLZ" `
  -PolicyParameterObject @{
    privateDNSZoneSubscriptionId="<subscription-id>"
    privateDNSZoneResourceGroupName="<resource-group-name>"
  } `
  -Location "canadacentral" `
  -IdentityType "SystemAssigned"
```

### Grant Permissions

The managed identity needs **Private DNS Zone Contributor** role on the resource group containing your private DNS zones:

```powershell
# Get the assignment's principal ID
$assignment = Get-AzPolicyAssignment -Name "dns-private-endpoints" -Scope "/providers/Microsoft.Management/managementGroups/SLZ"

# Grant permissions
New-AzRoleAssignment `
  -ObjectId $assignment.IdentityPrincipalId `
  -RoleDefinitionName "Private DNS Zone Contributor" `
  -Scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>"
```

## Configuration

### Parameters File Format

The `pubsecDNS.parameters.json` file defines which DNS zones to configure:

```json
{
  "privateLinkServiceNamespace": "Microsoft.CognitiveServices/accounts",
  "zone": "privatelink.cognitiveservices.azure.com",
  "filterLocationLike": "*",
  "groupId": "account",
  "privateDnsZoneConfigs": [
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.services.ai.azure.com"
  ]
}
```

**Fields:**
- `privateLinkServiceNamespace`: Azure resource provider and type
- `zone`: Primary DNS zone name (used for built-in policies)
- `filterLocationLike`: Region filter (`*` for all regions, or specific region like `canadacentral`)
- `groupId`: Private link group identifier
- `privateDnsZoneConfigs`: Array of DNS zones to configure (supports multiple zones for single endpoint)

## How It Works

### Custom Policy Template

The custom policy template (`templates/DNS-PrivateEndpoints/azurepolicy.json`) uses:

1. **Existence Condition**: Checks if private endpoint has DNS configurations for ALL required zones
   ```json
   "existenceCondition": {
     "count": {
       "value": "[parameters('privateDnsZoneConfigs')]",
       "where": { /* check each zone exists */ }
     },
     "equals": "[length(parameters('privateDnsZoneConfigs'))]"
   }
   ```

2. **Deployment Template**: Uses ARM template `copy` function to create multiple zone configs
   ```json
   "copy": [{
     "name": "privateDnsZoneConfigs",
     "count": "[length(parameters('privateDnsZoneConfigs'))]",
     "input": { /* create zone config */ }
   }]
   ```

### Policy Evaluation

- **Effect**: `DeployIfNotExists`
- **Trigger**: Private endpoint creation or update
- **Compliance Check**: Verifies all required DNS zone configurations exist
- **Remediation**: Creates missing DNS zone group with all required zones

## Maintenance

### Adding New Services

`service-catalog.json` is the **single source of truth** for all supported services. Follow this workflow:

1. Add an entry to `service-catalog.json` with `logicalService`, `resourceNamespace`, `groupId`, `dnsZone`, `filterLocationLike`, `policyType` (`builtin` or `custom`), and `builtInPolicyId` (if builtin).
2. Add the corresponding zone entry to `pubsecDNS.parameters.json`.
3. If `policyType` is `builtin`, add the policy GUID to `builtInPolicyMap` in `pubsecDNS.bicep`.
4. Run `Test-PolicyCoverage.ps1` — it validates all three files are in sync and fails with a clear error if anything is missing.

For multi-zone services (like AI Foundry):
- Include all zones in `privateDnsZoneConfigs` array in the parameters entry
- The custom policy template handles multiple zones automatically

### Validating Coverage

Run the validation script before every deployment:

```powershell
.\Test-PolicyCoverage.ps1
```

This performs four checks:
- **Check 1**: Every catalog entry exists in `pubsecDNS.parameters.json`
- **Check 2**: Every parameters zone is documented in the catalog (no undocumented additions)
- **Check 3**: Every `builtin` catalog entry is in `pubsecDNS.bicep`'s `builtInPolicyMap` with the correct policy GUID
- **Check 4**: No orphaned entries in the Bicep map

Exits with code `0` on full pass, `1` on any failure (safe to use in CI/CD pipelines).

### Updating Policies

To update existing policies, you must delete them first (Azure doesn't allow removing parameters from policies):

```powershell
# Delete policy set assignment
Remove-AzPolicyAssignment -Id "<assignment-id>"

# Delete policy set definition
Remove-AzPolicySetDefinition -Name 'custom-central-dns-private-endpoints' -ManagementGroupName "SLZ" -Force

# Delete custom policies
Get-AzPolicyDefinition -ManagementGroupName "SLZ" -Custom | 
  Where-Object { $_.Name -like 'dns-pe-*' } | 
  ForEach-Object { Remove-AzPolicyDefinition -Name $_.Name -ManagementGroupName "SLZ" -Force }

# Redeploy with new configuration
# (follow deployment steps above)
```

## Troubleshooting

### Policy Not Triggering

- Check policy assignment scope includes the subscription where private endpoints are created
- Verify managed identity has permissions on DNS zones resource group
- Check compliance state: `Get-AzPolicyState` for the specific resource

### Remediation Failures

- **Error: "MoreThanOnePrivateDnsZoneGroupPerPrivateEndpointNotAllowed"**
  - Private endpoint already has a zone group
  - Delete existing zone group first, or update it manually
  - Only one zone group allowed per private endpoint (but can contain multiple zone configs)

- **Error: "UnusedPolicyParameters"**
  - Parameter defined but not used in policy rule
  - Must delete and recreate policy definition (can't remove parameters from existing policies)

### Verification

Check DNS zone group configuration:

```powershell
# Using Azure CLI
az network private-endpoint dns-zone-group list `
  --endpoint-name "<endpoint-name>" `
  --resource-group "<resource-group>" `
  --output table
```

## Files

- **pubsecDNS.bicep**: Main Bicep template deploying policies and policy set
- **pubsecDNS.parameters.json**: Configuration of DNS zones (61 entries)
- **service-catalog.json**: Canonical service catalog — single source of truth for all 61 supported services with policy type, DNS zone, and built-in policy ID
- **Test-PolicyCoverage.ps1**: Validation script — cross-checks catalog, parameters, and Bicep map for consistency (CI-safe, exits non-zero on failure)
- **templates/DNS-PrivateEndpoints/azurepolicy.json**: Custom policy template supporting multi-zone configuration

## Output

After deployment, the template outputs:
- `builtInPolicyCount`: Number of policies using Microsoft built-in definitions (25)
- `customPolicyCount`: Number of custom policies deployed (36)
- `totalPolicyCount`: Total DNS zone configurations (61)

## License

Licensed under the MIT license.
