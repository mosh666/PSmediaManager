<#
.SYNOPSIS
    Creates a customized filename with dynamic placeholders.

.DESCRIPTION
    Generates a filename string by replacing placeholders with actual values like
    date, time, username, computername, etc. This function is useful for creating
    dynamic filenames for logs, exports, or timestamped files.

.PARAMETER Template
    A template string containing placeholders. Supported placeholders:
    - %year%         : 4-digit year (e.g., 2025)
    - %month%        : 2-digit month (01-12)
    - %day%          : 2-digit day (01-31)
    - %hour%         : 2-digit hour in 24-hour format (00-23)
    - %minute%       : 2-digit minute (00-59)
    - %second%       : 2-digit second (00-59)
    - %username      : Current username from $env:USERNAME
    - %computername  : Computer name from $env:COMPUTERNAME

.EXAMPLE
    New-CustomFileName -Template "%year%%month%%day%-MyApp-%username@%computername.log"

    Returns: 20251026-MyApp-mosh@AVIATOR.log

.EXAMPLE
    New-CustomFileName -Template "%year%-%month%-%day%_%hour%%minute%%second%.txt"

    Returns: 2025-10-26_143022.txt

.EXAMPLE
    New-CustomFileName -Template "Backup_%year%%month%%day%_%hour%%minute%.zip"

    Returns: Backup_20251026_1430.zip

.INPUTS
    String - Template string with placeholders

.OUTPUTS
    String - Filename with placeholders replaced by actual values

.NOTES
    Function Name: New-CustomFileName
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher

    All time values use leading zeros for consistency (e.g., "01" instead of "1").
    The function uses the current system time at the moment of execution.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function New-CustomFileName {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This function generates and returns a filename string without modifying system state')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$Template
    )

    begin {
        Write-Verbose "Creating custom filename from template: $Template"
    }

    process {
        try {
            $now = Get-Date

            # Resolve username/computername cross-platform
            $userName = $env:USERNAME
            if ([string]::IsNullOrWhiteSpace($userName)) { $userName = $env:USER }
            if ([string]::IsNullOrWhiteSpace($userName)) {
                try { $userName = (& whoami) } catch { $userName = $null }
            }

            $computerName = $env:COMPUTERNAME
            if ([string]::IsNullOrWhiteSpace($computerName)) { $computerName = $env:HOSTNAME }
            if ([string]::IsNullOrWhiteSpace($computerName)) {
                try { $computerName = [System.Net.Dns]::GetHostName() } catch { $computerName = $null }
            }

            # Create replacement hashtable with all supported placeholders
            $replacements = @{
                '%year%' = $now.ToString('yyyy')
                '%month%' = $now.ToString('MM')
                '%day%' = $now.ToString('dd')
                '%hour%' = $now.ToString('HH')
                '%minute%' = $now.ToString('mm')
                '%second%' = $now.ToString('ss')
                '%username%' = $userName
                '%computername%' = $computerName
            }

            # Replace all placeholders in the template
            $result = $Template
            foreach ($placeholder in $replacements.Keys) {
                $value = $replacements[$placeholder]
                if ($null -eq $value -or [string]::IsNullOrWhiteSpace($value)) {
                    Write-Warning "Placeholder '$placeholder' has no value, leaving unchanged"
                    continue
                }
                $result = $result.Replace($placeholder, $value)
            }

            Write-Verbose "Generated filename: $result"
            return $result
        }
        catch {
            $ErrorMessage = "Failed to create custom filename from template '$Template': $_"
            Write-Error $ErrorMessage
            throw
        }
    }
}

#endregion ########## PUBLIC ##########
