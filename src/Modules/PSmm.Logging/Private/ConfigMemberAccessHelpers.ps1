#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-PSmmLoggingConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Object,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [Parameter()][AllowNull()]$Default = $null
    )

    try {
        $value = $Default
        $ok = [ConfigMemberAccess]::TryGetMemberValue($Object, $Name, [ref]$value)
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
        return [ConfigMemberAccess]::TryGetMemberValue($Object, $Name, [ref]$tmp)
    }
    catch {
        Write-Verbose "Test-PSmmLoggingConfigMember: ConfigMemberAccess.TryGetMemberValue failed: $($_.Exception.Message)"
        return $false
    }
}
