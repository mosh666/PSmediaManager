#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-PSmmConfigNestedValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Path,

        [Parameter()]
        [AllowNull()]
        [object]$Default = $null
    )

    if (-not (Get-Command -Name Get-PSmmConfigMemberValue -ErrorAction SilentlyContinue)) {
        $helperPath = Join-Path -Path $PSScriptRoot -ChildPath 'Get-PSmmConfigMemberValue.ps1'
        if (Test-Path -LiteralPath $helperPath) {
            . $helperPath
        }
    }

    if ($null -eq $Object) {
        return $Default
    }

    $current = $Object
    foreach ($segment in $Path) {
        $current = Get-PSmmConfigMemberValue -Object $current -Name $segment -Default $null
        if ($null -eq $current) {
            return $Default
        }
    }

    return $current
}
