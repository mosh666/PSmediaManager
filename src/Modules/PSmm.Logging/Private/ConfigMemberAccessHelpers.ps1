#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-PSmmLoggingType {
    [CmdletBinding()]
    [OutputType([type])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TypeName
    )

    return ($TypeName -as [type])
}

function Get-PSmmLoggingExceptionInstance {
    [CmdletBinding()]
    [OutputType([System.Exception])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TypeName,

        [Parameter()]
        [AllowNull()]
        [object[]]$ArgumentList,

        [Parameter()]
        [AllowNull()]
        [System.Exception]$FallbackInnerException
    )

    $type = Get-PSmmLoggingType -TypeName $TypeName
    if (-not $type) {
        return $null
    }

    if ($null -eq $ArgumentList) { $ArgumentList = @() }
    try {
        $ex = [System.Activator]::CreateInstance($type, $ArgumentList)
        if ($ex -is [System.Exception]) { return $ex }
        return $null
    }
    catch {
        if ($null -ne $FallbackInnerException) {
            return [System.Exception]::new("Failed to construct exception [$TypeName]", $FallbackInnerException)
        }
        return $null
    }
}

function Test-PSmmLoggingTryGetMemberValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter(Mandatory)][ref]$Value
    )

    if ($null -eq $Object) { return $false }

    # 1) Use PSmm's ConfigMemberAccess when available (typed config objects)
    $cmaType = Get-PSmmLoggingType -TypeName 'ConfigMemberAccess'
    if ($cmaType) {
        try {
            return [bool]$cmaType::TryGetMemberValue($Object, $Name, $Value)
        }
        catch {
            Write-Verbose "Test-PSmmLoggingTryGetMemberValue: ConfigMemberAccess.TryGetMemberValue failed: $($_.Exception.Message)"
        }
    }

    # 2) IDictionary/hashtable support
    if ($Object -is [System.Collections.IDictionary]) {
        try {
            if ($Object.ContainsKey($Name)) {
                $Value.Value = $Object[$Name]
                return $true
            }
        }
        catch {
            Write-Verbose "Test-PSmmLoggingTryGetMemberValue: IDictionary.ContainsKey failed: $($_.Exception.Message)"
        }

        try {
            if ($Object.Contains($Name)) {
                $Value.Value = $Object[$Name]
                return $true
            }
        }
        catch {
            Write-Verbose "Test-PSmmLoggingTryGetMemberValue: IDictionary.Contains failed: $($_.Exception.Message)"
        }

        try {
            foreach ($k in $Object.Keys) {
                if ($k -eq $Name) {
                    $Value.Value = $Object[$k]
                    return $true
                }
            }
        }
        catch {
            Write-Verbose "Test-PSmmLoggingTryGetMemberValue: IDictionary.Keys iteration failed: $($_.Exception.Message)"
        }

        return $false
    }

    # 3) Generic object property access
    try {
        $prop = $Object.PSObject.Properties[$Name]
        if ($null -ne $prop) {
            $Value.Value = $prop.Value
            return $true
        }
    }
    catch {
        Write-Verbose "Test-PSmmLoggingTryGetMemberValue: PSObject property lookup failed: $($_.Exception.Message)"
    }

    return $false
}

function Get-PSmmLoggingConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter()][AllowNull()]$Default = $null
    )

    try {
        $value = $Default
        $ok = Test-PSmmLoggingTryGetMemberValue -Object $Object -Name $Name -Value ([ref]$value)
        if ($ok) {
            return $value
        }

        return $Default
    }
    catch {
        Write-Verbose "Get-PSmmLoggingConfigMemberValue: ConfigMemberAccess.TryGetMemberValue failed: $($_.Exception.Message)"
        return $Default
    }
}

function Test-PSmmLoggingConfigMember {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name
    )

    if ($null -eq $Object) {
        return $false
    }

    try {
        $tmp = $null
        return Test-PSmmLoggingTryGetMemberValue -Object $Object -Name $Name -Value ([ref]$tmp)
    }
    catch {
        Write-Verbose "Test-PSmmLoggingConfigMember: ConfigMemberAccess.TryGetMemberValue failed: $($_.Exception.Message)"
        return $false
    }
}
