function Assert-SmokeTestSubscription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SubscriptionId
    )

    $allowedName = 'covallen3-dnstest'
    $output = & az account show --subscription $SubscriptionId --output json --only-show-errors 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to verify smoke subscription '$SubscriptionId': $($output.Trim())"
    }
    $account = $output | ConvertFrom-Json
    if ($account.name -cne $allowedName) {
        throw "Smoke tests may only use subscription '$allowedName'; requested subscription resolves to '$($account.name)' ($($account.id))."
    }
    if ($account.state -ne 'Enabled') {
        throw "Smoke subscription '$allowedName' is not enabled (state '$($account.state)')."
    }
    $parsedId = [guid]::Empty
    if (-not [guid]::TryParse([string] $account.id, [ref] $parsedId) -or $parsedId -eq [guid]::Empty) {
        throw "Smoke subscription '$allowedName' has an invalid subscription ID."
    }

    return $account.id
}
