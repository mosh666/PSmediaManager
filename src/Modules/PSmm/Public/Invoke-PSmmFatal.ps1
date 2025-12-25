#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Invoke-PSmmFatal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [object]$Error,

        [Parameter()]
        [int]$ExitCode = 1,

        [Parameter()]
        [bool]$NonInteractive = $false,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FatalErrorUi
    )

    $hasInvokeFatal = $false
    try {
        $methodNames = @($FatalErrorUi.PSObject.Methods | ForEach-Object { $_.Name })
        if ($methodNames -contains 'InvokeFatal') {
            $hasInvokeFatal = $true
        }
    }
    catch {
        # fall through to Get-Member check
    }

    if (-not $hasInvokeFatal) {
        $invokeFatalMember = $FatalErrorUi | Get-Member -Name 'InvokeFatal' -ErrorAction SilentlyContinue
        if ($null -ne $invokeFatalMember) {
            $hasInvokeFatal = $true
        }
    }

    if (-not $hasInvokeFatal) {
        throw "FatalErrorUi must provide an InvokeFatal(...) method."
    }

    $FatalErrorUi.InvokeFatal($Context, $Message, $Error, $ExitCode, $NonInteractive)
}
