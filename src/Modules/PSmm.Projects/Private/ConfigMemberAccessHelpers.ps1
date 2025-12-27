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
        $cmaType = ('ConfigMemberAccess' -as [type])
        if ($cmaType) {
            if ($cmaType::TryGetMemberValue($Object, $Name, [ref]$tmp)) {
                return $tmp
            }
        }
        elseif ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($Name)) { return $Object[$Name] }
            if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        }
        else {
            $prop = $Object.PSObject.Properties[$Name]
            if ($prop) { return $prop.Value }
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
        $cmaType = ('ConfigMemberAccess' -as [type])
        if ($cmaType) {
            return $cmaType::TryGetMemberValue($Object, $Name, [ref]$tmp)
        }

        if ($Object -is [System.Collections.IDictionary]) {
            return ($Object.Contains($Name) -or $Object.ContainsKey($Name))
        }

        return ($null -ne $Object.PSObject.Properties[$Name])
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
        $cmaType = ('ConfigMemberAccess' -as [type])
        if ($cmaType) {
            [void]$cmaType::SetMemberValue($Object, $Name, $Value)
        }
        elseif ($Object -is [System.Collections.IDictionary]) {
            $Object[$Name] = $Value
        }
        else {
            $prop = $Object.PSObject.Properties[$Name]
            if ($prop) {
                $prop.Value = $Value
            }
            else {
                $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
            }
        }
    }
    catch {
        Write-Verbose "[Get-PSmmProjects] SetMemberValue failed for '$Name': $_"
    }
}
