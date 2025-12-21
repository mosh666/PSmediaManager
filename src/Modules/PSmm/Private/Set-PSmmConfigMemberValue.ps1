#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Set-PSmmConfigMemberValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        $Value
    )

    if ($null -eq $Object) {
        return
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($PSCmdlet.ShouldProcess("Dictionary key '$Name'", 'Set value')) {
            if (-not [ConfigMemberAccess]::SetMemberValue($Object, $Name, $Value)) {
                Write-Verbose "Set-PSmmConfigMemberValue: ConfigMemberAccess.SetMemberValue failed for dictionary key '$Name'"
            }
        }
        return
    }

    $exists = $false
    try {
        $tmp = $null
        $exists = [ConfigMemberAccess]::TryGetMemberValue($Object, $Name, [ref]$tmp)
    }
    catch {
        $exists = $false
    }

    $actionTarget = if ($exists) { "Property '$Name'" } else { "NoteProperty '$Name'" }
    if ($PSCmdlet.ShouldProcess($actionTarget, 'Set value')) {
        if (-not [ConfigMemberAccess]::SetMemberValue($Object, $Name, $Value)) {
            Write-Verbose "Set-PSmmConfigMemberValue: ConfigMemberAccess.SetMemberValue failed for member '$Name'"
        }
    }
}
