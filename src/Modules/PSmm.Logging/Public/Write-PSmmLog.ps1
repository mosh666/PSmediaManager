<#
.SYNOPSIS
    Writes a log message to configured targets (file and/or console).

.DESCRIPTION
    Primary logging function that writes messages to file and/or console targets
    with optional context, body, and exception information.

.PARAMETER Level
    The logging level (e.g., INFO, DEBUG, WARNING, ERROR, CRITICAL).
    Built-in levels: NOTSET, SQL, DEBUG, VERBOSE, INFO, NOTICE, SUCCESS, WARNING, ERROR, CRITICAL, ALERT, EMERGENCY

.PARAMETER Message
    The primary log message.

.PARAMETER Body
    Optional detailed message body.

.PARAMETER ErrorRecord
    Optional ErrorRecord object for exception logging.

.PARAMETER Context
    Optional context label to prefix the message (max 27 characters, padded).

.PARAMETER Console
    Switch to enable console output.

.PARAMETER File
    Switch to enable file output.

.EXAMPLE
    Write-PSmmLog -Level INFO -Message "Application started" -Console -File

.EXAMPLE
    Write-PSmmLog -Level ERROR -Message "Operation failed" -Context "Database" -ErrorRecord $_ -File

.EXAMPLE
    Write-PSmmLog -Level DEBUG -Message "Processing item" -Body "Details: $details" -Console

.NOTES
    Function Name: Write-PSmmLog
    Requires: PowerShell 5.1 or higher
    External Dependency: PSLogs module
    Prerequisite: Initialize-Logging must be called first
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Write-PSmmLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [string]$Body,

        [Parameter()]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [switch]$Console,

        [Parameter()]
        [switch]$File
    )

    try {
        # Ensure logging context exists to avoid uninitialized variable warnings
        if ($null -eq $script:Context -or -not ($script:Context -is [hashtable])) {
            # Provide a safe structure with expected keys to avoid downstream property access errors
            $script:Context = @{ Context = $null; Path = $null }
        }

        # Clear existing targets
        if (Get-Command Get-LoggingTarget -ErrorAction SilentlyContinue) {
            (Get-LoggingTarget).Clear()
        }

        # Add requested targets
        if ($File -and (Get-Command Add-LoggingTarget_File -ErrorAction SilentlyContinue)) { 
            Add-LoggingTarget_File 
        }
        if ($Console -and (Get-Command Add-LoggingTarget_Console -ErrorAction SilentlyContinue)) { 
            Add-LoggingTarget_Console 
        }

        # Set context if provided
        if (-not [string]::IsNullOrWhiteSpace($Context)) { 
            Set-LogContext -Context $Context 
        }

        # Build final log message with context
        $contextPrefix = if ($script:Context.Context) { $script:Context.Context } else { '' }
        $logMessage = "$contextPrefix $Message"

        # Write the log entry (PSLogs is a required dependency)
        if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
            throw 'PSLogs dependency is missing. Ensure PSmm.Logging is initialized and PSLogs is available.'
        }
        Write-Log -Level $Level -Message $logMessage -Body $Body -ExceptionInfo $ErrorRecord

        # Ensure log is flushed
        if (Get-Command Wait-Logging -ErrorAction SilentlyContinue) {
            Wait-Logging
            Wait-Logging  # Double-check to ensure file handles are released
        }
    }
    catch {
        # Logging failure should not spam tests with warnings; emit as verbose so callers can inspect when needed
        Write-Verbose "Failed to write log message: $_"
    }
}

#endregion ########## PUBLIC ##########
