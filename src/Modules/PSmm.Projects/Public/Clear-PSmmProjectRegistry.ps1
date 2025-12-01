<#
.SYNOPSIS
    Clears the project registry cache, forcing a full rescan on next access.

.DESCRIPTION
    Invalidates the cached project registry stored in the configuration.
    This forces Get-PSmmProjects to perform a full disk scan on its next invocation.

    Use this function when you know projects have been added, removed, or modified outside
    of the normal PSmediaManager operations (e.g., manual file system changes).

.PARAMETER Config
    The AppConfiguration object containing the project registry.

.EXAMPLE
    Clear-PSmmProjectRegistry -Config $appConfig
    # Clears the registry cache, next Get-PSmmProjects call will rescan all drives

.NOTES
    This function is automatically called by New-PSmmProject after creating a new project.
    You typically don't need to call this manually unless making external file system changes.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Clear-PSmmProjectRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AppConfiguration]$Config
    )

    try {
        if ($Config.Projects.ContainsKey('Registry')) {
            Write-Verbose 'Clearing project registry cache'

            # Reset the registry to force a rescan
            $Config.Projects.Registry = @{
                Master = @{}
                Backup = @{}
                LastScanned = [datetime]::MinValue
                ProjectDirs = @{}
            }

            Write-PSmmLog -Level DEBUG -Context 'Clear-PSmmProjectRegistry' `
                -Message 'Project registry cache cleared' -File

            Write-Verbose 'Project registry cache cleared successfully'
        }
        else {
            Write-Verbose 'No project registry to clear'
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Clear-PSmmProjectRegistry' `
            -Message "Failed to clear project registry: $_" -ErrorRecord $_ -File
        throw
    }
}
