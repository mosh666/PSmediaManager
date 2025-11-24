<#
.SYNOPSIS
    Adds a console logging target to the PSLogs configuration.

.DESCRIPTION
    Internal helper function that configures and adds a console-based logging target
    using the PSLogs module. Uses configuration from the script-level $script:Logging variable.

.NOTES
    Function Name: Add-LoggingTarget_Console
    Requires: PowerShell 5.1 or higher
    Scope: Private - Used internally by Write-PSmmLog
    External Dependency: PSLogs module
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Add-LoggingTarget_Console {
    [CmdletBinding()]
    param()

    Add-LoggingTarget -Name Console -Configuration @{
        Level = $script:Logging.DefaultLevel
        Format = $script:Logging.Format
        PrintException = $script:Logging.PrintException
        OnlyColorizeLevel = $script:Logging.OnlyColorizeLevel
        ShortLevel = $script:Logging.ShortLevel
    }
}

#endregion ########## PRIVATE ##########
