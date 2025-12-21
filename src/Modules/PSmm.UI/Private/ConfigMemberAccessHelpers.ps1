#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-PSmmUiConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    try {
        $tmp = $null
        if ([ConfigMemberAccess]::TryGetMemberValue($Object, $Name, [ref]$tmp)) {
            return $tmp
        }
    }
    catch {
        Write-Verbose "Get-PSmmUiConfigMemberValue failed for '$Name'. $($_.Exception.Message)"
    }

    return $null
}

function Get-PSmmUiConfigNestedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path
    )

    $cur = $Object
    foreach ($segment in $Path) {
        if ($null -eq $cur) {
            return $null
        }

        $cur = Get-PSmmUiConfigMemberValue -Object $cur -Name $segment
    }

    return $cur
}
