#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-PSmmConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    try {
        $tmp = $null
        $valueRef = [ref]$tmp
        if ([ConfigMemberAccess]::TryGetMemberValue($Object, $Name, $valueRef)) {
            return $valueRef.Value
        }
    }
    catch {
        Write-Verbose "Get-PSmmConfigMemberValue: ConfigMemberAccess.TryGetMemberValue failed: $($_.Exception.Message)"
    }

    return $Default
}
