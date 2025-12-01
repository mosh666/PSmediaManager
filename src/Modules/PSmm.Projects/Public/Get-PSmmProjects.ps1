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

        .EXAMPLE
            $projects = Get-PSmmProjects -Config $appConfig -Force
            # Forces a full rescan, ignoring cached data

    .PARAMETER Force
        Forces a full rescan of all drives, bypassing the registry cache.

    .PARAMETER FileSystem
        File system service for testing. Defaults to FileSystemService instance.

    .EXAMPLE
        $projects = Get-PSmmProjects -Config $appConfig
        # Returns: @{ Master = @{ DriveLabel = @(ProjectObjects...) }; Backup = @{ ... } }

    .EXAMPLE
        $projects = Get-PSmmProjects -Run $Run -Force
        # (Legacy) Forces a full rescan, ignoring cached data

    .OUTPUTS
        Hashtable containing Master and Backup projects, organized by drive label.
        Each project object contains: Name, Path, Drive, Label, SerialNumber

    .NOTES
        Projects are expected to be in a 'Projects' folder at the root of each drive.
        The _GLOBAL_ project is automatically excluded from results.
        Registry cache includes LastScanned timestamp for cache invalidation.
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
        $FileSystem = $null
    )

    # Ensure Projects.Registry exists on Config
    if (-not $Config.Projects.ContainsKey('Registry') -or $null -eq $Config.Projects.Registry) {
        $Config.Projects.Registry = @{
            Master = @{}
            Backup = @{}
            LastScanned = [datetime]::MinValue
            ProjectDirs = @{}
        }
    }

    try {
        # Use default FileSystemService if not provided
        # Create it here after the module is fully loaded to avoid type errors
        if ($null -eq $FileSystem) {
            try {
                $FileSystem = [FileSystemService]::new()
            }
            catch {
                # If FileSystemService type isn't available, create a wrapper using PowerShell cmdlets
                Write-Verbose "FileSystemService type not available, using PowerShell cmdlets directly"
                $FileSystem = $null  # We'll handle this with direct cmdlet calls
            }
        }
        $isTestMode = [string]::Equals($env:MEDIA_MANAGER_TEST_MODE, '1', [System.StringComparison]::OrdinalIgnoreCase)

        # Local reference to registry
        $registry = $Config.Projects.Registry

        # Disk-based cache has been removed; rely on in-memory registry and full scan

        # Check if we should use cached data (in-memory registry)
        $UseCache = -not $Force.IsPresent
        if ($UseCache -and $registry.LastScanned -ne [datetime]::MinValue) {
            Write-Verbose 'Checking if registry cache is still valid...'

            # Check if any Projects directories have been modified since last scan
            # Support both FileSystem abstraction and direct PowerShell cmdlets
            $canTestPath = $FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'TestPath')
            $canGetItemProp = $FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'GetItemProperty')
            $CacheInvalid = $false
            $Storage = $Config.Storage

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
                            $projectsPathExists = if ($canTestPath) { try { $FileSystem.TestPath($ProjectsPath) } catch { $false } } else { Test-Path -Path $ProjectsPath -ErrorAction SilentlyContinue }
                            if ($projectsPathExists) {
                                $ProjectsDirInfo = if ($canGetItemProp) { $FileSystem.GetItemProperty($ProjectsPath) } else { Get-Item -Path $ProjectsPath }
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
                    }

                    # Check Backup drives
                    if ($null -ne $sg.Backups -and $sg.Backups.Count -gt 0) {
                        foreach ($backupId in ($sg.Backups.Keys | Sort-Object)) {
                            $BackupDisk = $sg.Backups[$backupId]
                            $backupExists = $isTestMode -or (Test-DriveRootPath -DriveLetter $BackupDisk.DriveLetter -FileSystem $FileSystem)
                            if ($backupExists) {
                                $ProjectsPath = Join-Path -Path $BackupDisk.DriveLetter -ChildPath 'Projects'
                                $projectsPathExists = if ($canTestPath) { try { $FileSystem.TestPath($ProjectsPath) } catch { $false } } else { Test-Path -Path $ProjectsPath -ErrorAction SilentlyContinue }
                                if ($projectsPathExists) {
                                    $ProjectsDirInfo = if ($canGetItemProp) { $FileSystem.GetItemProperty($ProjectsPath) } else { Get-Item -Path $ProjectsPath }
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
                        }

                        if ($CacheInvalid) { break }
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

                    # Prefer helper that handles both hashtable and object shapes
                    if ($entry -is [hashtable] -and $entry.ContainsKey('Projects')) {
                        $projectsArray = $entry['Projects']
                    }
                    elseif ($null -ne $entry -and $entry.PSObject.Properties.Match('Projects').Count -gt 0) {
                        $projectsArray = $entry.Projects
                    }
                    else {
                        # Fallback: if entry already is an array of projects, use it
                        $projectsArray = $entry
                    }

                    # Ensure $projectsArray is an array
                    if ($null -eq $projectsArray) { $projectsArray = @() }
                    elseif (-not ($projectsArray -is [System.Collections.IEnumerable]) -or ($projectsArray -is [string])) { $projectsArray = @($projectsArray) }

                    $cachedMaster[$label] = $projectsArray

                }

                $cachedBackup = @{}
                foreach ($label in ($registry.Backup.Keys | Sort-Object)) {
                    $entry = $registry.Backup[$label]

                    if ($entry -is [hashtable] -and $entry.ContainsKey('Projects')) {
                        $projectsArray = $entry['Projects']
                    }
                    elseif ($null -ne $entry -and $entry.PSObject.Properties.Match('Projects').Count -gt 0) {
                        $projectsArray = $entry.Projects
                    }
                    else {
                        $projectsArray = $entry
                    }

                    if ($null -eq $projectsArray) { $projectsArray = @() }
                    elseif (-not ($projectsArray -is [System.Collections.IEnumerable]) -or ($projectsArray -is [string])) { $projectsArray = @($projectsArray) }

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
        $Storage = $Config.Storage

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
                $out[$label] = @{
                    BackupId = $(if ($first.PSObject.Properties.Match('BackupId').Count) { $first.BackupId } else { '' })
                    Drive = $(if ($first.PSObject.Properties.Match('Drive').Count) { $first.Drive } else { '' })
                    DriveType = $(if ($first.PSObject.Properties.Match('DriveType').Count) { $first.DriveType } else { '' })
                    FileSystem = $(if ($first.PSObject.Properties.Match('FileSystem').Count) { $first.FileSystem } else { '' })
                    FreeSpace = $(if ($first.PSObject.Properties.Match('FreeSpace').Count) { [double]$first.FreeSpace } else { 0 })
                    HealthStatus = $(if ($first.PSObject.Properties.Match('HealthStatus').Count) { $first.HealthStatus } else { 'Unknown' })
                    Label = $(if ($first.PSObject.Properties.Match('Label').Count) { $first.Label } else { $label })
                    Manufacturer = $(if ($first.PSObject.Properties.Match('Manufacturer').Count) { $first.Manufacturer } else { '' })
                    Model = $(if ($first.PSObject.Properties.Match('Model').Count) { $first.Model } else { '' })
                    Name = $(if ($first.PSObject.Properties.Match('Name').Count) { $first.Name } else { '' })
                    PartitionKind = $(if ($first.PSObject.Properties.Match('PartitionKind').Count) { $first.PartitionKind } else { '' })
                    Path = $(if ($first.PSObject.Properties.Match('Path').Count) { $first.Path } else { '' })
                    SerialNumber = $(if ($first.PSObject.Properties.Match('SerialNumber').Count) { $first.SerialNumber } else { '' })
                    StorageGroup = $(if ($first.PSObject.Properties.Match('StorageGroup').Count) { $first.StorageGroup } else { '' })
                    TotalSpace = $(if ($first.PSObject.Properties.Match('TotalSpace').Count) { [double]$first.TotalSpace } else { 0 })
                    UsedSpace = $(if ($first.PSObject.Properties.Match('UsedSpace').Count) { [double]$first.UsedSpace } else { 0 })
                    # Persist full project array for accurate UI rendering when using cached registry.
                    Projects = $ProjectsByLabel[$label]
                }
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

        function Get-FlattenedProjectsFromRegistrySide {
            param([Parameter(Mandatory)][hashtable]$RegistrySide)
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
        $registry.ProjectDirs = $ProjectDirs
        $registry.LastScanned = Get-Date

        if ($registryChanged) {
            # Update the registry cache with compact summaries and persist full arrays inside
            $registry.Master = Convert-ProjectsToDriveRegistry -ProjectsByLabel $MasterProjects
            $registry.Backup = Convert-ProjectsToDriveRegistry -ProjectsByLabel $BackupProjects

            # Sync registry back to Config
            $Config.Projects.Registry = $registry

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

    # Derive an error key to optionally skip scanning if prior errors recorded
    $errorKey = if ($DriveType -eq 'Master') { "Master_${StorageGroup}" } else { "Backup_${StorageGroup}_${BackupId}" }

    # Safely honor internal storage error flags when present
    $storageErrorMap = $null
    if ($null -ne $Config.InternalErrorMessages -and `
        $Config.InternalErrorMessages.ContainsKey('Storage')) {
        $storageErrorMap = $Config.InternalErrorMessages['Storage']
    }

    if ($null -ne $storageErrorMap -and $storageErrorMap.ContainsKey($errorKey)) {
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
                throw "FileSystem service is required to create Projects folder: $projectsPath"
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

        # Define Assets folder path using AppConfiguration
        if ($Config.Projects.Paths -and $Config.Projects.Paths.Assets) {
            $AssetsRelativePath = $Config.Projects.Paths.Assets
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
                throw "FileSystem service is required to create Assets folder: $AssetsFullPath"
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
