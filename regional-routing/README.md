# Regional Private DNS Routing Prototype

This prototype uses the existing `pubsecDNS.parameters.json` service inventory but creates custom policy definitions for every emitted service route. It leaves the baseline initiative unchanged.

## Routing behavior

The policy selects the Private DNS zone subscription and resource group from an initiative parameter keyed by the evaluated private endpoint's lowercase Azure location:

```json
{
  "regionalPrivateDnsZoneTargets": {
    "value": {
      "canadacentral": {
        "subscriptionId": "00000000-0000-0000-0000-000000000000",
        "resourceGroupName": "rg-private-dns-canadacentral"
      },
      "canadaeast": {
        "subscriptionId": "11111111-1111-1111-1111-111111111111",
        "resourceGroupName": "rg-private-dns-canadaeast"
      }
    }
  }
}
```

Only locations present in the object are in scope. Existing service-specific location filters remain active, so the Canada Central AKS definition cannot act on a Canada East endpoint.

## Important limitation

The routing signal is `Microsoft.Network/privateEndpoints.location`, which is normally the virtual network's region. Azure Policy can inspect the target resource ID in `privateLinkServiceConnections`, but it cannot dereference that ID to read the remote resource's location during evaluation.

If routing must follow the target service's location rather than the private endpoint's location, use an explicit tag or another property copied onto the private endpoint and route on that value instead.

## Why built-in policies are not used

The baseline built-ins accept one DNS zone resource ID per initiative reference and do not expose this location-to-target map. This prototype therefore uses the custom definition for all services. Multi-zone services still emit one definition and one zone group.

## Deploy and assign

Deploy the definitions and initiative:

```powershell
New-AzManagementGroupDeployment `
  -ManagementGroupId 'alz' `
  -Location 'canadacentral' `
  -TemplateFile './pubsecDNS.regional.bicep' `
  -TemplateParameterFile './pubsecDNS.regional.bicepparam'
```

At assignment time, provide `regionalPrivateDnsZoneTargets` in the shape above. Grant the assignment identity Network Contributor where private endpoints are deployed and Private DNS Zone Contributor on every target DNS resource group.

## Validation criteria

1. Deploy the same service type with private endpoints in two mapped regions.
2. Confirm each endpoint gets exactly one `default` private DNS zone group.
3. Confirm each zone group references the DNS resource group mapped to its endpoint location.
4. Confirm an endpoint in an unmapped region is not applicable.
5. Confirm AI Foundry and Azure Machine Learning retain all required zone configurations in one zone group.

## Reproducible smoke test

The smoke contract is checked in at `tests/smoke-matrix.json`. It deliberately covers six service routes in two private endpoint regions (12 endpoints total): Storage Blob, Key Vault, App Configuration, AI Services, Batch account, and Batch node management. AI Services verifies the multi-zone behavior in a single DNS zone group.

Each run:

1. Requires a clean, unique run ID and refuses to reconcile an existing environment.
2. Creates one private endpoint per route in Canada Central and Canada East.
3. Uses globally unique private-link connection names while preserving each service-defined group ID.
4. Resolves exactly one initiative reference for every matrix route and remediates routes serially to avoid competing service operations.
5. Verifies endpoint provisioning state and location, one exact regional DNS zone group, and an A record containing the endpoint NIC address.
6. Removes successful environments. Failed environments are removed unless `-KeepOnFailure` is set; retained environments expire after six hours.

Run the full smoke test:

```powershell
./regional-routing/tests/Invoke-RegionalRoutingTest.ps1 `
  -Action All `
  -SubscriptionId '<subscription-id>' `
  -ManagementGroupId '<management-group-id>' `
  -PrimaryLocation canadacentral `
  -SecondaryLocation canadaeast `
  -RunId "local$(Get-Date -Format yyyyMMddHHmmss)"
```

Run local static validation without Azure credentials:

```powershell
./regional-routing/tests/Invoke-RegionalRoutingTest.ps1 -Action Validate
```

The `Regional policy smoke test` workflow runs this command weekly and on demand. Its run ID is derived from the GitHub run ID and attempt, preventing cross-run resource reuse. Regional validation and expired-resource cleanup run from separate workflows and do not invoke the standard smoke harness.