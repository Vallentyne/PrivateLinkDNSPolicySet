# Check current policy set status
$policySet = Get-AzPolicySetDefinition -Name "Deploy-Private-DNS-Zones" -ManagementGroupName "DND"

Write-Host "`n=== Current Policy Set Status ===" -ForegroundColor Green
Write-Host "Name: $($policySet.Name)"
Write-Host "Version: $($policySet.Properties.Metadata.Version)"
Write-Host "Policy Count: $($policySet.Properties.PolicyDefinitions.Count)"
Write-Host "Description: $($policySet.Properties.Description)"
Write-Host "`n=== Policy List ===" -ForegroundColor Cyan
$policySet.Properties.PolicyDefinitions | ForEach-Object {
    Write-Host "  - $($_.policyDefinitionReferenceId)"
}
