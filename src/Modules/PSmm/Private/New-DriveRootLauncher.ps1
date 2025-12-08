function New-DriveRootLauncher {
    <#
    .SYNOPSIS
        Creates a CMD launcher in the drive root to start PSmediaManager.

    .DESCRIPTION
        This function creates a Start-PSmediaManager.lnk file in the drive root
        (parent directory of the repository root) if it doesn't already exist.

        The Windows shortcut provides a convenient launcher for portable drives,
        allowing users to start PSmediaManager directly from the drive root without
        navigating into the repository folder.

    .PARAMETER RepositoryRoot
        The absolute path to the PSmediaManager repository root directory.
        This should be the directory containing the .git folder and src/ directory.

    .EXAMPLE
        New-DriveRootLauncher -RepositoryRoot 'E:\PSmediaManager'
        Creates E:\Start-PSmediaManager.lnk if it doesn't exist.

    .NOTES
        Author           : Der Mosh
        Created          : 2025-11-20

        The function will:
        - Check if the CMD file already exists (skip creation if it does)
        - Calculate the drive root from the repository root
        - Create the CMD file with proper PowerShell invocation
        - Log warnings if creation fails (e.g., read-only drive)
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        $PathProvider
    )

    try {
        # Calculate drive root (parent of repository root)
        $driveRoot = Split-Path -Path $RepositoryRoot -Parent

        if ([string]::IsNullOrWhiteSpace($driveRoot)) {
            Write-Warning "Cannot determine drive root from repository root: $RepositoryRoot"
            return
        }

        # Define launcher file path
        $launcherPath = $PathProvider.CombinePath(@($driveRoot, 'Start-PSmediaManager.lnk'))
        $repoLauncher = $PathProvider.CombinePath(@($RepositoryRoot, 'Start-PSmediaManager.ps1'))

        # Check if launcher already exists
        if ($FileSystem.TestPath($launcherPath)) {
            Write-Verbose "Launcher already exists: $launcherPath"
            return
        }

        if (-not $FileSystem.TestPath($repoLauncher)) {
            Write-Warning "Repository launcher not found at: $repoLauncher"
            return
        }

        Write-Verbose "Creating drive root launcher: $launcherPath"

        # Remove legacy launchers created by previous versions
        $legacyCmd = $PathProvider.CombinePath(@($driveRoot, 'Start-PSmediaManager.cmd'))
        $legacyPs1 = $PathProvider.CombinePath(@($driveRoot, 'Start-PSmediaManager.ps1'))
        foreach ($legacy in @($legacyCmd, $legacyPs1)) {
            if ($FileSystem.TestPath($legacy)) {
                try {
                    if ($PSCmdlet.ShouldProcess($legacy, 'Remove legacy launcher')) {
                        $FileSystem.RemoveItem($legacy, $false)
                        Write-Verbose "Removed legacy launcher: $legacy"
                    }
                    else {
                        Write-Verbose "Skipping removal of legacy launcher (WhatIf/Confirm): $legacy"
                    }
                }
                catch {
                    Write-Warning "Failed to remove legacy launcher '$legacy': $_"
                }
            }
        }

        try {
            $shell = New-Object -ComObject WScript.Shell
        }
        catch {
            Write-Warning "WScript.Shell COM object unavailable: $_"
            return
        }

        try {
            if (-not $PSCmdlet.ShouldProcess($launcherPath, 'Create drive root launcher')) {
                Write-Verbose "Creation of launcher skipped by ShouldProcess: $launcherPath"
                return
            }

            $shortcut = $shell.CreateShortcut($launcherPath)
            $shortcut.TargetPath = 'pwsh.exe'
            $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$repoLauncher`""
            $shortcut.WorkingDirectory = $RepositoryRoot
            $shortcut.Description = 'Launch PSmediaManager'
            $shortcut.IconLocation = 'pwsh.exe,0'
            $shortcut.Save()
            Write-Verbose "Successfully created launcher: $launcherPath"
        }
        catch {
            Write-Warning "Failed to create launcher at '$launcherPath': $_"
        }
    }
    catch {
        Write-Warning "Error in New-DriveRootLauncher: $_"
    }
}
