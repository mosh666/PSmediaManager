#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-PSmmPluginsConfigMemberValue {
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
        Write-Verbose "Get-PSmmPluginsConfigMemberValue failed for '$Name'. $($_.Exception.Message)"
    }

    return $null
}

function Test-PSmmPluginsConfigMember {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $false
    }

    try {
        $tmp = $null
        return [ConfigMemberAccess]::TryGetMemberValue($Object, $Name, [ref]$tmp)
    }
    catch {
        Write-Verbose "Test-PSmmPluginsConfigMember failed for '$Name'. $($_.Exception.Message)"
        return $false
    }
}

function Set-PSmmPluginsConfigMemberValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Object) { return }

    if (-not $PSCmdlet.ShouldProcess("Config member '$Name'", 'Set value')) {
        return
    }

    try {
        $null = [ConfigMemberAccess]::SetMemberValue($Object, $Name, $Value)
    }
    catch {
        Write-Verbose "Set-PSmmPluginsConfigMemberValue failed for '$Name'. $($_.Exception.Message)"
    }
}

function Get-PSmmPluginsConfigNestedValue {
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

        $cur = Get-PSmmPluginsConfigMemberValue -Object $cur -Name $segment
    }

    return $cur
}
