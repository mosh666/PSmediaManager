#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-PSmmProjectsConfigMemberValue {
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
        Write-Verbose "[Get-PSmmProjects] GetMemberValue failed for '$Name': $_"
    }

    return $null
}

function Test-PSmmProjectsConfigMember {
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
        Write-Verbose "[Get-PSmmProjects] TestMember failed for '$Name': $_"
        return $false
    }
}

function Get-PSmmProjectsConfigNestedValue {
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

        $cur = Get-PSmmProjectsConfigMemberValue -Object $cur -Name $segment
    }

    return $cur
}

function Set-PSmmProjectsConfigMemberValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()][AllowNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter()][AllowNull()][object]$Value
    )

    if ($null -eq $Object) {
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Set config member value')) {
        return
    }

    try {
        [void][ConfigMemberAccess]::SetMemberValue($Object, $Name, $Value)
    }
    catch {
        Write-Verbose "[Get-PSmmProjects] SetMemberValue failed for '$Name': $_"
    }
}
