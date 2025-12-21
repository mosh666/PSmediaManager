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
        [object]$Config  # Uses [object] instead of [AppConfiguration] to avoid type resolution issues when module is loaded
    )

    function Get-ConfigMemberValue([object]$Object, [string]$Name) {
        if ($null -eq $Object) {
            return $null
        }

        if ($Object -is [System.Collections.IDictionary]) {
            try {
                if ($Object.ContainsKey($Name)) {
                    return $Object[$Name]
                }
            }
            catch {
                Write-Verbose "[Clear-PSmmProjectRegistry] Get-ConfigMemberValue: ContainsKey('$Name') failed: $_"
            }

            try {
                if ($Object.Contains($Name)) {
                    return $Object[$Name]
                }
            }
            catch {
                Write-Verbose "[Clear-PSmmProjectRegistry] Get-ConfigMemberValue: Contains('$Name') failed: $_"
            }

            try {
                foreach ($k in $Object.Keys) {
                    if ($k -eq $Name) {
                        return $Object[$k]
                    }
                }
            }
            catch {
                Write-Verbose "[Clear-PSmmProjectRegistry] Get-ConfigMemberValue: enumerating keys for '$Name' failed: $_"
            }

            return $null
        }

        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) {
            return $p.Value
        }

        return $null
    }

    function Set-ConfigMemberValue {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [Parameter()][AllowNull()][object]$Object,
            [Parameter(Mandatory)][string]$Name,
            [Parameter()][AllowNull()][object]$Value
        )

        if ($null -eq $Object) { return }

        if (-not $PSCmdlet.ShouldProcess($Name, 'Set config member value')) {
            return
        }

        if ($Object -is [System.Collections.IDictionary]) {
            $Object[$Name] = $Value
            return
        }

        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) {
            $Object.$Name = $Value
            return
        }

        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }

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
            $Config['Projects'] = [ProjectsConfig]::FromObject($null)
        }
        else {
            $Config['Projects'] = [ProjectsConfig]::FromObject($Config['Projects'])
        }
        $Config = [pscustomobject]$Config
    }

    try {
        $projectsConfig = Get-ConfigMemberValue -Object $Config -Name 'Projects'
        if ($null -eq $projectsConfig) {
            Write-Verbose 'No Projects configuration present'
            return
        }

        if ($projectsConfig -isnot [ProjectsConfig]) {
            $projectsConfig = [ProjectsConfig]::FromObject($projectsConfig)
            Set-ConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig
        }

        Write-Verbose 'Clearing project registry cache'

        # Reset the registry to force a rescan
        Set-ConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value ([ProjectsRegistryCache]::new())
        Set-ConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig

        Write-PSmmLog -Level DEBUG -Context 'Clear-PSmmProjectRegistry' `
            -Message 'Project registry cache cleared' -File

        Write-Verbose 'Project registry cache cleared successfully'
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Clear-PSmmProjectRegistry' `
            -Message "Failed to clear project registry: $_" -ErrorRecord $_ -File
        throw
    }
}
