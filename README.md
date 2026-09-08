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

The policy set uses a hybrid approach with **58 total policy references** covering 59 DNS zone configurations:

### Built-In Policies (25 configurations)
Uses Microsoft's native Azure Policy definitions for common services:
- Storage Accounts (blob, file, queue, table, dfs, web)
- Key Vault
- Container Registry
- Event Hub, Service Bus, Event Grid (topics + domains)
- Web Apps
- Azure Cache for Redis
- Cognitive Search
- Machine Learning workspaces (primary and notebooks zones)
- Azure Synapse (SQL)
- Data Factory
- Storage Sync
- Compute Disk Access
- IoT Hub, IoT Central, Device Update
- SignalR
- Azure Batch (batchAccount)

### Custom Policies (33 references)
Deploys custom policy definitions for services without built-in policies or requiring special configuration:
- Azure Automation (Webhook, DSC and Hybrid Worker)
- Azure SQL Database
- Azure Synapse (SQL On-Demand, Dev, Private Link Hub)
- Storage secondary endpoints (blob, file, queue, table, dfs, web)
- Cosmos DB (SQL, MongoDB, MongoDB vCore, Cassandra, Gremlin, Table)
- Database services (PostgreSQL, MySQL Single + Flexible Server, MariaDB)
- AKS clusters (region-specific zones)
- Azure Batch (nodeManagement)
- Backup and Site Recovery (region-specific zones)
- **Azure AI Foundry** (special multi-zone configuration)
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

## Azure Machine Learning (Built-In Multi-Zone Support)

Azure Machine Learning workspace private endpoints require both:

1. `privatelink.api.azureml.ms`
2. `privatelink.notebooks.azure.net`

Both catalog entries map to the Microsoft built-in policy `ee40564d-486e-4f68-a5ca-7a621edae0fb`. The initiative emits this built-in exactly once, passing the API zone as `privateDnsZoneId` and the notebooks zone as `secondPrivateDnsZoneId`. This creates one `deployedByPolicy` DNS zone group containing both zones and avoids competing deployments to the same private endpoint child resource.

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

### Assign the Policy Set (Recommended: Azure Portal)

Assign the initiative through **Azure Policy > Assignments** in the Azure portal. The portal creates the managed identity and automatically grants the roles declared by the initiative's policy definitions at the assignment scope.

1. Select the `Custom - Central DNS for Private Endpoints <version>` initiative.
2. Set the assignment scope to the target management group.
3. Provide the central Private DNS zone subscription and resource group parameters.
4. On the **Remediation** tab, select **System assigned managed identity** and choose an identity location.
5. Create the assignment, then verify the identity's role assignments as described below.

The portal is recommended because assignments created with PowerShell, the Azure CLI, an SDK, or infrastructure as code do not automatically grant the roles listed in `roleDefinitionIds`.

#### PowerShell Alternative

If automation is required, create the assignment with a managed identity and grant both required roles manually:

```powershell
# Assign to management group with managed identity
$assignment = New-AzPolicyAssignment `
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

### Verify Managed Identity Permissions

The assignment's managed identity requires permissions at two scopes:

- **Network Contributor** at the assignment scope, or on every subscription/resource group containing private endpoints. This allows the policy to create `Microsoft.Network/privateEndpoints/privateDnsZoneGroups` resources. The portal normally grants this declared role automatically.
- **Private DNS Zone Contributor** on the resource group containing the central Private DNS zones. Verify or add this role explicitly, especially when the DNS resource group is outside the policy assignment scope.

For a PowerShell-created assignment, grant both roles after the managed identity has replicated in Microsoft Entra ID:

```powershell
$principalId = $assignment.Identity.PrincipalId

# Allow creation of DNS zone groups on private endpoints
New-AzRoleAssignment `
  -ObjectId $principalId `
  -RoleDefinitionName "Network Contributor" `
  -Scope "/providers/Microsoft.Management/managementGroups/SLZ"

# Allow the zone groups to reference the central Private DNS zones
New-AzRoleAssignment `
  -ObjectId $principalId `
  -RoleDefinitionName "Private DNS Zone Contributor" `
  -Scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>"
```

Existing non-compliant private endpoints require remediation tasks after these permissions are in place. For a management-group assignment, wait for the first compliance evaluation to record the resource as non-compliant, then create remediation at the resource-group or subscription scope using the existing compliance state. Verify that older versions of the initiative are not also assigned at an overlapping scope.

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

This performs five checks:
- **Check 1**: Every catalog entry exists in `pubsecDNS.parameters.json`
- **Check 2**: Every parameters zone is documented in the catalog (no undocumented additions)
- **Check 3**: Every `builtin` catalog entry is in `pubsecDNS.bicep`'s `builtInPolicyMap` with the correct policy GUID
- **Check 4**: No orphaned entries in the Bicep map
- **Check 5**: Every parameter follows its catalog route, and multi-zone built-ins emit exactly one policy reference

