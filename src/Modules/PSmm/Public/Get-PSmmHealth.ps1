<#
.SYNOPSIS
    Returns a health summary for PSmediaManager runtime.
.DESCRIPTION
    Aggregates PowerShell version compliance, required module presence, plugin states,
    storage validation, vault / secret availability, and basic configuration integrity
    into a single structured object (and optionally formatted output).
.PARAMETER Config
    (Optional) The AppConfiguration object; if omitted will attempt Get-AppConfiguration.
.PARAMETER Run
    (Optional) Run/session state object containing Requirements/Plugins status.
.PARAMETER RequirementsPath
    Path to requirements PSD1 file; defaults to PSmm.Requirements.psd1 relative to module root.
.PARAMETER Format
    When set, outputs a human readable table instead of raw object.
.EXAMPLE
    Get-PSmmHealth -Format
.EXAMPLE
    $health = Get-PSmmHealth; if (-not $health.PowerShell.VersionOk) { Write-Warning 'Upgrade PowerShell.' }
.NOTES
    Designed to be lightweight: single pass, no network calls. Plugin latest version checks are
    not performed here; this surfaces cached state only.
#>
#Requires -Version 7.5.4
Set-StrictMode -Version Latest
function Get-PSmmHealth {
    [CmdletBinding()] Param(
        [Parameter()] [object] $Config,
        [Parameter()] [object] $Run,
        [Parameter()] [string] $RequirementsPath,
        [Parameter()] [object[]] $PreviousPlugins,
        [Parameter()] [switch] $Format
    )
    try {
        if (-not (Get-Command -Name Get-PSmmAppConfigurationSafe -ErrorAction SilentlyContinue)) {
            $helperPath = Join-Path -Path $PSScriptRoot -ChildPath '..\\Private\\Get-PSmmAppConfigurationSafe.ps1'
            if (Test-Path -LiteralPath $helperPath) {
                . $helperPath
            }
        }

        if (-not (Get-Command -Name Get-PSmmConfigMemberValue -ErrorAction SilentlyContinue)) {
            $helperPath = Join-Path -Path $PSScriptRoot -ChildPath '..\\Private\\Get-PSmmConfigMemberValue.ps1'
            if (Test-Path $helperPath) {
                . $helperPath
            }
        }

        if (-not (Get-Command -Name Get-PSmmConfigNestedValue -ErrorAction SilentlyContinue)) {
            $helperPath = Join-Path -Path $PSScriptRoot -ChildPath '..\\Private\\Get-PSmmConfigNestedValue.ps1'
            if (Test-Path $helperPath) {
                . $helperPath
            }
        }

        # Resolve configuration if not provided
        if (-not $Config -and (Get-Command -Name Get-AppConfiguration -ErrorAction SilentlyContinue)) {
            if (Get-Command -Name Get-PSmmAppConfigurationSafe -ErrorAction SilentlyContinue) {
                $Config = Get-PSmmAppConfigurationSafe
            }
            else {
                $Config = $null
            }
        }
        # Determine requirements file path
        if (-not $RequirementsPath) {
            # PSScriptRoot is in Public folder, need to go to src/Config/PSmm/PSmm.Requirements.psd1
            # Public -> PSmm -> Modules -> src
            $srcRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
            $candidate = Join-Path -Path $srcRoot -ChildPath 'Config/PSmm/PSmm.Requirements.psd1'
            if (Test-Path $candidate) { $RequirementsPath = $candidate }
        }
        $requirements = $null
        if ($RequirementsPath -and (Test-Path $RequirementsPath)) {
            try { $requirements = (Import-PowerShellDataFile -Path $RequirementsPath) } catch { $requirements = $null }
        }
        # PowerShell version compliance
        $currentPs = $PSVersionTable.PSVersion
        $requiredPs = if ($requirements -and $requirements.PowerShell -and $requirements.PowerShell.VersionMinimum) {
            [version]$requirements.PowerShell.VersionMinimum
        } else {
            [version]'7.5.4'
        }
        $psOk = $currentPs -ge $requiredPs
        # Module checks
        $modules = @()
        if ($requirements -and $requirements.PowerShell -and $requirements.PowerShell.Modules) {
            foreach ($m in $requirements.PowerShell.Modules) {
                $name = $m.Name
                $loaded = Get-Module -Name $name -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
                $modules += [pscustomobject]@{
                    Name = $name
                    Present = [bool]$loaded
                    Version = if ($loaded) { $loaded.Version.ToString() } else { $null }
                }
            }
        }

        # Ensure $modules is always an array
        if ($modules -isnot [object[]]) { $modules = @($modules) }
        # Plugin state (cached)
        $plugins = @()
        $pluginManifest = $null
        if ($Run -and $Run.App -and $Run.App.Plugins -and $Run.App.Plugins.Manifest) {
            $pluginManifest = $Run.App.Plugins.Manifest
        }
        elseif ($Config) {
            $resolvedPlugins = Get-PSmmConfigNestedValue -Object $Config -Path @('Plugins','Resolved') -Default $null
            if ($resolvedPlugins) {
                $pluginManifest = $resolvedPlugins
            }
        }

        if ($pluginManifest) {
            foreach ($scope in $pluginManifest.GetEnumerator()) {
                foreach ($pl in $scope.Value.GetEnumerator()) {
                    if (-not ($pl.Value.Mandatory -or $pl.Value.Enabled)) { continue }
                    $state = $pl.Value.State
                    $prevMatch = $null
                    if ($PreviousPlugins) {
                        $prevMatch = $PreviousPlugins | Where-Object { $_.Name -eq $pl.Value.Name } | Select-Object -First 1
                    }
                    if ($state) {
                        try { $latestVer = $state.LatestVersion } catch { $latestVer = $null }
                        try { $currentVer = $state.CurrentVersion } catch { $currentVer = $null }
                    }
                    else {
                        $latestVer = $null
                        $currentVer = $null
                    }
                    $plugins += [pscustomobject]@{
                        Name = $pl.Value.Name
                        Scope = $scope.Name
                        InstalledVersion = $currentVer
                        LatestVersion = $latestVer
                        UpdateAvailable = if ($latestVer -and $currentVer -and $latestVer -gt $currentVer) { $true } else { $false }
                        PreviousVersion = if ($prevMatch) { $prevMatch.InstalledVersion } else { $null }
                        Changed = if ($prevMatch -and $prevMatch.InstalledVersion -ne $currentVer) { $true } else { $false }
                        Upgraded = if ($prevMatch -and $prevMatch.InstalledVersion -and $currentVer -and ([version]$currentVer -gt [version]$prevMatch.InstalledVersion)) { $true } else { $false }
                    }
                }
            }
        }

        # Storage status (using Config when possible)
        $storage = @()
        if ($Config) {
            $storageSource = Get-PSmmConfigMemberValue -Object $Config -Name 'Storage' -Default $null
            if ($storageSource) {
                $storageKeys = @()
                try {
                    $storageKeys = @($storageSource.Keys)
                }
                catch {
                    $storageKeys = @()
                }

                foreach ($sg in $storageKeys) {
                    $group = $null
                    try { $group = $storageSource[$sg] } catch { $group = $null }

                    $master = Get-PSmmConfigMemberValue -Object $group -Name 'Master' -Default $null

                    $backups = Get-PSmmConfigMemberValue -Object $group -Name 'Backups' -Default $null
                    if (-not $backups) {
                        $backups = Get-PSmmConfigMemberValue -Object $group -Name 'Backup' -Default $null
                    }

                    $masterCount = if ($null -ne $master) { 1 } else { 0 }

                    $backupCount = 0
                    if ($null -ne $backups) {
                        if ($backups -is [System.Collections.IDictionary]) {
                            try { $backupCount = @($backups.Keys).Count } catch { $backupCount = 0 }
                        }
                        else {
                            try { $backupCount = @($backups.Keys).Count } catch { $backupCount = 0 }
                            if ($backupCount -eq 0) {
                                try { $backupCount = @($backups.PSObject.Properties).Count } catch { $backupCount = 0 }
                            }
                        }
                    }

                    $storage += [pscustomobject]@{
                        Group = $sg
                        MasterDrives = $masterCount
                        BackupDrives = $backupCount
                    }
                }
            }
        }
        # Secrets / Vault status
        $githubToken = if ($Config) { Get-PSmmConfigNestedValue -Object $Config -Path @('Secrets','GitHubToken') -Default $null } else { $null }
        $vaultPathValue = if ($Config) { Get-PSmmConfigNestedValue -Object $Config -Path @('Secrets','VaultPath') -Default $null } else { $null }
        $vaultStatus = [pscustomobject]@{
            GitHubTokenPresent = [bool]$githubToken
            VaultPath = $vaultPathValue
            KeePassXCAvailable = $false
            VaultInitialized = [bool]$vaultPathValue
        }

        # Update Modules to use 'Installed' property name instead of 'Present'
        $modulesFixed = @($modules | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Version = $_.Version; Installed = $_.Present } })

        # Structure storage with Configured flag and GroupCount
        $storageFixed = [pscustomobject]@{
            Configured = ($storage.Count -gt 0)
            GroupCount = $storage.Count
            Status = if ($storage.Count -gt 0) { 'OK' } else { 'NotConfigured' }
            Details = $storage
        }

        $configPath = $null
        if ($Config) {
            try {
                $configPath = Get-PSmmConfigNestedValue -Object $Config -Path @('Paths','App','Config') -Default $null
                if ($null -eq $configPath) {
                    $configPath = Get-PSmmConfigNestedValue -Object $Config -Path @('Paths','Config') -Default $null
                }
            } catch { $configPath = $null }
        }

        $result = [pscustomobject]@{
            PowerShell = [pscustomobject]@{ CurrentVersion = $currentPs.ToString(); RequiredVersion = $requiredPs.ToString(); VersionOk = $psOk }
            Modules    = $modulesFixed
            Plugins    = $plugins
            Storage    = $storageFixed
            Vault      = $vaultStatus
            Configuration = [pscustomobject]@{ Valid = ($null -ne $Config); ConfigPath = $configPath; HasRequiredKeys = ($null -ne $Config) }
            OverallStatus = if ($psOk) { 'Healthy' } else { 'Warning' }
            IssueCount = if ($psOk) { 0 } else { 1 }
            Issues = if (-not $psOk) { @('PowerShell version below requirement') } else { @() }
            IsHealthy = $psOk
            Timestamp  = (Get-Date).ToString('s')
        }
        if ($Format) {
            Write-Output '== PowerShell =='
            Write-Output "Current: $($result.PowerShell.CurrentVersion) / Required: $($result.PowerShell.RequiredVersion) / OK: $($result.PowerShell.VersionOk)"
            Write-Output "== Modules =="
            $result.Modules | Format-Table Name, Version, Installed | Out-String | Write-Output
            Write-Output "== Plugins =="
            if ($result.Plugins.Count -gt 0) {
                $result.Plugins | Sort-Object Name | Format-Table Name, PreviousVersion, InstalledVersion, LatestVersion, Changed, Upgraded, UpdateAvailable | Out-String | Write-Output
            } else { Write-Output 'No plugin state available.' }
            Write-Output '== Storage =='
            if ($result.Storage.Details.Count -gt 0) {
                $result.Storage.Details | Format-Table Group, MasterDrives, BackupDrives | Out-String | Write-Output
            } else { Write-Output 'No storage configuration loaded.' }
            Write-Output '== Vault =='
            Write-Output "Vault: $($result.Vault.VaultPath) / GitHubToken: $($result.Vault.GitHubTokenPresent)"
            return
        }
        return $result
    }
    catch {
        Write-Warning "Failed to build health summary: $($_.Exception.Message)"
        return $null
    }
}
