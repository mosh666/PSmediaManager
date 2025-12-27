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

if (-not (Get-Command -Name 'Get-PSmmProjectsConfigMemberValue' -ErrorAction SilentlyContinue)) {
    $helpersPath = Join-Path -Path $PSScriptRoot -ChildPath '..\\Private\\ConfigMemberAccessHelpers.ps1'
    if (Test-Path -Path $helpersPath) {
        . $helpersPath
    }
}

function Clear-PSmmProjectRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config  # Uses [object] instead of [AppConfiguration] to avoid type resolution issues when module is loaded
    )

    # Support legacy dictionary-shaped configs by normalizing Projects into the typed model
    # and using a PSCustomObject view for property access.
    if ($Config -is [System.Collections.IDictionary]) {
        $hasProjects = $false
        try { $hasProjects = $Config.ContainsKey('Projects') } catch { $hasProjects = $false }
        if (-not $hasProjects) {
            try { $hasProjects = $Config.Contains('Projects') } catch { $hasProjects = $false }
        }
        if (-not $hasProjects) {
            try {
                foreach ($k in $Config.Keys) {
                    if ($k -eq 'Projects') { $hasProjects = $true; break }
                }
            }
            catch { $hasProjects = $false }
        }

        if (-not $hasProjects -or $null -eq $Config['Projects']) {
            $Config['Projects'] = ConvertTo-PSmmProjectsConfig -Object $null
        }
        else {
            $Config['Projects'] = ConvertTo-PSmmProjectsConfig -Object $Config['Projects']
        }
        $Config = [pscustomobject]$Config
    }

    try {
        $projectsConfig = Get-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects'
        if ($null -eq $projectsConfig) {
            Write-Verbose 'No Projects configuration present'
            return
        }

        $projectsConfigType = Resolve-PSmmProjectsType -Name 'ProjectsConfig'
        if ($projectsConfigType) {
            if ($projectsConfig -isnot $projectsConfigType) {
                $projectsConfig = ConvertTo-PSmmProjectsConfig -Object $projectsConfig
            }
        }
        else {
            $projectsConfig = ConvertTo-PSmmProjectsConfig -Object $projectsConfig
        }

        Write-Verbose 'Clearing project registry cache'

        # Reset the registry to force a rescan
        Set-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value ([ProjectsRegistryCache]::new())
        Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig

        $writeLog = Get-Command -Name Write-PSmmLog -ErrorAction SilentlyContinue
        if ($null -ne $writeLog) {
            Write-PSmmLog -Level DEBUG -Context 'Clear-PSmmProjectRegistry' `
                -Message 'Project registry cache cleared' -File
        }

        Write-Verbose 'Project registry cache cleared successfully'
    }
    catch {
        $writeLog = Get-Command -Name Write-PSmmLog -ErrorAction SilentlyContinue
        if ($null -ne $writeLog) {
            Write-PSmmLog -Level ERROR -Context 'Clear-PSmmProjectRegistry' `
                -Message "Failed to clear project registry: $_" -ErrorRecord $_ -File
        }
        throw
    }
}