Exits with code `0` on full pass, `1` on any failure (safe to use in CI/CD pipelines).

### Automated Azure Smoke Test

The smoke harness deploys five representative Private Link services into a disposable resource group:

- Storage Blob and Key Vault validate Microsoft built-in policy references.
- App Configuration validates the standard custom policy path.
- AI Services validates the custom three-zone policy path.
- Azure Machine Learning validates the built-in two-zone policy path.

Private endpoints are deployed without DNS zone groups. The harness assigns the initiative, starts targeted remediation with fresh resource discovery, and verifies that:

1. Each private endpoint has exactly one DNS zone group.
2. The zone group contains exactly the expected private DNS zone IDs.
3. Every expected zone contains an A record for the private endpoint NIC IP.
4. A final policy scan has no non-compliant states for the smoke assignment.

Run the complete lifecycle locally with an existing Azure CLI login:

```powershell
./tests/smoke/Invoke-SmokeTest.ps1 `
  -Action All `
  -SubscriptionId '<test-subscription-id>' `
  -ManagementGroupId '<test-management-group-id>'
```

`All` removes the environment in a `finally` block. To retain a failed environment temporarily, add `-KeepOnFailure`; it remains tagged with a six-hour expiration. Remove a retained run using the same `RunId` printed by the original command:

```powershell
./tests/smoke/Invoke-SmokeTest.ps1 `
  -Action Destroy `
  -SubscriptionId '<test-subscription-id>' `
  -ManagementGroupId '<test-management-group-id>' `
  -RunId '<original-run-id>'
```

Use `-Action Validate` for the offline catalog and Bicep checks. The `Deploy`, `Test`, and `Destroy` actions support troubleshooting an individual run.

#### Dedicated Test Subscription

Place a dedicated test subscription in a child management group used only for this harness. The subscription must be a descendant of the management group where the temporary initiative definitions are deployed.

For GitHub Actions, configure an Entra application or user-assigned managed identity with a federated credential for the `dns-policy-smoke` GitHub environment. Grant its service principal:

- **Contributor** on the dedicated test management group.
- **Role Based Access Control Administrator** on the dedicated test subscription, allowing it to grant the policy assignment identity its declared remediation roles.

Configure these GitHub environment variables on `dns-policy-smoke`:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_POLICY_MANAGEMENT_GROUP_ID`

The workflows provide three automation levels:

- `policy-validation.yml` runs offline validation on pull requests and pushes to `main`.
- `policy-smoke.yml` runs the live test manually or every Monday and serializes access to the test subscription.
- `cleanup-expired.yml` runs daily to remove expired resource groups and orphaned `smoke-*` policy definitions.

AI Services availability and quota vary by region. Change the workflow's `location` input if `AIServices` is unavailable in the default region.

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

- **Error: `LinkedAuthorizationFailed` for `Microsoft.Network/privateDnsZones/join/action`**
  - Confirm the caller object ID belongs to the intended policy assignment's managed identity
  - Grant that identity **Private DNS Zone Contributor** on the central DNS zone resource group
  - Check for older policy assignments at overlapping scopes; an old assignment can still launch competing deployments with its own identity and parameters

- **Remediation remains `Evaluating` with zero deployments**
  - Confirm Policy Insights has a fresh `NonCompliant` state for the assignment and definition reference
  - Create remediation at the resource-group or subscription scope after that state exists
  - Use the existing non-compliant state instead of starting resource-level reevaluation before the compliance snapshot is available

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
- **pubsecDNS.parameters.json**: Configuration of DNS zones (59 entries)
- **service-catalog.json**: Canonical service catalog — single source of truth for all 59 DNS zone configurations with policy type, DNS zone, and built-in policy ID
- **Test-PolicyCoverage.ps1**: Validation script — cross-checks catalog, parameters, and Bicep map for consistency (CI-safe, exits non-zero on failure)
- **templates/DNS-PrivateEndpoints/azurepolicy.json**: Custom policy template supporting multi-zone configuration
- **tests/smoke**: Disposable Azure smoke-test Bicep, orchestration, assertions, and cleanup scripts
- **.github/workflows**: Offline validation, live smoke testing, and expiration cleanup workflows

## Output

After deployment, the template outputs:
- `builtInPolicyCount`: Number of policies using Microsoft built-in definitions (25)
- `customPolicyCount`: Number of custom policies deployed (33)
- `totalPolicyCount`: Total DNS zone configurations (59)

## License

Licensed under the MIT license.
