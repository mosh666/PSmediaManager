<#
.SYNOPSIS
    Sets the current logging context label.

.DESCRIPTION
    Updates the script-level context that will be prefixed to all subsequent log messages.
    Context is padded to 27 characters and wrapped in brackets.

.PARAMETER Context
    The context label to set (will be padded to 27 characters).

.EXAMPLE
    Set-LogContext -Context "Database"

.EXAMPLE
    Set-LogContext -Context "UserAuthentication"

.NOTES
    Function Name: Set-LogContext
    Requires: PowerShell 5.1 or higher
    This is typically called internally by Write-PSmmLog.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Set-LogContext {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Context
    )

    if ($PSCmdlet.ShouldProcess($Context, 'Set logging context')) {
        $script:Context.Context = '[' + $Context.PadRight(27) + ']'
        Write-Verbose "Log context set to: $($script:Context.Context)"
    }
}

#endregion ########## PUBLIC ##########
