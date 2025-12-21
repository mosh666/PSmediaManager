#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-PSmmAppConfigurationSafe {
    [CmdletBinding()]
    [OutputType([object])]
    param()

    if (-not (Get-Command -Name Get-AppConfiguration -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        return Get-AppConfiguration
    }
    catch {
        Write-Verbose "Get-PSmmAppConfigurationSafe: Get-AppConfiguration failed: $($_.Exception.Message)"
        return $null
    }
}
