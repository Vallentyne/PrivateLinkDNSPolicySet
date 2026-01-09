# Test which policies are valid before building comprehensive set

$testPolicies = @(
    "b4a7f6c1-585e-4177-ad5b-c2c93f4bb991",  # Media Services Key
    "a48d9e19-b6a3-4726-a288-b0e1146c2381",  # Media Services Live
    "a9b426fe-8856-4945-8600-18c5dd1cca2a",  # Media Services Stream
    "6a4e6f44-f2af-4082-9702-033c9e88b9f8",  # Bot Service
    "9427df23-0f42-4e1e-bf99-a6133d841c4a",  # Virtual Desktop Hostpool
    "a222b93a-e6c2-4c01-817f-21e092455b2a",  # IoT DeviceUpdate
    "55c4db33-97b0-437b-8469-c4f4498f5df9",  # Arc HybridResourceProvider
    "d627d7c6-ded5-481a-8f2e-7e16b1e6faf6"   # IoT Central
)

foreach ($id in $testPolicies) {
    try {
        $pol = Get-AzPolicyDefinition -Id "/providers/Microsoft.Authorization/policyDefinitions/$id" -ErrorAction Stop
        Write-Host "✓ $id - $($pol.Properties.DisplayName)" -ForegroundColor Green
    } catch {
        Write-Host "✗ $id - NOT FOUND" -ForegroundColor Red
    }
}
