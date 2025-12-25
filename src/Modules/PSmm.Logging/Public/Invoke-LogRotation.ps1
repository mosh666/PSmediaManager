<#
.SYNOPSIS
    Rotates log files based on age and/or quantity limits.

.DESCRIPTION
    Manages log file retention by deleting old log files based on age (days) or
    keeping only a specified number of most recent files. Supports WhatIf for testing.

.PARAMETER Path
    The directory path containing log files.

.PARAMETER Pattern
    File pattern to match log files (default: *.log).

.PARAMETER MaxAgeDays
    Maximum age in days. Files older than this will be deleted.

.PARAMETER MaxFiles
    Maximum number of log files to keep. Oldest files beyond this limit will be deleted.

.PARAMETER FileSystem
    A FileSystem service instance (service-first DI). This is required; no filesystem shim/fallback is used.

.PARAMETER WhatIf
    Shows what would be deleted without actually deleting files.

.EXAMPLE
    Invoke-LogRotation -Path "C:\Logs" -MaxAgeDays 30 -FileSystem $fileSystemService

.EXAMPLE
    Invoke-LogRotation -Path "C:\Logs" -MaxFiles 10 -FileSystem $fileSystemService -WhatIf

.EXAMPLE
    Invoke-LogRotation -Path "C:\Logs" -MaxAgeDays 30 -MaxFiles 20 -FileSystem $fileSystemService

.NOTES
    Function Name: Invoke-LogRotation
    Requires: PowerShell 5.1 or higher
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Invoke-LogRotation {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [string]$Pattern = '*.log',

        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]$MaxAgeDays,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$MaxFiles,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$FileSystem
    )

    try {
        $requiredFsMethods = @('TestPath', 'GetChildItem', 'RemoveItem')
        foreach ($methodName in $requiredFsMethods) {
            $hasMethod = $null -ne ($FileSystem | Get-Member -Name $methodName -MemberType Method -ErrorAction SilentlyContinue)
            if (-not $hasMethod) {
                throw "FileSystem is missing required method '$methodName'. Invoke-LogRotation requires an injected FileSystem service implementing: $($requiredFsMethods -join ', ')."
            }
        }

        # Validate path using FileSystem service
        if (-not $FileSystem.TestPath($Path)) {
            throw "Path not found: $Path"
        }

        Write-Verbose "Starting log rotation in: $Path"
        Write-Verbose "Pattern: $Pattern, MaxAgeDays: $MaxAgeDays, MaxFiles: $MaxFiles"

        # Get all log files sorted by last write time (newest first)
        $files = @($FileSystem.GetChildItem($Path, $Pattern, 'File') |
                Sort-Object LastWriteTime -Descending)

        if ($files.Count -eq 0) {
            Write-Verbose "No log files found matching pattern '$Pattern' in $Path"
            return
        }

        Write-Verbose "Found $($files.Count) log file(s)"

        $now = Get-Date
        $toDelete = @()

        # Rule 1: Age-based deletion
        if ($MaxAgeDays -gt 0) {
            $cutoff = $now.AddDays(-$MaxAgeDays)
            $ageBasedFiles = @($files | Where-Object { $_.LastWriteTime -lt $cutoff })
            if ($ageBasedFiles.Count -gt 0) {
                Write-Verbose "Found $($ageBasedFiles.Count) file(s) older than $MaxAgeDays days"
                $toDelete += $ageBasedFiles
            }
        }

        # Rule 2: Quantity-based deletion (keep only MaxFiles newest)
        if ($MaxFiles -gt 0 -and $files.Count -gt $MaxFiles) {
            $excessFiles = @($files[$MaxFiles..($files.Count - 1)])
            Write-Verbose "Found $($excessFiles.Count) file(s) exceeding MaxFiles limit of $MaxFiles"
            $toDelete += $excessFiles
        }

        # Deduplicate the deletion list
        $toDelete = @($toDelete | Sort-Object FullName -Unique)

        if ($toDelete.Count -eq 0) {
            Write-Verbose 'No files meet deletion criteria'
            return
        }

        Write-Verbose "Preparing to delete $($toDelete.Count) file(s)"

        # Delete files
        foreach ($file in $toDelete) {
            if ($PSCmdlet.ShouldProcess($file.FullName, 'Delete log file')) {
                $FileSystem.RemoveItem($file.FullName, $false)
                Write-Verbose "Deleted: $($file.FullName)"
            }
        }

        Write-Verbose 'Log rotation complete'
    }
    catch {
        Write-Error "Log rotation failed: $_"
        throw
    }
}

#endregion ########## PUBLIC ##########
