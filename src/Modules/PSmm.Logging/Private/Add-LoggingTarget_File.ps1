<#
.SYNOPSIS
    Adds a file logging target to the PSLogs configuration.

.DESCRIPTION
    Internal helper function that configures and adds a file-based logging target
    using the PSLogs module. Uses configuration from the script-level $script:Logging variable.

.NOTES
    Function Name: Add-LoggingTarget_File
    Requires: PowerShell 5.1 or higher
    Scope: Private - Used internally by Write-PSmmLog
    External Dependency: PSLogs module
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Add-LoggingTarget_File {
    [CmdletBinding()]
    param()

    Add-LoggingTarget -Name File -Configuration @{
        Path = $script:Logging.Path
        PrintBody = $script:Logging.PrintBody
        Append = $script:Logging.Append
        Encoding = $script:Logging.Encoding
        Level = $script:Logging.DefaultLevel
        Format = $script:Logging.Format
        PrintException = $script:Logging.PrintException
        ShortLevel = $script:Logging.ShortLevel
    }
}

#endregion ########## PRIVATE ##########
