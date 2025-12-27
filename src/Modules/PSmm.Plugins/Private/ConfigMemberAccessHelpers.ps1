#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-PSmmPluginsType {
    [CmdletBinding()]
    [OutputType([type])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TypeName
    )

    return ($TypeName -as [type])
}

function Test-PSmmPluginsTryGetMemberValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][ref]$Value
    )

    if ($null -eq $Object) {
        return $false
    }

    # 1) Use PSmm's ConfigMemberAccess when available
    $cmaType = Get-PSmmPluginsType -TypeName 'ConfigMemberAccess'
    if ($cmaType) {
        try {
            return [bool]$cmaType::TryGetMemberValue($Object, $Name, $Value)
        }
        catch {
            Write-Verbose "Test-PSmmPluginsTryGetMemberValue: ConfigMemberAccess.TryGetMemberValue failed: $($_.Exception.Message)"
        }
    }

    # 2) IDictionary/hashtable access
    if ($Object -is [System.Collections.IDictionary]) {
        try {
            if ($Object.ContainsKey($Name)) {
                $Value.Value = $Object[$Name]
                return $true
            }
        }
        catch {
            Write-Verbose "Test-PSmmPluginsTryGetMemberValue: IDictionary.ContainsKey failed: $($_.Exception.Message)"
        }

        try {
            if ($Object.Contains($Name)) {
                $Value.Value = $Object[$Name]
                return $true
            }
        }
        catch {
            Write-Verbose "Test-PSmmPluginsTryGetMemberValue: IDictionary.Contains failed: $($_.Exception.Message)"
        }

        return $false
    }

    # 3) Generic PSObject property access
    try {
        $prop = $Object.PSObject.Properties[$Name]
        if ($null -ne $prop) {
            $Value.Value = $prop.Value
            return $true
        }
    }
    catch {
        Write-Verbose "Test-PSmmPluginsTryGetMemberValue: PSObject property lookup failed: $($_.Exception.Message)"
    }

    return $false
}

function Set-PSmmPluginsMemberValueFallback {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)][ValidateNotNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter()][AllowNull()][object]$Value
    )

    if (-not $PSCmdlet.ShouldProcess('Config object', "Set member '$Name'")) {
        return
    }

    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop) {
        $prop.Value = $Value
        return
    }

    $null = Add-Member -InputObject $Object -MemberType NoteProperty -Name $Name -Value $Value -Force
}

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
        if (Test-PSmmPluginsTryGetMemberValue -Object $Object -Name $Name -Value ([ref]$tmp)) {
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
        return Test-PSmmPluginsTryGetMemberValue -Object $Object -Name $Name -Value ([ref]$tmp)
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
        $cmaType = Get-PSmmPluginsType -TypeName 'ConfigMemberAccess'
        if ($cmaType) {
            $null = $cmaType::SetMemberValue($Object, $Name, $Value)
            return
        }

        Set-PSmmPluginsMemberValueFallback -Object $Object -Name $Name -Value $Value
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
