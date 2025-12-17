#Requires -Version 7.5.4
Set-StrictMode -Version Latest

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

    .PARAMETER ServiceContainer
        ServiceContainer instance providing access to FileSystem service.
        If omitted, creates a new FileSystemService instance or falls back to cmdlets.

    .EXAMPLE
        $projects = Get-PSmmProjects -Config $appConfig -ServiceContainer $ServiceContainer
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

        BREAKING CHANGE (v0.2.0): Replaced -FileSystem parameter with -ServiceContainer parameter.
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

        [Parameter()]
        $ServiceContainer = $null
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
                # fall through
            }

            try {
                if ($Object.Contains($Name)) {
                    return $Object[$Name]
                }
            }
            catch {
                # fall through
            }

            try {
                foreach ($k in $Object.Keys) {
                    if ($k -eq $Name) {
                        return $Object[$k]
                    }
                }
            }
            catch {
                # fall through
            }

            return $null
        }

        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) {
            return $p.Value
        }

        return $null
    }

    function Set-ConfigMemberValue([object]$Object, [string]$Name, [object]$Value) {
        if ($null -eq $Object) {
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
                # fall through
            }

            try {
                if ($map.Contains($key)) { return $map[$key] }
            }
            catch {
                # fall through
            }

            try {
                foreach ($k in $map.Keys) {
                    if ($k -eq $key) {
                        return $map[$k]
                    }
                }
            }
            catch {
                # fall through
            }
            return $null
        }

        try {
            return $map[$key]
        }
        catch {
        }

        $p = $map.PSObject.Properties[$key]
        if ($null -ne $p) {
            return $p.Value
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
        foreach ($p in $value.PSObject.Properties) {
            $ht2[[string]$p.Name] = $p.Value
        }
        return $ht2
    }

    function Normalize-StorageMap([object]$storage) {
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
                $keys = @($storage.PSObject.Properties | ForEach-Object { $_.Name })
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
                    # fall back to legacy view
                }
            }

            $sg = ConvertTo-PSmmLegacyView -value $raw
            if ($null -eq $sg) { continue }

            # Normalize Backup -> Backups for legacy shapes
            if ($null -eq $sg.PSObject.Properties['Backups'] -and $null -ne $sg.PSObject.Properties['Backup']) {
                $sg | Add-Member -NotePropertyName 'Backups' -NotePropertyValue $sg.Backup -Force
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

    # Resolve FileSystem service from container or create fallback
    $FileSystem = $null
    if ($null -ne $ServiceContainer) {
        try {
            if ($ServiceContainer.PSObject.Methods.Name -contains 'Resolve') {
                $FileSystem = $ServiceContainer.Resolve('FileSystem')
            }
        }
        catch {
            Write-Verbose "Failed to resolve FileSystem from ServiceContainer: $_"
        }
    }

    # Fallback: create new FileSystemService or use cmdlets
    if ($null -eq $FileSystem) {
        try {
            $FileSystem = [FileSystemService]::new()
        }
        catch {
            Write-Verbose "FileSystemService type not available, using PowerShell cmdlets directly"
            $FileSystem = $null
        }
    }

    # Ensure Projects.Registry exists on Config
    $projectsConfig = Get-ConfigMemberValue -Object $Config -Name 'Projects'
    if ($null -eq $projectsConfig) {
        $projectsConfig = [ProjectsConfig]::FromObject($null)
        Set-ConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig
    }
    elseif ($projectsConfig -isnot [ProjectsConfig]) {
        $projectsConfig = [ProjectsConfig]::FromObject($projectsConfig)
        Set-ConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig
    }

    $registry = Get-ConfigMemberValue -Object $projectsConfig -Name 'Registry'
    if ($null -eq $registry) {
        $registry = [ProjectsRegistryCache]::new()
        Set-ConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value $registry
    }
    else {
        # Normalize legacy hashtable/object shapes into the typed cache model
        $registry = [ProjectsRegistryCache]::FromObject($registry)
        Set-ConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value $registry
    }

    try {
        $isTestMode = [string]::Equals($env:MEDIA_MANAGER_TEST_MODE, '1', [System.StringComparison]::OrdinalIgnoreCase)

        # Local reference to registry
        $registry = Get-ConfigMemberValue -Object $projectsConfig -Name 'Registry'

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
                $storageSource = Get-ConfigMemberValue -Object $Config -Name 'Storage'
                $Storage = Normalize-StorageMap -storage $storageSource

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
        $storageSource = Get-ConfigMemberValue -Object $Config -Name 'Storage'
        $Storage = Normalize-StorageMap -storage $storageSource

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
        function Get-FlattenedProjectsFromByLabel {
            param([Parameter(Mandatory)][hashtable]$ByLabel)
            $result = @()
            foreach ($label in ($ByLabel.Keys | Sort-Object)) {
                $items = $ByLabel[$label]
                if ($null -eq $items) { continue }
                foreach ($item in $items) {
                    # Use a stable identity key capturing moves/renames/drives
                    $driveType = if ($item.PSObject.Properties.Match('DriveType').Count) { $item.DriveType } else { '' }
                    $backupId = if ($item.PSObject.Properties.Match('BackupId').Count) { $item.BackupId } else { '' }
                    $serial = if ($item.PSObject.Properties.Match('SerialNumber').Count) { $item.SerialNumber } else { '' }
                    $name = if ($item.PSObject.Properties.Match('Name').Count) { $item.Name } else { '' }
                    $path = if ($item.PSObject.Properties.Match('Path').Count) { $item.Path } else { '' }
                    $labelVal = if ($item.PSObject.Properties.Match('Label').Count) { $item.Label } else { $label }
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
            elseif ($null -ne $Object -and $Object.PSObject.Properties.Match($Name).Count -gt 0) {
                return $Object.$Name
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
                    $driveType = if ($item.PSObject.Properties.Match('DriveType').Count) { $item.DriveType } else { '' }
                    $backupId = if ($item.PSObject.Properties.Match('BackupId').Count) { $item.BackupId } else { '' }
                    $serial = if ($item.PSObject.Properties.Match('SerialNumber').Count) { $item.SerialNumber } else { '' }
                    $name = if ($item.PSObject.Properties.Match('Name').Count) { $item.Name } else { '' }
                    $path = if ($item.PSObject.Properties.Match('Path').Count) { $item.Path } else { '' }
                    $labelVal = if ($item.PSObject.Properties.Match('Label').Count) { $item.Label } else { $label }
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
            Set-ConfigMemberValue -Object $projectsConfig -Name 'Registry' -Value $registry
            Set-ConfigMemberValue -Object $Config -Name 'Projects' -Value $projectsConfig

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
                # fall through
            }

            try {
                if ($Object.Contains($Name)) {
                    return $Object[$Name]
                }
            }
            catch {
                # fall through
            }

            try {
                foreach ($k in $Object.Keys) {
                    if ($k -eq $Name) {
                        return $Object[$k]
                    }
                }
            }
            catch {
                # fall through
            }

            return $null
        }

        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) {
            return $p.Value
        }

        return $null
    }

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

        $p = $Map.PSObject.Properties[$Key]
        return ($null -ne $p)
    }

    # Derive an error key to optionally skip scanning if prior errors recorded
    $errorKey = if ($DriveType -eq 'Master') { "Master_${StorageGroup}" } else { "Backup_${StorageGroup}_${BackupId}" }

    # Safely honor internal storage error flags when present
    $internalErrorMessages = Get-ConfigMemberValue -Object $Config -Name 'InternalErrorMessages'
    $errorCatalog = [UiErrorCatalog]::FromObject($internalErrorMessages)
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
        Write-PSmmLog -Level WARNING -Context 'Get-ProjectsFromDrive' `
            -Message "Drive $($Disk.DriveLetter) ($($Disk.Label)) is not accessible or not mounted" -File
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

    # Fallback capability detection for FileSystem abstraction
    $canTestPath = $FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'TestPath')
    $canGetItemProp = $FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'GetItemProperty')
    $canGetChildItem = $FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'GetChildItem')
    $canNewItem = $FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'NewItem')

    $projectsPathExists = if ($canTestPath) {
        try { $FileSystem.TestPath($projectsPath) } catch { $false }
    }
    else {
        Test-Path -Path $projectsPath -ErrorAction SilentlyContinue
    }

    if ($projectsPathExists) {
        try {
            # Track the Projects directory's last write time for cache invalidation
            $projectsDirInfo = if ($canGetItemProp) {
                $FileSystem.GetItemProperty($projectsPath)
            }
            else {
                Get-Item -Path $projectsPath
            }

            $cacheKey = "$($Disk.SerialNumber)_Projects"
            $ProjectDirs[$cacheKey] = $projectsDirInfo.LastWriteTime
            Write-Verbose "Tracking $DriveType drive '$($Disk.Label)' Projects directory (LastWriteTime: $($projectsDirInfo.LastWriteTime))"

            # Ensure _GLOBAL_ project exists with Assets folder
            Initialize-GlobalProject -ProjectsPath $projectsPath -Config $Config -FileSystem $FileSystem

            $projectFolders = if ($canGetChildItem) {
                $FileSystem.GetChildItem($projectsPath, $null, 'Directory')
            }
            else {
                Get-ChildItem -Path $projectsPath -Directory
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
            Write-PSmmLog -Level WARNING -Context 'Get-ProjectsFromDrive' `
                -Message $errorMsg -ErrorRecord $_ -File
        }
    }
    else {
        Write-Verbose "Projects folder not found on $DriveType drive $($Disk.DriveLetter) ($($Disk.Label))"
        Write-PSmmLog -Level WARNING -Context 'Get-ProjectsFromDrive' `
            -Message "Projects folder not found on $DriveType drive $($Disk.DriveLetter) ($($Disk.Label))" -File

        # Attempt to create Projects folder with confirmation
        try {
            if ($canNewItem) {
                $null = $FileSystem.NewItem($projectsPath, 'Directory')
            }
            else {
                throw [ValidationException]::new("FileSystem service is required to create Projects folder", "FileSystem service", $projectsPath)
            }

            Write-PSmmLog -Level SUCCESS -Context 'Get-ProjectsFromDrive' `
                -Message "Created Projects folder on $DriveType drive $($Disk.DriveLetter) ($($Disk.Label))" -File

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
            Write-PSmmLog -Level DEBUG -Context 'Get-ProjectsFromDrive' `
                -Message "Projects folder creation declined or failed on $DriveType drive $($Disk.DriveLetter) ($($Disk.Label))" -File

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

    $supportsTestPath = $FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'TestPath')
    if ($supportsTestPath) {
        foreach ($candidate in $candidates) {
            try {
                if ($FileSystem.TestPath($candidate)) {
                    return $true
                }
            }
            catch {
                continue
            }
        }
        return $false
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
                # fall through
            }

            try {
                if ($Object.Contains($Name)) {
                    return $Object[$Name]
                }
            }
            catch {
                # fall through
            }

            try {
                foreach ($k in $Object.Keys) {
                    if ($k -eq $Name) {
                        return $Object[$k]
                    }
                }
            }
            catch {
                # fall through
            }

            return $null
        }

        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) {
            return $p.Value
        }

        return $null
    }

    try {
        # Define _GLOBAL_ project path
        $GlobalProjectPath = Join-Path -Path $ProjectsPath -ChildPath '_GLOBAL_'

        # Create _GLOBAL_ project folder if it doesn't exist
        if (-not $FileSystem.TestPath($GlobalProjectPath)) {
            Write-Verbose "Creating _GLOBAL_ project folder: $GlobalProjectPath"
            $null = $FileSystem.NewItem($GlobalProjectPath, 'Directory')
            Write-PSmmLog -Level INFO -Context 'Initialize-GlobalProject' `
                -Message "Created _GLOBAL_ project folder: $GlobalProjectPath" -File
        }

        # Define Assets folder path using AppConfiguration (or legacy shapes)
        $projectsConfig = Get-ConfigMemberValue -Object $Config -Name 'Projects'
        $pathsSource = if ($null -ne $projectsConfig) { Get-ConfigMemberValue -Object $projectsConfig -Name 'Paths' } else { $null }
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
        if (-not $FileSystem.TestPath($AssetsFullPath)) {
            Write-Verbose "Creating Assets folder: $AssetsFullPath"

            $canNewItem = $FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'NewItem')
            if ($canNewItem) {
                $null = $FileSystem.NewItem($AssetsFullPath, 'Directory')
            }
            else {
                throw [ValidationException]::new("FileSystem service is required to create Assets folder", "FileSystem service", $AssetsFullPath)
            }

            Write-PSmmLog -Level INFO -Context 'Initialize-GlobalProject' `
                -Message "Created Assets folder: $AssetsFullPath" -File
        }
        else {
            Write-Verbose "_GLOBAL_ project and Assets folder already exist"
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Initialize-GlobalProject' `
            -Message "Failed to initialize _GLOBAL_ project: $_" -ErrorRecord $_ -File
        # Don't throw - this shouldn't block project discovery
    }
}
