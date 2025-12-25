#Requires -Version 7.5.4
Set-StrictMode -Version Latest

if (-not (Get-Command -Name 'Get-PSmmProjectsConfigMemberValue' -ErrorAction SilentlyContinue)) {
    $helpersPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Private\ConfigMemberAccessHelpers.ps1'
    if (Test-Path -Path $helpersPath) {
        . $helpersPath
    }
}

function Get-PSmmProjects {
    <#
    .SYNOPSIS
        Retrieves all PSmediaManager projects from Master and Backup storage drives.

    .DESCRIPTION
        Scans all configured Master and Backup storage drives for project folders,
        returning a structured hashtable grouped by drive label. Skips drives with
        errors or missing drive letters, and excludes the _GLOBAL_ project folder.

        Uses a registry cache to speed up subsequent calls. The cache is invalidated
        and refreshed when project changes are detected.

    .PARAMETER Config
        Application configuration object (AppConfiguration).
        Preferred modern approach with strongly-typed configuration.

    .PARAMETER Force
        Forces a full rescan of all drives, bypassing the registry cache.

    .PARAMETER FileSystem
        FileSystem service used to enumerate drives and project folders.
        Required (service-first DI).

    .EXAMPLE
        $projects = Get-PSmmProjects -Config $appConfig -FileSystem $FileSystem
        # Returns: @{ Master = @{ DriveLabel = @(ProjectObjects...) }; Backup = @{ ... } }

    .EXAMPLE
        $projects = Get-PSmmProjects -Config $appConfig -Force
        # Forces a full rescan, ignoring cached data

    .OUTPUTS
        Hashtable containing Master and Backup projects, organized by drive label.
        Each project object contains: Name, Path, Drive, Label, SerialNumber

    .NOTES
        Projects are expected to be in a 'Projects' folder at the root of each drive.
        The _GLOBAL_ project is automatically excluded from results.
        Registry cache includes LastScanned timestamp for cache invalidation.

        BREAKING CHANGE: Requires injected -FileSystem (service-first DI); does not resolve FileSystem from ServiceContainer.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function retrieves multiple project configurations')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter()]
        [switch]$Force,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem
    )

    function ConvertTo-PSmmLegacyView([object]$value) {
        if ($null -eq $value) {
            return $null
        }

        if ($value -is [System.Collections.IDictionary]) {
            return [pscustomobject]$value
        }

        return $value
    }

    function Get-PSmmMapValue([object]$map, [string]$key) {
        if ($null -eq $map -or [string]::IsNullOrWhiteSpace($key)) {
            return $null
        }

        if ($map -is [System.Collections.IDictionary]) {
            try {
                if ($map.ContainsKey($key)) { return $map[$key] }
            }
            catch {
                Write-Verbose "[Get-PSmmProjects] Get-PSmmMapValue: ContainsKey('$key') failed: $_"
            }

            try {
                if ($map.Contains($key)) { return $map[$key] }
            }
            catch {
                Write-Verbose "[Get-PSmmProjects] Get-PSmmMapValue: Contains('$key') failed: $_"
            }

            try {
                foreach ($k in $map.Keys) {
                    if ($k -eq $key) {
                        return $map[$k]
                    }
                }
            }
            catch {
                Write-Verbose "[Get-PSmmProjects] Get-PSmmMapValue: enumerating keys for '$key' failed: $_"
            }
            return $null
        }

        try {
            return $map[$key]
        }
        catch {
            Write-Verbose "[Get-PSmmProjects] Get-PSmmMapValue: indexer access for '$key' failed: $_"
        }

        if (Get-Command -Name Test-PSmmProjectsConfigMember -ErrorAction SilentlyContinue) {
            if (Test-PSmmProjectsConfigMember -Object $map -Name $key) {
                return Get-PSmmProjectsConfigMemberValue -Object $map -Name $key
            }
        }
        else {
            $fallback = Get-PSmmProjectsConfigMemberValue -Object $map -Name $key
            if ($null -ne $fallback) {
                return $fallback
            }
        }

        return $null
    }

    function ConvertTo-HashtableShallow([object]$value) {
        if ($null -eq $value) {
            return @{}
        }

        if ($value -is [hashtable]) {
            return $value
        }

        if ($value -is [System.Collections.IDictionary]) {
            $ht = @{}
            foreach ($k in $value.Keys) {
                $ht[[string]$k] = $value[$k]
            }
            return $ht
        }

        $ht2 = @{}
        $memberNames = @(
            $value |
                Get-Member -MemberType NoteProperty, Property -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name
        )

        foreach ($memberName in $memberNames) {
            if ([string]::IsNullOrWhiteSpace([string]$memberName)) {
                continue
            }

            $memberValue = $null
            try {
                $memberValue = $value.$memberName
            }
            catch {
                $memberValue = $null
            }

            $ht2[[string]$memberName] = $memberValue
        }
        return $ht2
    }

    function ConvertTo-StorageMap([object]$storage) {
        $out = @{}
        if ($null -eq $storage) {
            return $out
        }

        $keys = @()
        try {
            $keys = @($storage.Keys)
        }
        catch {
            if ($storage -isnot [System.Collections.IDictionary]) {
                $keys = @(
                    $storage |
                        Get-Member -MemberType NoteProperty, Property -ErrorAction SilentlyContinue |
                        Select-Object -ExpandProperty Name
                )
            }
        }

        $sgType = 'StorageGroupConfig' -as [type]

        foreach ($k in $keys) {
            $key = [string]$k
            if ([string]::IsNullOrWhiteSpace($key)) { continue }

            $raw = Get-PSmmMapValue -map $storage -key $key

            if ($null -ne $sgType) {
                try {
                    $out[$key] = $sgType::FromObject($key, $raw)
                    continue
                }
                catch {
                    Write-Verbose "[Get-PSmmProjects] ConvertTo-StorageMap: failed to convert storage group '$key' via typed model: $_"
                }
            }

            $sg = ConvertTo-PSmmLegacyView -value $raw
            if ($null -eq $sg) { continue }

            # Normalize Backup -> Backups for legacy shapes
            $hasBackups = Test-PSmmProjectsConfigMember -Object $sg -Name 'Backups'
            $hasBackup = Test-PSmmProjectsConfigMember -Object $sg -Name 'Backup'
            if (-not $hasBackups -and $hasBackup) {
                $backupValue = Get-PSmmProjectsConfigMemberValue -Object $sg -Name 'Backup'
                $sg | Add-Member -NotePropertyName 'Backups' -NotePropertyValue $backupValue -Force
            }

            # Ensure Backups is a dictionary-like value and that child drive configs are PSCustomObject views
            $bk = $null
            try { $bk = $sg.Backups } catch { $bk = $null }
            if ($null -ne $bk -and $bk -isnot [System.Collections.IDictionary]) {
                $bk = ConvertTo-HashtableShallow -value $bk
                $sg | Add-Member -NotePropertyName 'Backups' -NotePropertyValue $bk -Force
            }

            $master = $null
            try { $master = $sg.Master } catch { $master = $null }
            if ($master -is [System.Collections.IDictionary]) {
                $sg | Add-Member -NotePropertyName 'Master' -NotePropertyValue ([pscustomobject]$master) -Force
            }

            if ($bk -is [System.Collections.IDictionary]) {
                $fixed = @{}
                foreach ($bkId in $bk.Keys) {
                    $v = $bk[$bkId]
                    $fixed[[string]$bkId] = if ($v -is [System.Collections.IDictionary]) { [pscustomobject]$v } else { $v }
                }
                $sg | Add-Member -NotePropertyName 'Backups' -NotePropertyValue $fixed -Force
            }

            $out[$key] = $sg
        }

        return $out
    }

    # Support legacy dictionary-shaped configs by normalizing Projects into the typed model
    # and using a PSCustomObject view for property access under StrictMode.
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

        $hasStorage = $false
        try { $hasStorage = $Config.ContainsKey('Storage') } catch { $hasStorage = $false }
        if (-not $hasStorage) {
            try { $hasStorage = $Config.Contains('Storage') } catch { $hasStorage = $false }
        }
        if (-not $hasStorage) {
            try {
                foreach ($k in $Config.Keys) {
                    if ($k -eq 'Storage') { $hasStorage = $true; break }
                }
            }
            catch { $hasStorage = $false }
        }

        if (-not $hasStorage -or $null -eq $Config['Storage']) {
            $Config['Storage'] = @{}
        }

        $Config = [pscustomobject]$Config
    }

    if ($null -eq $FileSystem) {
        throw 'Get-PSmmProjects requires a non-null FileSystem service (pass DI service).'
    }

    # Ensure Projects.Registry exists on Config
    $projectsConfig = Get-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects'
    if ($null -eq $projectsConfig) {
        $projectsConfig = [ProjectsConfig]::FromObject($null)
        Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig
    }
    elseif ($projectsConfig -isnot [ProjectsConfig]) {
        $projectsConfig = [ProjectsConfig]::FromObject($projectsConfig)
        Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig
    }

    $registry = Get-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Registry'
    if ($null -eq $registry) {
        $registry = [ProjectsRegistryCache]::new()
        Set-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value $registry
    }
    else {
        # Normalize legacy hashtable/object shapes into the typed cache model
        $registry = [ProjectsRegistryCache]::FromObject($registry)
        Set-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value $registry
    }

    try {
        $isTestMode = [string]::Equals($env:MEDIA_MANAGER_TEST_MODE, '1', [System.StringComparison]::OrdinalIgnoreCase)

        # Local reference to registry
        $registry = Get-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Registry'

        # Disk-based cache has been removed; rely on in-memory registry and full scan

        # Check if we should use cached data (in-memory registry)
        $UseCache = -not $Force.IsPresent
        if ($UseCache -and $registry.LastScanned -ne [datetime]::MinValue) {
            Write-Verbose 'Checking if registry cache is still valid...'

            # Check if any Projects directories have been modified since last scan
            # Support both FileSystem abstraction and direct PowerShell cmdlets
            # Verify FileSystem service is available
            $CacheInvalid = $false  # Default: assume valid unless proven otherwise

            if (-not $FileSystem) {
                Write-PSmmLog -Level WARNING -Context 'Get-PSmmProjects' `
                    -Message 'FileSystem service not available, cannot validate cache' -File
                Write-Verbose 'FileSystem service not available, bypassing cache validation'
            } else {
                $storageSource = Get-PSmmProjectsConfigMemberValue -Object $Config -Name 'Storage'
                $Storage = ConvertTo-StorageMap -storage $storageSource

                # Only validate cache against storage if storage is configured
                if ($null -ne $Storage -and $Storage.Count -gt 0) {
                    foreach ($storageGroup in ($Storage.Keys | Sort-Object)) {
                        $sg = $Storage[$storageGroup]
                        if ($null -eq $sg) { continue }

                        # Check Master drive
                        if ($null -ne $sg.Master) {
                            $MasterDisk = $sg.Master
                            $driveExists = $isTestMode -or (Test-DriveRootPath -DriveLetter $MasterDisk.DriveLetter -FileSystem $FileSystem)
                            if ($driveExists) {
                                $ProjectsPath = Join-Path -Path $MasterDisk.DriveLetter -ChildPath 'Projects'
                                try {
                                    $projectsPathExists = $FileSystem.TestPath($ProjectsPath)
                                    if ($projectsPathExists) {
                                        $ProjectsDirInfo = $FileSystem.GetItemProperty($ProjectsPath)
                                        $CurrentWriteTime = $ProjectsDirInfo.LastWriteTime
                                        $CacheKey = "$($MasterDisk.SerialNumber)_Projects"

                                        if (-not $registry.ProjectDirs.ContainsKey($CacheKey) -or
                                            $registry.ProjectDirs[$CacheKey] -ne $CurrentWriteTime) {
                                            Write-Verbose "Projects directory modified on Master drive $($MasterDisk.Label)"
                                            $CacheInvalid = $true
                                            break
                                        }
                                    }
                                }
                                catch {
                                    Write-Verbose "Error checking Master drive cache: $_"
                                    $CacheInvalid = $true
                                    break
                                }
                            }
                        }

                        # Check Backup drives
                        if ($null -ne $sg.Backups -and $sg.Backups.Count -gt 0) {
                            foreach ($backupId in ($sg.Backups.Keys | Sort-Object)) {
                                $BackupDisk = $sg.Backups[$backupId]
                                $backupExists = $isTestMode -or (Test-DriveRootPath -DriveLetter $BackupDisk.DriveLetter -FileSystem $FileSystem)
                                if ($backupExists) {
                                    $ProjectsPath = Join-Path -Path $BackupDisk.DriveLetter -ChildPath 'Projects'
                                    try {
                                        $projectsPathExists = $FileSystem.TestPath($ProjectsPath)
                                        if ($projectsPathExists) {
                                            $ProjectsDirInfo = $FileSystem.GetItemProperty($ProjectsPath)
                                            $CurrentWriteTime = $ProjectsDirInfo.LastWriteTime
                                            $CacheKey = "$($BackupDisk.SerialNumber)_Projects"

                                            if (-not $registry.ProjectDirs.ContainsKey($CacheKey) -or
                                                $registry.ProjectDirs[$CacheKey] -ne $CurrentWriteTime) {
                                                Write-Verbose "Projects directory modified on Backup drive $($BackupDisk.Label)"
                                                $CacheInvalid = $true
                                                break
                                            }
                                        }
                                    }
                                    catch {
                                        Write-Verbose "Error checking Backup drive cache: $_"
                                        $CacheInvalid = $true
                                        break
                                    }
                                }
                            }

                            if ($CacheInvalid) { break }
                        }
                    }
                }
            }

            # Return cached data if still valid
            if (-not $CacheInvalid) {
                Write-Verbose 'Using cached project registry (no changes detected)'
                Write-PSmmLog -Level DEBUG -Context 'Get-PSmmProjects' `
                    -Message "Using cached project registry (last scanned: $($registry.LastScanned))" -File

                # The registry stores compact drive summaries which include a 'Projects' property
                # containing the full project arrays. Convert the compact registry back into the
                # same shape returned by a full scan: a hashtable of driveLabel -> project-array.
                $cachedMaster = @{}
                foreach ($label in ($registry.Master.Keys | Sort-Object)) {
                    $entry = $registry.Master[$label]
                    $projectsArray = if ($null -ne $entry -and $entry -is [ProjectsDriveRegistryEntry]) { $entry.Projects } else { @() }
                    if ($null -eq $projectsArray) { $projectsArray = @() }
                    $cachedMaster[$label] = $projectsArray
                }

                $cachedBackup = @{}
                foreach ($label in ($registry.Backup.Keys | Sort-Object)) {
                    $entry = $registry.Backup[$label]
                    $projectsArray = if ($null -ne $entry -and $entry -is [ProjectsDriveRegistryEntry]) { $entry.Projects } else { @() }
                    if ($null -eq $projectsArray) { $projectsArray = @() }
                    $cachedBackup[$label] = $projectsArray
                }

                return @{
                    Master = $cachedMaster
                    Backup = $cachedBackup
                }
            }
            else {
                Write-Verbose 'Cache invalidated, performing full project scan'
                Write-PSmmLog -Level DEBUG -Context 'Get-PSmmProjects' `
                    -Message 'Project changes detected, invalidating registry cache' -File
            }
        }
        elseif ($Force.IsPresent) {
            Write-Verbose 'Force parameter specified, performing full project scan'
            Write-PSmmLog -Level DEBUG -Context 'Get-PSmmProjects' `
                -Message 'Force scan requested, bypassing registry cache' -File
        }
        else {
            Write-Verbose 'No cached data available, performing initial project scan'
            Write-PSmmLog -Level DEBUG -Context 'Get-PSmmProjects' `
                -Message 'Performing initial project scan (no registry cache)' -File
        }

        Write-Verbose 'Starting full project discovery...'

        # Initialize hashtables for projects grouped by drive label
        $MasterProjects = @{}
        $BackupProjects = @{}
        $ProjectDirs = @{}

        # Get all storage groups (1, 2, etc.)
        $storageSource = Get-PSmmProjectsConfigMemberValue -Object $Config -Name 'Storage'
        $Storage = ConvertTo-StorageMap -storage $storageSource

        # Process each storage group
        foreach ($storageGroup in $Storage.Keys | Sort-Object) {
            Write-Verbose "Processing Storage Group $storageGroup..."
            $sg = $Storage[$storageGroup]
            if ($null -eq $sg) { continue }

            # Process Master drive for this storage group
            if ($null -ne $sg.Master) {
                $MasterDisk = $sg.Master
                Write-Verbose "Processing Master drive: $($MasterDisk.Label)"

                $Result = Get-ProjectsFromDrive -Disk $MasterDisk `
                    -StorageGroup $storageGroup `
                    -DriveType 'Master' `
                    -Projects $MasterProjects `
                    -ProjectDirs $ProjectDirs `
                    -Config $Config `
                    -FileSystem $FileSystem

                $MasterProjects = $Result.Projects
                $ProjectDirs = $Result.ProjectDirs
            }

            # Process Backup drives for this storage group
            if ($null -ne $sg.Backups) {
                $BackupStorage = $sg.Backups

                # Check if there are any backup drives configured
                if ($BackupStorage.Count -gt 0) {
                    Write-Verbose "Processing $($BackupStorage.Count) Backup drive(s) for Storage Group $storageGroup..."

                    foreach ($backupId in ($BackupStorage.Keys | Sort-Object)) {
                        $BackupDisk = $BackupStorage[$backupId]
                        Write-Verbose "Processing Backup drive ${backupId}: $($BackupDisk.Label)"

                        $Result = Get-ProjectsFromDrive -Disk $BackupDisk `
                            -StorageGroup $storageGroup `
                            -BackupId $backupId `
                            -DriveType 'Backup' `
                            -Projects $BackupProjects `
                            -ProjectDirs $ProjectDirs `
                            -Config $Config `
                            -FileSystem $FileSystem

                        $BackupProjects = $Result.Projects
                        $ProjectDirs = $Result.ProjectDirs
                    }
                }
            }
        }

        # Build a compact per-drive registry summary to avoid duplicating per-project arrays
        function Convert-ProjectsToDriveRegistry {
            [CmdletBinding()]
            [OutputType([hashtable])]
            param(
                [Parameter(Mandatory)][hashtable]$ProjectsByLabel
            )
            $out = @{}
            foreach ($label in ($ProjectsByLabel.Keys | Sort-Object)) {
                $items = $ProjectsByLabel[$label]
                if ($null -eq $items) { continue }
                # Choose the first item as representative for drive-level metadata
                $first = if ($items -is [System.Collections.IEnumerable] -and $items -isnot [string]) { $items | Select-Object -First 1 } else { $items }
                if ($null -eq $first) { continue }
                $entry = [ProjectsDriveRegistryEntry]::FromProjectSample($first, @($ProjectsByLabel[$label]))
                if ([string]::IsNullOrWhiteSpace($entry.Label)) { $entry.Label = [string]$label }
                $out[[string]$label] = $entry
            }
            return $out
        }

        # Decide whether registry actually changed before updating/logging
        function Get-StringMemberValue {
            param(
                [Parameter(Mandatory)][AllowNull()][object]$Object,
                [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
                [Parameter()][AllowNull()][string]$Default = ''
            )

            $val = Get-PSmmProjectsConfigMemberValue -Object $Object -Name $Name
            if ($null -eq $val) {
                return $Default
            }

            try {
                return [string]$val
            }
            catch {
                return $Default
            }
        }

        function Get-FlattenedProjectsFromByLabel {
            param([Parameter(Mandatory)][hashtable]$ByLabel)
            $result = @()
            foreach ($label in ($ByLabel.Keys | Sort-Object)) {
                $items = $ByLabel[$label]
                if ($null -eq $items) { continue }
                foreach ($item in $items) {
                    # Use a stable identity key capturing moves/renames/drives
                    $driveType = Get-StringMemberValue -Object $item -Name 'DriveType' -Default ''
                    $backupId = Get-StringMemberValue -Object $item -Name 'BackupId' -Default ''
                    $serial = Get-StringMemberValue -Object $item -Name 'SerialNumber' -Default ''
                    $name = Get-StringMemberValue -Object $item -Name 'Name' -Default ''
                    $path = Get-StringMemberValue -Object $item -Name 'Path' -Default ''
                    $labelVal = Get-StringMemberValue -Object $item -Name 'Label' -Default ([string]$label)
                    $result += "${driveType}|${labelVal}|${backupId}|${serial}|${name}|${path}"
                }
            }
            , $result
        }

        # Helper function to extract a value from either a hashtable key or PSObject property
        function Get-FromKeyOrProperty {
            param(
                [Parameter(Mandatory)]
                $Object,
                [Parameter(Mandatory)]
                [string]$Name,
                $Default = $null
            )

            if ($Object -is [ProjectsDriveRegistryEntry]) {
                try { return $Object.$Name } catch { return $Default }
            }

            if ($Object -is [hashtable] -and $Object.ContainsKey($Name)) {
                return $Object[$Name]
            }
            elseif ($null -ne $Object -and (Test-PSmmProjectsConfigMember -Object $Object -Name $Name)) {
                return Get-PSmmProjectsConfigMemberValue -Object $Object -Name $Name
            }
            else {
                return $Default
            }
        }

        function Get-FlattenedProjectsFromRegistrySide {
            param([Parameter(Mandatory)][System.Collections.IDictionary]$RegistrySide)
            $result = @()
            foreach ($label in ($RegistrySide.Keys | Sort-Object)) {
                $entry = $RegistrySide[$label]
                if ($null -eq $entry) { continue }
                $projArr = Get-FromKeyOrProperty -Object $entry -Name 'Projects' -Default @()
                foreach ($item in $projArr) {
                    $driveType = Get-StringMemberValue -Object $item -Name 'DriveType' -Default ''
                    $backupId = Get-StringMemberValue -Object $item -Name 'BackupId' -Default ''
                    $serial = Get-StringMemberValue -Object $item -Name 'SerialNumber' -Default ''
                    $name = Get-StringMemberValue -Object $item -Name 'Name' -Default ''
                    $path = Get-StringMemberValue -Object $item -Name 'Path' -Default ''
                    $labelVal = Get-StringMemberValue -Object $item -Name 'Label' -Default ([string]$label)
                    $result += "${driveType}|${labelVal}|${backupId}|${serial}|${name}|${path}"
                }
            }
            , $result
        }

        $prevMasterFlat = Get-FlattenedProjectsFromRegistrySide -RegistrySide $registry.Master
        $prevBackupFlat = Get-FlattenedProjectsFromRegistrySide -RegistrySide $registry.Backup
        $newMasterFlat = Get-FlattenedProjectsFromByLabel -ByLabel $MasterProjects
        $newBackupFlat = Get-FlattenedProjectsFromByLabel -ByLabel $BackupProjects

        $registryChanged = $true
        if ($null -ne $prevMasterFlat -and $null -ne $prevBackupFlat) {
            # Compare as sets (order-independent)
            $hsPrev = [System.Collections.Generic.HashSet[string]]::new()
            if ($prevMasterFlat) { $hsPrev.UnionWith([string[]]$prevMasterFlat) }
            if ($prevBackupFlat) { $hsPrev.UnionWith([string[]]$prevBackupFlat) }
            $hsNew = [System.Collections.Generic.HashSet[string]]::new()
            if ($newMasterFlat) { $hsNew.UnionWith([string[]]$newMasterFlat) }
            if ($newBackupFlat) { $hsNew.UnionWith([string[]]$newBackupFlat) }
            $registryChanged = -not $hsPrev.SetEquals($hsNew)
        }

        # Always refresh ProjectDirs and LastScanned to keep cache valid
        $registry.ProjectDirs = $registry.ConvertProjectDirs($ProjectDirs)
        $registry.LastScanned = Get-Date

        if ($registryChanged) {
            # Update the registry cache with compact summaries and persist full arrays inside
            $registry.Master = Convert-ProjectsToDriveRegistry -ProjectsByLabel $MasterProjects
            $registry.Backup = Convert-ProjectsToDriveRegistry -ProjectsByLabel $BackupProjects

            # Sync registry back to Config
            Set-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value $registry
            Set-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig

            $masterCount = ($MasterProjects.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
            $backupCount = ($BackupProjects.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
            Write-Verbose "Project discovery complete. Found $masterCount Master and $backupCount Backup projects"
            Write-PSmmLog -Level INFO -Context 'Get-PSmmProjects' `
                -Message "Registry updated: $masterCount Master, $backupCount Backup projects" -File
        }
        else {
            # No changes; avoid noisy INFO logs and unnecessary registry overwrites
            $masterCount = ($MasterProjects.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
            $backupCount = ($BackupProjects.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
            Write-Verbose "Project discovery complete with no registry changes. Found $masterCount Master and $backupCount Backup projects"
            Write-PSmmLog -Level DEBUG -Context 'Get-PSmmProjects' `
                -Message 'No project changes detected; registry not updated' -File
        }

        # Create the final hashtable to return
        $Projects = @{
            Master = $MasterProjects
            Backup = $BackupProjects
        }

        return $Projects
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Get-PSmmProjects' `
            -Message "Failed to retrieve projects: $_" -ErrorRecord $_ -File
        throw
    }
}

<#
.SYNOPSIS
    Helper function to retrieve projects from a specific drive.

.DESCRIPTION
    Internal function that scans a single drive for project folders and adds them
    to the projects collection. Also tracks directory modification times for cache invalidation.

.PARAMETER Disk
    The disk object containing drive information.

.PARAMETER StorageGroup
    The storage group number (1, 2, etc.).

.PARAMETER BackupId
    The backup ID if this is a backup drive (optional).

.PARAMETER DriveType
    The type of drive (Master or Backup).

.PARAMETER Projects
    The hashtable to add discovered projects to.

.PARAMETER ProjectDirs
    Hashtable tracking last write times of Projects directories for cache invalidation.

    [CmdletBinding()]
    Hashtable containing updated Projects and ProjectDirs tracking data.
#>
function Get-ProjectsFromDrive {
    <#
        Internal drive scan helper. Returns updated Projects/ProjectDirs hashtables.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [object] $Disk,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $StorageGroup,
        [Parameter()] [string] $BackupId = '',
        [Parameter(Mandatory)] [ValidateSet('Master', 'Backup')] [string] $DriveType,
        [Parameter(Mandatory)] [hashtable] $Projects,
        [Parameter(Mandatory)] [hashtable] $ProjectDirs,
        [Parameter(Mandatory)] [object] $Config,
        [Parameter(Mandatory)] $FileSystem
    )

    function Test-MapHasKey([object]$Map, [string]$Key) {
        if ($null -eq $Map -or [string]::IsNullOrWhiteSpace($Key)) {
            return $false
        }

        if ($Map -is [System.Collections.IDictionary]) {
            $hasKey = $false
            try { $hasKey = [bool]$Map.ContainsKey($Key) } catch { $hasKey = $false }
            if (-not $hasKey) {
                try { $hasKey = [bool]$Map.Contains($Key) } catch { $hasKey = $false }
            }
            if (-not $hasKey) {
                try {
                    foreach ($k in $Map.Keys) {
                        if ($k -eq $Key) { $hasKey = $true; break }
                    }
                }
                catch { $hasKey = $false }
            }
            return $hasKey
        }

        if (Get-Command -Name Test-PSmmProjectsConfigMember -ErrorAction SilentlyContinue) {
            return (Test-PSmmProjectsConfigMember -Object $Map -Name $Key)
        }

        return ($null -ne (Get-PSmmProjectsConfigMemberValue -Object $Map -Name $Key))
    }

    # Derive an error key to optionally skip scanning if prior errors recorded
    $errorKey = if ($DriveType -eq 'Master') { "Master_${StorageGroup}" } else { "Backup_${StorageGroup}_${BackupId}" }

    # Safely honor internal storage error flags when present
    $internalErrorMessages = Get-PSmmProjectsConfigMemberValue -Object $Config -Name 'InternalErrorMessages'
    $uiErrorCatalogType = 'UiErrorCatalog' -as [type]
    if (-not $uiErrorCatalogType) {
        throw 'Unable to resolve type [UiErrorCatalog]. Ensure PSmm is loaded before PSmm.Projects.'
    }

    $errorCatalog = $uiErrorCatalogType::FromObject($internalErrorMessages)
    $storageErrorMap = $errorCatalog.Storage

    if ($null -ne $storageErrorMap -and (Test-MapHasKey -Map $storageErrorMap -Key $errorKey)) {
        Write-Verbose "Skipping $DriveType drive '$($Disk.Label)' - has error flag"
        return @{ Projects = $Projects; ProjectDirs = $ProjectDirs }
    }

    # Skip if disk doesn't have a drive letter (not mounted)
    if ([string]::IsNullOrWhiteSpace($Disk.DriveLetter)) {
        Write-Verbose "Skipping $DriveType drive '$($Disk.Label)' - no drive letter assigned"
        return @{
            Projects = $Projects
            ProjectDirs = $ProjectDirs
        }
    }

    $skipDriveGuard = [string]::Equals($env:MEDIA_MANAGER_TEST_MODE, '1', [System.StringComparison]::OrdinalIgnoreCase)

    # Verify the drive actually exists before trying to access it unless test mode overrides
    if (-not $skipDriveGuard -and -not (Test-DriveRootPath -DriveLetter $Disk.DriveLetter -FileSystem $FileSystem)) {
        Write-Verbose "Skipping $DriveType drive '$($Disk.Label)' ($($Disk.DriveLetter)) - drive not accessible or not mounted"
        if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
            Write-PSmmLog -Level WARNING -Context 'Get-ProjectsFromDrive' `
                -Message "Drive $($Disk.DriveLetter) ($($Disk.Label)) is not accessible or not mounted" -File
        }
        return @{
            Projects = $Projects
            ProjectDirs = $ProjectDirs
        }
    }

    # Get detailed storage drive information for enrichment
    $storageDriveInfo = Get-StorageDrive |
        Where-Object { $_.SerialNumber -eq $Disk.SerialNumber } |
        Select-Object -First 1

    # Check if Projects folder exists on this drive
    $projectsPath = Join-Path -Path $Disk.DriveLetter -ChildPath 'Projects'

    $projectsPathExists = $false
    if ($null -ne $FileSystem) {
        try {
            $projectsPathExists = [bool]$FileSystem.TestPath($projectsPath)
        }
        catch {
            $projectsPathExists = Test-Path -Path $projectsPath -ErrorAction SilentlyContinue
        }
    }
    else {
        $projectsPathExists = Test-Path -Path $projectsPath -ErrorAction SilentlyContinue
    }

    if ($projectsPathExists) {
        try {
            # Track the Projects directory's last write time for cache invalidation
            $projectsDirInfo = $null
            if ($null -ne $FileSystem) {
                try {
                    $projectsDirInfo = $FileSystem.GetItemProperty($projectsPath)
                }
                catch {
                    $projectsDirInfo = Get-Item -Path $projectsPath
                }
            }
            else {
                $projectsDirInfo = Get-Item -Path $projectsPath
            }

            $cacheKey = "$($Disk.SerialNumber)_Projects"
            $ProjectDirs[$cacheKey] = $projectsDirInfo.LastWriteTime
            Write-Verbose "Tracking $DriveType drive '$($Disk.Label)' Projects directory (LastWriteTime: $($projectsDirInfo.LastWriteTime))"

            # Ensure _GLOBAL_ project exists with Assets folder
            Initialize-GlobalProject -ProjectsPath $projectsPath -Config $Config -FileSystem $FileSystem

            $projectFolders = $null
            if ($null -ne $FileSystem) {
                try {
                    $projectFolders = $FileSystem.GetChildItem($projectsPath, $null, 'Directory')
                }
                catch {
                    $projectFolders = Get-ChildItem -Path $projectsPath -Directory
                }
            }
            else {
                $projectFolders = Get-ChildItem -Path $projectsPath -Directory
            }

            # Initialize array for this drive label if it doesn't exist
            if (-not $Projects.ContainsKey($Disk.Label)) {
                $Projects[$Disk.Label] = @()
            }

            $projectCount = 0
            foreach ($folder in $projectFolders) {
                # Skip the _GLOBAL_ project
                if ($folder.Name -eq '_GLOBAL_') {
                    continue
                }

                $Projects[$Disk.Label] += [PSCustomObject]@{
                    Name = $folder.Name
                    Path = $folder.FullName
                    Drive = $Disk.DriveLetter
                    Label = $Disk.Label
                    SerialNumber = $Disk.SerialNumber
                    StorageGroup = $StorageGroup
                    DriveType = $DriveType
                    BackupId = $BackupId
                    # Additional storage drive metadata
                    Manufacturer = if ($storageDriveInfo) { $storageDriveInfo.Manufacturer } else { 'N/A' }
                    Model = if ($storageDriveInfo) { $storageDriveInfo.Model } else { 'N/A' }
                    FileSystem = if ($storageDriveInfo) { $storageDriveInfo.FileSystem } else { 'N/A' }
                    PartitionKind = if ($storageDriveInfo) { $storageDriveInfo.PartitionKind } else { 'N/A' }
                    TotalSpace = if ($storageDriveInfo) { $storageDriveInfo.TotalSpace } else { 0 }
                    FreeSpace = if ($storageDriveInfo) { $storageDriveInfo.FreeSpace } else { 0 }
                    UsedSpace = if ($storageDriveInfo) { $storageDriveInfo.UsedSpace } else { 0 }
                    HealthStatus = if ($storageDriveInfo) { $storageDriveInfo.HealthStatus } else { 'Unknown' }
                }
                $projectCount++
            }

            # If no projects were found (empty folder or only _GLOBAL_), add a placeholder
            if ($projectCount -eq 0) {
                $Projects[$Disk.Label] += [PSCustomObject]@{
                    Name = ''
                    Path = ''
                    Drive = $Disk.DriveLetter
                    Label = $Disk.Label
                    SerialNumber = $Disk.SerialNumber
                    StorageGroup = $StorageGroup
                    DriveType = $DriveType
                    BackupId = $BackupId
                    # Additional storage drive metadata
                    Manufacturer = if ($storageDriveInfo) { $storageDriveInfo.Manufacturer } else { 'N/A' }
                    Model = if ($storageDriveInfo) { $storageDriveInfo.Model } else { 'N/A' }
                    FileSystem = if ($storageDriveInfo) { $storageDriveInfo.FileSystem } else { 'N/A' }
                    PartitionKind = if ($storageDriveInfo) { $storageDriveInfo.PartitionKind } else { 'N/A' }
                    TotalSpace = if ($storageDriveInfo) { $storageDriveInfo.TotalSpace } else { 0 }
                    FreeSpace = if ($storageDriveInfo) { $storageDriveInfo.FreeSpace } else { 0 }
                    UsedSpace = if ($storageDriveInfo) { $storageDriveInfo.UsedSpace } else { 0 }
                    HealthStatus = if ($storageDriveInfo) { $storageDriveInfo.HealthStatus } else { 'Unknown' }
                }
            }

            Write-Verbose "Found $projectCount project(s) on $DriveType drive '$($Disk.Label)' ($($Disk.DriveLetter))"
        }
        catch {
            $errorMsg = "Could not access projects on $DriveType drive $($Disk.DriveLetter) ($($Disk.Label))"
            if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level WARNING -Context 'Get-ProjectsFromDrive' `
                    -Message $errorMsg -ErrorRecord $_ -File
            }
        }
    }
    else {
        Write-Verbose "Projects folder not found on $DriveType drive $($Disk.DriveLetter) ($($Disk.Label))"
        if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
            Write-PSmmLog -Level WARNING -Context 'Get-ProjectsFromDrive' `
                -Message "Projects folder not found on $DriveType drive $($Disk.DriveLetter) ($($Disk.Label))" -File
        }

        # Attempt to create Projects folder with confirmation
        try {
            if ($canNewItem) {
                $null = $FileSystem.NewItem($projectsPath, 'Directory')
            }
            else {
                throw [ValidationException]::new("FileSystem service is required to create Projects folder", "FileSystem service", $projectsPath)
            }

            if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level SUCCESS -Context 'Get-ProjectsFromDrive' `
                    -Message "Created Projects folder on $DriveType drive $($Disk.DriveLetter) ($($Disk.Label))" -File
            }

            # Track the newly created Projects directory
            $projectsDirInfo = if ($canGetItemProp) {
                $FileSystem.GetItemProperty($projectsPath)
            }
            else {
                Get-Item -Path $projectsPath
            }

            $cacheKey = "$($Disk.SerialNumber)_Projects"
            $ProjectDirs[$cacheKey] = $projectsDirInfo.LastWriteTime

            # Initialize _GLOBAL_ project with Assets folder
            Initialize-GlobalProject -ProjectsPath $projectsPath -Config $Config -FileSystem $FileSystem

            # Initialize array for this drive label if it doesn't exist
            if (-not $Projects.ContainsKey($Disk.Label)) {
                $Projects[$Disk.Label] = @()
            }

            # Add placeholder since folder is now empty
            $Projects[$Disk.Label] += [PSCustomObject]@{
                Name = ''
                Path = ''
                Drive = $Disk.DriveLetter
                Label = $Disk.Label
                SerialNumber = $Disk.SerialNumber
                # Additional storage drive metadata
                Manufacturer = if ($storageDriveInfo) { $storageDriveInfo.Manufacturer } else { 'N/A' }
                Model = if ($storageDriveInfo) { $storageDriveInfo.Model } else { 'N/A' }
                FileSystem = if ($storageDriveInfo) { $storageDriveInfo.FileSystem } else { 'N/A' }
                PartitionKind = if ($storageDriveInfo) { $storageDriveInfo.PartitionKind } else { 'N/A' }
                TotalSpace = if ($storageDriveInfo) { $storageDriveInfo.TotalSpace } else { 0 }
                FreeSpace = if ($storageDriveInfo) { $storageDriveInfo.FreeSpace } else { 0 }
                UsedSpace = if ($storageDriveInfo) { $storageDriveInfo.UsedSpace } else { 0 }
                HealthStatus = if ($storageDriveInfo) { $storageDriveInfo.HealthStatus } else { 'Unknown' }
            }
        }
        catch {
            if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level DEBUG -Context 'Get-ProjectsFromDrive' `
                    -Message "Projects folder creation declined or failed on $DriveType drive $($Disk.DriveLetter) ($($Disk.Label))" -File
            }

            # Add placeholder entry for drive without projects folder
            if (-not $Projects.ContainsKey($Disk.Label)) {
                $Projects[$Disk.Label] = @()
            }

            $Projects[$Disk.Label] += [PSCustomObject]@{
                Name = ''
                Path = ''
                Drive = $Disk.DriveLetter
                Label = $Disk.Label
                SerialNumber = $Disk.SerialNumber
                # Additional storage drive metadata
                Manufacturer = if ($storageDriveInfo) { $storageDriveInfo.Manufacturer } else { 'N/A' }
                Model = if ($storageDriveInfo) { $storageDriveInfo.Model } else { 'N/A' }
                FileSystem = if ($storageDriveInfo) { $storageDriveInfo.FileSystem } else { 'N/A' }
                PartitionKind = if ($storageDriveInfo) { $storageDriveInfo.PartitionKind } else { 'N/A' }
                TotalSpace = if ($storageDriveInfo) { $storageDriveInfo.TotalSpace } else { 0 }
                FreeSpace = if ($storageDriveInfo) { $storageDriveInfo.FreeSpace } else { 0 }
                UsedSpace = if ($storageDriveInfo) { $storageDriveInfo.UsedSpace } else { 0 }
                HealthStatus = if ($storageDriveInfo) { $storageDriveInfo.HealthStatus } else { 'Unknown' }
            }
        }
    }

    return @{
        Projects = $Projects
        ProjectDirs = $ProjectDirs
    }
}

function Test-DriveRootPath {
    [CmdletBinding()]
    param(
        [Parameter()][string]$DriveLetter,
        [Parameter()][object]$FileSystem
    )

    if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
        return $false
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add($DriveLetter)

    if ($DriveLetter -match '^[A-Za-z]:$') {
        $candidates.Add("$DriveLetter\\")
    }
    elseif ($DriveLetter -match '^[A-Za-z]:\\$') {
        $candidates.Add($DriveLetter.TrimEnd('\'))
    }

    if ($null -ne $FileSystem) {
        $fileSystemWorks = $true
        foreach ($candidate in $candidates) {
            try {
                if ($FileSystem.TestPath($candidate)) {
                    return $true
                }
            }
            catch {
                $fileSystemWorks = $false
                break
            }
        }

        if ($fileSystemWorks) {
            return $false
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -Path $candidate -ErrorAction SilentlyContinue) {
            return $true
        }
    }

    return $false
}

<#
.SYNOPSIS
    Helper function to ensure _GLOBAL_ project exists with required folder structure.

.DESCRIPTION
    Internal function that creates the _GLOBAL_ project folder and its Assets subfolder
    if they don't exist. This provides a consistent location for shared assets across projects.

.PARAMETER ProjectsPath
    The full path to the Projects folder on the drive.

.NOTES
    Creates: Projects\_GLOBAL_\Libraries\Assets
#>
function Initialize-GlobalProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectsPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem
    )

    try {
        # Define _GLOBAL_ project path
        $GlobalProjectPath = Join-Path -Path $ProjectsPath -ChildPath '_GLOBAL_'

        # Create _GLOBAL_ project folder if it doesn't exist
        $globalProjectExists = $false
        try {
            $globalProjectExists = [bool]$FileSystem.TestPath($GlobalProjectPath)
        }
        catch {
            $globalProjectExists = Test-Path -Path $GlobalProjectPath -ErrorAction SilentlyContinue
        }

        if (-not $globalProjectExists) {
            Write-Verbose "Creating _GLOBAL_ project folder: $GlobalProjectPath"
            $null = $FileSystem.NewItem($GlobalProjectPath, 'Directory')
            if (Get-Command -Name Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level INFO -Context 'Initialize-GlobalProject' `
                    -Message "Created _GLOBAL_ project folder: $GlobalProjectPath" -File
            }
        }

        # Define Assets folder path using AppConfiguration (or legacy shapes)
        $projectsConfig = Get-PSmmProjectsConfigMemberValue -Object $Config -Name 'Projects'
        $pathsSource = if ($null -ne $projectsConfig) { Get-PSmmProjectsConfigMemberValue -Object $projectsConfig -Name 'Paths' } else { $null }
        $projectsPaths = if ($null -ne $pathsSource) {
            [ProjectsPathsConfig]::FromObject($pathsSource)
        }
        else {
            [ProjectsPathsConfig]::new()
        }

        if (-not [string]::IsNullOrWhiteSpace($projectsPaths.Assets)) {
            $AssetsRelativePath = $projectsPaths.Assets
        }
        else {
            # Use default path if configuration not found
            $AssetsRelativePath = 'Libraries\Assets'
            Write-Verbose "Using default Assets path: $AssetsRelativePath"
        }

        $AssetsFullPath = Join-Path -Path $GlobalProjectPath -ChildPath $AssetsRelativePath

        # Create Assets folder if it doesn't exist
        $assetsExists = $false
        try {
            $assetsExists = [bool]$FileSystem.TestPath($AssetsFullPath)
        }
        catch {
            $assetsExists = Test-Path -Path $AssetsFullPath -ErrorAction SilentlyContinue
        }

        if (-not $assetsExists) {
            Write-Verbose "Creating Assets folder: $AssetsFullPath"

            try {
                $null = $FileSystem.NewItem($AssetsFullPath, 'Directory')
            }
            catch {
                throw [ValidationException]::new("FileSystem service is required to create Assets folder", "FileSystem service", $AssetsFullPath)
            }

            if (Get-Command -Name Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level INFO -Context 'Initialize-GlobalProject' `
                    -Message "Created Assets folder: $AssetsFullPath" -File
            }
        }
        else {
            Write-Verbose "_GLOBAL_ project and Assets folder already exist"
        }
    }
    catch {
        if (Get-Command -Name Write-PSmmLog -ErrorAction SilentlyContinue) {
            Write-PSmmLog -Level ERROR -Context 'Initialize-GlobalProject' `
                -Message "Failed to initialize _GLOBAL_ project: $_" -ErrorRecord $_ -File
        }
        else {
            Write-Verbose "[Initialize-GlobalProject] Failed to initialize _GLOBAL_ project: $_"
        }
        # Don't throw - this shouldn't block project discovery
    }
}
