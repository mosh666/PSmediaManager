#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Displays the PSmediaManager UI.

.DESCRIPTION
    Contains functions to display various UI components of the PSmediaManager application,
    including headers, footers, and menu options.

    Uses Write-Host for UI rendering because:
    - UI output must go directly to console, not pipeline (prevents blank line artifacts)
    - Interactive menu operations require direct host communication
    - PSAvoidUsingWriteHost is intentionally used for this purpose
#>

Set-StrictMode -Version Latest

#region ########## Helpers ##########

# Note: Build-UIRuntimeFromConfig has been removed. UI functions now work directly with AppConfiguration.

#endregion ########## Helpers ##########

#region ########## Header/Footer ##########

<#
.SYNOPSIS
    Displays the application header with optional project title.

.PARAMETER Run
    The runtime configuration hashtable.

.PARAMETER Title
    The title label to display before the project name.

.PARAMETER ProjectName
    The name of the current project to display.

.PARAMETER ShowProject
    Controls whether to display the project information. Default is $true.
    Set to $false to hide project information (e.g., in main menu).

.PARAMETER ShowStorageErrors
    Controls whether to display storage error messages. Default is $true.
    Set to $false to hide storage errors (e.g., in project menus).

.PARAMETER StorageGroupFilter
    Optional storage group filter. When specified, only errors for this storage group will be displayed.
#>
function Show-Header {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter()]
        [string]$Title = 'Project',

        [Parameter()]
        [string]$ProjectName = '',

        [Parameter()]
        [bool]$ShowProject = $true,

        [Parameter()]
        [bool]$ShowStorageErrors = $true,

        [Parameter()]
        [string]$StorageGroupFilter = $null
    )

    $displayName = [string](Get-PSmmUiConfigMemberValue -Object $Config -Name 'DisplayName')
    if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = 'PSmediaManager' }

    $appVersion = [string](Get-PSmmUiConfigMemberValue -Object $Config -Name 'AppVersion')

    $uiWidthSource = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'Width')
    $uiWidth = 80
    if ($null -ne $uiWidthSource) {
        try {
            $uiWidth = [int]$uiWidthSource
            if ($uiWidth -lt 1) { $uiWidth = 80 }
        }
        catch {
            $uiWidth = 80
        }
    }

    $fgPrimary     = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Primary')
    $fgAccent      = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Accent')
    $fgError       = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Error')
    $fgWarning     = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Warning')
    $fgNeutral4    = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Neutral4')
    $fgBackupDrive = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'BackupDrive')
    $fgMasterDrive = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'MasterDrive')

    $Columns = @(
        New-UiColumn -Text $displayName -Width '50%' -Alignment 'l' -TextColor $fgPrimary -Bold -Italic
        New-UiColumn -Text $appVersion -Width 'auto' -Alignment 'r' -TextColor $fgAccent -Italic
    )

    # PS 7.5.4+ baseline guarantees $PSSpecialChar
    $borderChar = $PSSpecialChar.SixPointStar

    Format-UI -Columns $Columns -Width $uiWidth -ColumnSeparator '' -Border $borderChar -Config $Config
    Write-PSmmHost ''

    # Display error messages if enabled
    if ($ShowStorageErrors) {
        $internalErrorsSource = Get-PSmmUiConfigMemberValue -Object $Config -Name 'InternalErrorMessages'
        $uiErrorCatalogType = 'UiErrorCatalog' -as [type]
        if (-not $uiErrorCatalogType) {
            throw 'Unable to resolve required type [UiErrorCatalog]. Ensure PSmm is loaded before PSmm.UI.'
        }

        $errorCatalog = $uiErrorCatalogType::FromObject($internalErrorsSource)
        if (-not [string]::IsNullOrWhiteSpace($StorageGroupFilter)) {
            $errorCatalog = $errorCatalog.FilterStorageGroup($StorageGroupFilter)
        }

        $ErrorMessages = Get-ErrorMessages -ErrorHashtable $errorCatalog
        if ($ErrorMessages -and @($ErrorMessages).Count -gt 0) {
            foreach ($ErrorMsg in $ErrorMessages) {
                $ErrorColumns = @(
                    New-UiColumn -Text $ErrorMsg -Width $uiWidth -Alignment 'c' -TextColor $fgError -Bold -Blink
                )
                Format-UI -Columns $ErrorColumns -Width $uiWidth -Config $Config
            }
            Write-PSmmHost ''
        }
    }

    # Display current project information if available and ShowProject is enabled
    $projects = Get-PSmmUiConfigMemberValue -Object $Config -Name 'Projects'
    $currentProjectSource = Get-PSmmUiConfigMemberValue -Object $projects -Name 'Current'
    if ($ShowProject -and $null -ne $currentProjectSource) {
        $currentProject = [ProjectCurrentConfig]::FromObject($currentProjectSource)
        if ([string]::IsNullOrWhiteSpace($currentProject.Name)) {
            return
        }
        Write-PSmmHost ''

        # Get project name
        $CurrentProjectName = $currentProject.Name

        # Build project display with folder icon
        # Use UTF-16 surrogate pairs for emoji > U+FFFF (0x1F4C1 = 📁)
        $ProjectDisplay = "$([char]::ConvertFromUtf32(0x1F4C1)) $CurrentProjectName"  # 📁 folder icon

        # Get storage disk information if available
        $DiskDisplay = ''
        $DiskColor = $fgAccent

        if ($null -ne $currentProject.StorageDrive -and -not [string]::IsNullOrWhiteSpace($currentProject.StorageDrive.Label)) {
            $storageDrive = $currentProject.StorageDrive

            # Determine drive type and icon based on label pattern
            # Use UTF-16 surrogate pairs for emoji > U+FFFF
            $driveIcon = [char]::ConvertFromUtf32(0x1F4BE)  # 💾 default storage icon

            if ($storageDrive.Label -match '-Backup-\d+$') {
                $driveIcon = [char]::ConvertFromUtf32(0x1F4C0)  # 📀 backup disc icon
                $DiskColor = $fgBackupDrive
            }
            elseif ($storageDrive.Label -notmatch '-Backup-') {
                $driveIcon = [char]::ConvertFromUtf32(0x1F4BF)  # 💿 master disc icon
                $DiskColor = $fgMasterDrive
            }

            # Build disk display string with icon
            $DiskDisplay = "$driveIcon $($storageDrive.Label) [$($storageDrive.DriveLetter)]"
        }

        # Display project info in a structured two-column layout
        if (-not [string]::IsNullOrWhiteSpace($DiskDisplay)) {
            # Two-column layout: Project on left, Disk info on right
            $ProjectMetadataColumns = @(
                New-UiColumn -Text $ProjectDisplay -Width '50%' -Alignment 'l' -TextColor $fgWarning -Bold
                New-UiColumn -Text $DiskDisplay -Width '50%' -Alignment 'r' -TextColor $DiskColor -Bold
            )
        }
        else {
            # Single column layout if no disk info
            $ProjectMetadataColumns = @(
                New-UiColumn -Text $ProjectDisplay -Width $uiWidth -Alignment 'c' -TextColor $fgWarning -Bold -Underline
            )
        }

        Format-UI -Columns $ProjectMetadataColumns -Width $uiWidth -Config $Config

        # Add a subtle separator line for visual clarity
        $SeparatorColumns = @(
            New-UiColumn -Text ([string]::new([char]0x2500, $uiWidth)) -Width $uiWidth -Alignment 'c' -TextColor $fgNeutral4 -Dim
        )
        Format-UI -Columns $SeparatorColumns -Width $uiWidth -Config $Config
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        # Fallback to legacy parameter if no current project is set
        Write-PSmmHost ''
        $TitleColumns = @(
            New-UiColumn -Text "$($Title): $ProjectName" -Width $uiWidth -Alignment 'c' -Underline
        )
        Format-UI -Columns $TitleColumns -Width $uiWidth -Config $Config
    }
}

<#
.SYNOPSIS
    Displays the application footer with action options.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Show-Footer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    $uiWidthSource = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'Width')
    $uiWidth = 80
    if ($null -ne $uiWidthSource) {
        try {
            $uiWidth = [int]$uiWidthSource
            if ($uiWidth -lt 1) { $uiWidth = 80 }
        }
        catch {
            $uiWidth = 80
        }
    }

    $fgAccent = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Accent')
    $fgInfo   = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Info')

    $FooterColumns = @(
        New-UiColumn -Text '[K] Start KeePassXC' -Width '50%' -Alignment 'l' -TextColor $fgAccent
        New-UiColumn -Text "Show System Info [I]`nQuit [Q]" -Width 'auto' -Alignment 'r' -TextColor $fgInfo
    )

    $borderChar = $PSSpecialChar.SixPointStar

    Format-UI -Columns $FooterColumns -Width $uiWidth -Border $borderChar -Config $Config
}

#endregion ########## Header/Footer ##########


#region ########## Main Menu ##########

<#
.SYNOPSIS
    Displays the main menu with project listings.

.DESCRIPTION
    Shows available projects organized by Master and Backup drives,
    with options to create or delete projects.

.PARAMETER Run
    The runtime configuration hashtable.

.PARAMETER StorageGroup
    Optional. Specific storage group to display (e.g., '1', '2').
    If not specified, all storage groups will be displayed.
#>
function Show-MenuMain {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter()]
        [string]$StorageGroup = $null,

        [Parameter()]
        [object]$Projects = $null
    )

    $storageMap = Get-PSmmUiConfigMemberValue -Object $Config -Name 'Storage'
    $storageKeys = @()
    if ($storageMap -is [System.Collections.IDictionary]) {
        $storageKeys = @($storageMap.Keys)
    }
    elseif ($null -ne $storageMap) {
        try {
            $k = $storageMap.Keys
            if ($null -ne $k) { $storageKeys = @($k) }
        }
        catch {
            Write-Verbose "Show-MenuMain: failed to enumerate Storage keys: $($_.Exception.Message)"
        }
    }

    $parameters = Get-PSmmUiConfigMemberValue -Object $Config -Name 'Parameters'
    $isDebugOrDev = [bool](Get-PSmmUiConfigMemberValue -Object $parameters -Name 'Debug') -or [bool](Get-PSmmUiConfigMemberValue -Object $parameters -Name 'Dev')

    $uiWidthSource = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'Width')
    $uiWidth = 80
    if ($null -ne $uiWidthSource) {
        try {
            $uiWidth = [int]$uiWidthSource
            if ($uiWidth -lt 1) { $uiWidth = 80 }
        }
        catch {
            $uiWidth = 80
        }
    }

    $fgAccent       = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Accent')
    $fgWarning      = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Warning')
    $fgSuccess      = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Success')
    $fgSuccessLight = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'SuccessLight')
    $fgError        = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Error')

    if ($isDebugOrDev) {
        Write-Verbose '[UI] Show-MenuMain starting diagnostics...'
        Write-Verbose ("[UI] Storage groups present: {0}" -f ($storageKeys -join ', '))

        $projectsObj = Get-PSmmUiConfigMemberValue -Object $Config -Name 'Projects'
        $registry = Get-PSmmUiConfigMemberValue -Object $projectsObj -Name 'Registry'

        if ($null -ne $registry) {
            $master = Get-PSmmUiConfigMemberValue -Object $registry -Name 'Master'

            if ($master -is [System.Collections.IDictionary]) {
                Write-Verbose ("[UI] Registry Master keys: {0}" -f (($master.Keys | Sort-Object) -join ', '))
            }
            else {
                Write-Verbose '[UI] Projects.Registry present but Master keys not enumerable'
            }
        }
        else {
            Write-Verbose '[UI] Projects.Registry not present (skipping registry diagnostics)'
        }
    }

    # Display filter storage group option
    $FilterOptionColumns = @(
        New-UiColumn -Text '[S] Filter Storage Group' -Width $uiWidth -Alignment 'l' -TextColor $fgAccent
    )
    Format-UI -Columns $FilterOptionColumns -Width $uiWidth -Config $Config
    Write-PSmmHost ''

    # Display current filter status
    if (-not [string]::IsNullOrWhiteSpace($StorageGroup)) {
        $FilterColumns = @(
            New-UiColumn -Text "$('=' * 18) Storage Group $StorageGroup $('=' * 18)" -Width $uiWidth -Alignment 'c' -TextColor $fgWarning -Bold
        )
        Format-UI -Columns $FilterColumns -Width $uiWidth -Config $Config
        Write-PSmmHost ''
    }

    # Action buttons
    $Columns = @(
        New-UiColumn -Text '[C] Create Project' -Width '50%' -Alignment 'l' -TextColor $fgSuccess
        New-UiColumn -Text '[R] Reconfigure Storage' -Width '50%' -Alignment 'r' -TextColor $fgAccent

    )
    Format-UI -Columns $Columns -Width $uiWidth -Config $Config
    Write-PSmmHost ''

    Write-PSmmLog -Level NOTICE -Context 'Show-Projects' -Message 'Load available projects' -File
    if ($null -eq $Projects) {
        $Projects = Get-PSmmProjects -Config $Config -FileSystem $FileSystem
    }

    $uiProjectsIndexType = 'UiProjectsIndex' -as [type]
    if (-not $uiProjectsIndexType) {
        throw 'Unable to resolve required type [UiProjectsIndex]. Ensure PSmm is loaded before PSmm.UI.'
    }

    $projectsIndex = $uiProjectsIndexType::FromObject($Projects)

    if ($isDebugOrDev) {
        $masterTotal = ($projectsIndex.Master.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        $backupTotal = ($projectsIndex.Backup.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        Write-Verbose ("[UI] Retrieved projects: MasterTotal={0} BackupTotal={1}" -f $masterTotal, $backupTotal)
        foreach ($k in $projectsIndex.Master.Keys) { Write-Verbose ("[UI] Master[{0}] Count={1}" -f $k, $projectsIndex.Master[$k].Count) }
        foreach ($k in $projectsIndex.Backup.Keys) { Write-Verbose ("[UI] Backup[{0}] Count={1}" -f $k, $projectsIndex.Backup[$k].Count) }
    }

    # Determine which storage groups to display
    $StorageGroupsToDisplay = if ([string]::IsNullOrWhiteSpace($StorageGroup)) {
        # Show all storage groups
        @($storageKeys | Sort-Object)
    }
    else {
        # Show only the specified storage group
        # Find matching storage group key (handles string vs int comparison)
        $MatchingKey = $storageKeys | Where-Object { $_.ToString() -eq $StorageGroup.ToString() } | Select-Object -First 1

        if ($MatchingKey) {
            @($MatchingKey)
        }
        else {
            Write-PSmmHost "Storage Group '$StorageGroup' not found. Available groups: $($storageKeys -join ', ')" -ForegroundColor Red
            return
        }
    }

    if (@($StorageGroupsToDisplay).Count -eq 0) {
        Write-PSmmHost 'No storage groups configured.' -ForegroundColor DarkGray
        return
    }

    # Group and display projects by storage group
    foreach ($storageGroupKey in $StorageGroupsToDisplay) {
        # Display Storage Group Header (only when not filtered, as it's shown above when filtered)
        if ([string]::IsNullOrWhiteSpace($StorageGroup)) {
            $StorageGroupColumns = @(
                New-UiColumn -Text "$('=' * 16) Storage Group $storageGroupKey $('=' * 16)" -Width $uiWidth -Alignment 'c' -TextColor $fgWarning -Bold
            )
            Format-UI -Columns $StorageGroupColumns -Width $uiWidth -Config $Config
            Write-PSmmHost ''
        }

        # Collect all drives (Master and Backup) for this storage group
        $AllDrivesInGroup = [System.Collections.Generic.Dictionary[string, UiDriveProjectsInfo]]::new()

        # Add Master drives
        if ($null -ne $projectsIndex.Master -and $projectsIndex.Master.Count -gt 0) {
            foreach ($driveLabel in $projectsIndex.Master.Keys) {
                $driveProjects = $projectsIndex.Master[$driveLabel]
                if ($driveProjects -and $driveProjects.Count -gt 0) {
                    $firstProject = $driveProjects | Select-Object -First 1
                    if ($firstProject -and (Get-Member -InputObject $firstProject -Name 'StorageGroup' -MemberType Properties)) {
                        if ($firstProject.StorageGroup -eq $storageGroupKey) {
                            $AllDrivesInGroup[$driveLabel] = [UiDriveProjectsInfo]::new([object[]]$driveProjects, 'Master Drive', '', $null, $false)
                        }
                    }
                }
            }
        }

        # Add Backup drives
        if ($null -ne $projectsIndex.Backup -and $projectsIndex.Backup.Count -gt 0) {
            foreach ($driveLabel in $projectsIndex.Backup.Keys) {
                $driveProjects = $projectsIndex.Backup[$driveLabel]
                if ($driveProjects -and $driveProjects.Count -gt 0) {
                    $firstProject = $driveProjects | Select-Object -First 1
                    if ($firstProject -and (Get-Member -InputObject $firstProject -Name 'StorageGroup' -MemberType Properties)) {
                        if ($firstProject.StorageGroup -eq $storageGroupKey) {
                            # Use BackupId from the project object instead of a counter
                            $backupId = if ($firstProject.BackupId) { [int]$firstProject.BackupId } else { 1 }
                            $AllDrivesInGroup[$driveLabel] = [UiDriveProjectsInfo]::new([object[]]$driveProjects, 'Backup Drive', ("B$backupId"), [Nullable[int]]$backupId, $false)
                        }
                    }
                }
            }
        }

        # Display all drives in this storage group
        if ($AllDrivesInGroup.Count -gt 0) {
            if ($isDebugOrDev) {
                Write-Verbose ("[UI] Drives to display for StorageGroup {0}: {1}" -f $storageGroupKey, ($AllDrivesInGroup.Keys -join ', '))
            }
            # Sort drives: Master drives first, then Backup drives
            $SortedDriveLabels = $AllDrivesInGroup.Keys | Sort-Object {
                $driveInfo = $AllDrivesInGroup[$_]
                # Master drives get priority 0, Backup drives get priority 1
                if ($driveInfo.DriveType -eq 'Master Drive') { "0_$_" } else { "1_$_" }
            }

            foreach ($driveLabel in $SortedDriveLabels) {
                $driveInfo = $AllDrivesInGroup[$driveLabel]
                $isFallback = [bool]$driveInfo.IsFallback
                $backupNumber = $driveInfo.BackupNumber
                if ($isDebugOrDev) {
                    $projNames = ($driveInfo.Projects | Where-Object { $_.Name } | Select-Object -ExpandProperty Name)
                    Write-Verbose ("[UI] Rendering drive '{0}' Type={1} Projects=[{2}]" -f $driveLabel, $driveInfo.DriveType, ($projNames -join ', '))
                }
                Show-UnifiedDrive -DriveLabel $driveLabel `
                    -Projects $driveInfo.Projects `
                    -DriveType $driveInfo.DriveType `
                    -Prefix $driveInfo.Prefix `
                    -BackupNumber $backupNumber `
                    -IsFallback $isFallback `
                    -Config $Config
            }
        }
        else {
            if ($isDebugOrDev) {
                Write-Verbose ("[UI] No drives found for StorageGroup {0}. Displaying status block." -f $storageGroupKey)
            }
            # No projects found for this storage group - show storage status instead
            # Note: $Config.Storage contains runtime storage info with IsAvailable property
            $storageConfig = $null
            if ($storageMap -is [System.Collections.IDictionary]) {
                $storageConfig = $storageMap[$storageGroupKey]
            }
            elseif ($null -ne $storageMap) {
                try { $storageConfig = $storageMap[$storageGroupKey] } catch { $storageConfig = $null }
                if ($null -eq $storageConfig) {
                    $storageConfig = Get-PSmmUiConfigMemberValue -Object $storageMap -Name ([string]$storageGroupKey)
                }
            }
            if ($storageConfig) {
                # Display Master drive status
                $master = Get-PSmmUiConfigMemberValue -Object $storageConfig -Name 'Master'
                if ($null -ne $master) {
                    $labelObj = Get-PSmmUiConfigMemberValue -Object $master -Name 'Label'
                    $label = if ($null -ne $labelObj) { [string]$labelObj } else { '' }
                    if (-not [string]::IsNullOrWhiteSpace($label)) {
                        $isAvailableObj = Get-PSmmUiConfigMemberValue -Object $master -Name 'IsAvailable'
                        $isAvailable = if ($null -ne $isAvailableObj) { [bool]$isAvailableObj } else { $false }

                        $driveLetterObj = Get-PSmmUiConfigMemberValue -Object $master -Name 'DriveLetter'
                        $driveLetter = if ($null -ne $driveLetterObj) { [string]$driveLetterObj } else { $null }
                        $statusText = if ($isAvailable -and -not [string]::IsNullOrWhiteSpace($driveLetter)) {
                            "Available ($driveLetter)"
                        } elseif ($isAvailable) {
                            'Available (no drive letter)'
                        } else {
                            'Not mounted or unavailable'
                        }

                        $masterColumns = @(
                            New-UiColumn -Text "Master: $label" -Width '60%' -Alignment 'l' -TextColor (if ($isAvailable) { $fgSuccess } else { $fgError })
                            New-UiColumn -Text $statusText -Width 'auto' -Alignment 'r' -TextColor (if ($isAvailable) { $fgSuccessLight } else { $fgWarning }) -Dim:(-not $isAvailable)
                        )
                        Format-UI -Columns $masterColumns -Width $uiWidth -Config $Config
                    }
                }

                # Display Backup drive(s) status using typed Backups dictionary (defensive against legacy or partial config without Backups)
                $backups = Get-PSmmUiConfigMemberValue -Object $storageConfig -Name 'Backups'
                if ($null -ne $backups -and ($backups -is [hashtable] -or $backups -is [System.Collections.IDictionary]) -and $backups.Count -gt 0) {
                    foreach ($backupId in ($backups.Keys | Sort-Object)) {
                        $backup = $backups[$backupId]
                        if ($null -eq $backup) { continue }

                        # Determine availability & label
                        $labelObj = Get-PSmmUiConfigMemberValue -Object $backup -Name 'Label'
                        $label = if ($null -ne $labelObj) { [string]$labelObj } else { '' }
                        if ([string]::IsNullOrWhiteSpace($label)) { continue }

                        $isAvailableObj = Get-PSmmUiConfigMemberValue -Object $backup -Name 'IsAvailable'
                        $isAvailable = if ($null -ne $isAvailableObj) { [bool]$isAvailableObj } else { $false }
                        $driveLetterObj = Get-PSmmUiConfigMemberValue -Object $backup -Name 'DriveLetter'
                        $driveLetter = if ($null -ne $driveLetterObj) { [string]$driveLetterObj } else { $null }
                        $statusText = if ($isAvailable -and -not [string]::IsNullOrWhiteSpace($driveLetter)) {
                            "Available ($driveLetter)"
                        } elseif ($isAvailable) {
                            'Available (no drive letter)'
                        } else {
                            'Not mounted or unavailable'
                        }

                        $backupColumns = @(
                            New-UiColumn -Text "Backup $backupId : $label" -Width '60%' -Alignment 'l' -TextColor (if ($isAvailable) { $fgSuccess } else { $fgError })
                            New-UiColumn -Text $statusText -Width 'auto' -Alignment 'r' -TextColor (if ($isAvailable) { $fgSuccessLight } else { $fgWarning }) -Dim:(-not $isAvailable)
                        )
                        Format-UI -Columns $backupColumns -Width $uiWidth -Config $Config
                    }
                }
                elseif ($storageConfig -and $null -eq $backups) {
                    # Older configuration (or not yet built) where Backups property is missing entirely
                    Write-PSmmHost '  No backup configuration defined for this storage group' -ForegroundColor DarkGray
                }
                elseif ($null -ne $backups -and $backups.Count -eq 0) {
                    # Backups property exists but empty
                    Write-PSmmHost '  No backup drives registered for this storage group' -ForegroundColor DarkGray
                }

                # Show a message if no projects found
                    Write-PSmmHost '  No projects found on this storage group' -ForegroundColor DarkGray
            }
        }

        Write-PSmmHost ''
    }
}

<#
.SYNOPSIS
    Displays a single drive with its role, metadata, and projects in a unified format.

.PARAMETER DriveLabel
    The label of the drive to display.

.PARAMETER Projects
    Array of project objects for this drive.

.PARAMETER DriveType
    The role of the drive ('Master Drive' or 'Backup Drive').

.PARAMETER Prefix
    Optional prefix for project numbering (e.g., 'B1' for backup).

.PARAMETER BackupNumber
    Optional backup drive number (e.g., 1 for Backup-1, 2 for Backup-2).

.PARAMETER IsFallback
    Indicates if this storage is being shown due to automatic fallback.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Show-UnifiedDrive {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'BackupNumber', Justification = 'Parameter reserved for future backup drive numbering feature')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$DriveLabel,

        [Parameter(Mandatory)]
        [AllowNull()]
        [array]$Projects,

        [Parameter(Mandatory)]
        [string]$DriveType,

        [Parameter()]
        [string]$Prefix = '',

        [Parameter()]
        [AllowNull()]
        [int]$BackupNumber = $null,

        [Parameter()]
        [bool]$IsFallback = $false,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    if ($null -eq $Projects -or $Projects.Count -eq 0) {
        return
    }

    $DriveProjects = @($Projects)

    # Get drive information from first project
    if ($DriveProjects.Count -eq 0) {
        return
    }

    $DriveInfo = $DriveProjects[0]

    $uiWidthSource = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'Width')
    $uiWidth = 80
    if ($null -ne $uiWidthSource) {
        try {
            $uiWidth = [int]$uiWidthSource
            if ($uiWidth -lt 1) { $uiWidth = 80 }
        }
        catch {
            $uiWidth = 80
        }
    }

    $fgMasterDrive      = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'MasterDrive')
    $fgMasterDriveLight = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'MasterDriveLight')
    $fgBackupDrive      = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'BackupDrive')
    $fgBackupDriveLight = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'BackupDriveLight')
    $fgBackupDriveDark  = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'BackupDriveDark')

    $fgAccent      = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Accent')
    $fgSecondary   = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Secondary')
    $fgInfo        = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Info')
    $fgSuccess     = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Success')
    $fgWarning     = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Warning')
    $fgError       = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Error')
    $fgNeutral1    = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Neutral1')
    $fgNeutral2    = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Neutral2')
    $fgNeutral3    = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Neutral3')
    $fgNeutral4    = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Neutral4')

    # Determine colors and styling based on drive type
    $IsMaster = $DriveType -eq 'Master Drive'
    $BorderChar = if ($IsMaster) { [char]0x2550 } else { [char]0x2500 }  # ═ for Master, ─ for Backup
    $HeaderColor = if ($IsMaster) { $fgMasterDrive } else { $fgBackupDrive }
    $RoleColor = if ($IsMaster) { $fgMasterDriveLight } else { $fgBackupDriveLight }

    # Display drive header with label and role
    $DriveHeaderColumns = @(
        New-UiColumn -Text "$([string]::new($BorderChar, 18)) $DriveLabel $([string]::new($BorderChar, 18))" -Width $uiWidth -Alignment 'c' -TextColor $HeaderColor -Bold
    )
    Format-UI -Columns $DriveHeaderColumns -Width $uiWidth -Config $Config

    # Display role with icon
    $RoleIcon = if ($IsMaster) { '💿' } else { '📀' }
    $RoleText = "$RoleIcon Role: $DriveType"
    if ($IsFallback) {
        $RoleText += " (Automatic Fallback)"
        $RoleColor = $fgWarning
    }
    $RoleColumns = @(
        New-UiColumn -Text $RoleText -Width $uiWidth -Alignment 'c' -TextColor $RoleColor -Bold
    )
    Format-UI -Columns $RoleColumns -Width $uiWidth -Config $Config

    # Calculate space usage percentage
    $UsedPercent = if ($DriveInfo.TotalSpace -gt 0) {
        [math]::Round(($DriveInfo.UsedSpace / $DriveInfo.TotalSpace) * 100, 1)
    } else { 0 }
    $FreePercent = if ($DriveInfo.TotalSpace -gt 0) {
        [math]::Round(($DriveInfo.FreeSpace / $DriveInfo.TotalSpace) * 100, 1)
    } else { 0 }

    $healthColor = switch ($DriveInfo.HealthStatus) {
        'Healthy' { $fgSuccess }
        'Warning' { $fgWarning }
        'Unhealthy' { $fgError }
        default { $fgNeutral1 }
    }

    # Define metadata items in optimal sorted order for two-column display
    $MetadataItems = @(
        New-UiKeyValueItem -Key 'Drive Letter' -Value $DriveInfo.Drive -Color $fgAccent
        New-UiKeyValueItem -Key 'Serial Number' -Value $DriveInfo.SerialNumber -Color $fgNeutral2
        New-UiKeyValueItem -Key 'Label' -Value $DriveInfo.Label -Color $fgWarning
        New-UiKeyValueItem -Key 'Manufacturer' -Value $DriveInfo.Manufacturer -Color $fgNeutral1
        New-UiKeyValueItem -Key 'Model' -Value $DriveInfo.Model -Color $fgNeutral1
        New-UiKeyValueItem -Key 'File System' -Value $DriveInfo.FileSystem -Color $fgInfo
        New-UiKeyValueItem -Key 'Partition Kind' -Value $DriveInfo.PartitionKind -Color $fgNeutral2
        New-UiKeyValueItem -Key 'Total Space' -Value "$([math]::Round($DriveInfo.TotalSpace, 2)) GB" -Color $fgInfo
        New-UiKeyValueItem -Key 'Used Space' -Value "$([math]::Round($DriveInfo.UsedSpace, 2)) GB ($UsedPercent%)" -Color $fgSecondary
        New-UiKeyValueItem -Key 'Free Space' -Value "$([math]::Round($DriveInfo.FreeSpace, 2)) GB ($FreePercent%)" -Color $fgSuccess
        New-UiKeyValueItem -Key 'Health Status' -Value $DriveInfo.HealthStatus -Color $healthColor
        New-UiKeyValueItem -Key 'Projects' -Value (@($DriveProjects | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) }).Count) -Color $fgNeutral1
    )

    # Display metadata in side-by-side two-column layout centered
    $contentWidth = 76  # Optimized width for metadata display

    for ($i = 0; $i -lt $MetadataItems.Count; $i += 2) {
        $LeftItem = $MetadataItems[$i]
        $RightItem = if ($i + 1 -lt $MetadataItems.Count) { $MetadataItems[$i + 1] } else { $null }

        $MetadataColumns = @(
            New-UiColumn -Text "$($LeftItem.Key):" -Width 17 -Alignment 'r' -TextColor $fgAccent
            New-UiColumn -Text $LeftItem.Value -Width 21 -Alignment 'l' -TextColor $LeftItem.Color
        )

        if ($RightItem) {
            $MetadataColumns += @(
                New-UiColumn -Text "$($RightItem.Key):" -Width 17 -Alignment 'r' -TextColor $fgAccent
                New-UiColumn -Text $RightItem.Value -Width 21 -Alignment 'l' -TextColor $RightItem.Color
            )
        }

        # Generate the line (Format-UI handles output directly)
        Format-UI -Columns $MetadataColumns -Width $contentWidth -ColumnSeparator ' ' -Config $Config | Out-Null
    }

    # Projects header
    $ProjectsColumns = @(
        New-UiColumn -Text "$([string]::new([char]0x2500, 7)) PROJECTS $([string]::new([char]0x2500, 7))" -Width $uiWidth -Alignment 'c' -TextColor $fgSuccess -Bold -Italic
    )
    Format-UI -Columns $ProjectsColumns -Width $uiWidth -Config $Config
    Write-PSmmHost ''

    # Display projects
    $Count = 0
    foreach ($Project in $DriveProjects) {
        if ([string]::IsNullOrWhiteSpace($Project.Name)) {
            continue
        }
        $Count++

        # Use project name directly - prefix is already shown in the first column
        $DisplayName = $Project.Name

        # Determine project numbering color based on drive type
        $ProjectNumColor = if ($IsMaster) {
                $fgMasterDriveLight
        } else {
                $fgBackupDriveDark
        }

        $ProjectColumns = @(
            New-UiColumn -Text "[$Prefix$Count]" -Width 10 -Alignment 'c' -TextColor $ProjectNumColor -Bold
            New-UiColumn -Text $DisplayName -Width 20 -Alignment 'l' -TextColor $fgNeutral1
            New-UiColumn -Text $Project.Path -Width 'auto' -Alignment 'l' -TextColor $fgNeutral3
        )
        Format-UI -Columns $ProjectColumns -Width $uiWidth -Config $Config
    }

    if ($Count -eq 0) {
        $NoProjectsColumns = @(
            New-UiColumn -Text 'No projects found on this drive.' -Width $uiWidth -Alignment 'c' -TextColor $fgNeutral4 -Italic
        )
        Format-UI -Columns $NoProjectsColumns -Width $uiWidth -Config $Config
    }

    Write-PSmmLog -Level NOTICE -Context 'Show-UnifiedDrive' -Message "Displayed $Count projects for $DriveType : $DriveLabel" -File
    Write-PSmmHost ''
}

#endregion ########## Main Menu ##########


#region ########## Project Menu ##########

<#
.SYNOPSIS
    Displays the project-specific menu with available actions.

.DESCRIPTION
    Shows menu options for the current project, including backup operations,
    digiKam management, media processing plugins, and more. Menu options vary
    based on whether digiKam or MariaDB processes are currently running.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Show-Menu_Project {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Process
    )

    $uiWidthSource = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'Width')
    $uiWidth = 80
    if ($null -ne $uiWidthSource) {
        try {
            $uiWidth = [int]$uiWidthSource
            if ($uiWidth -lt 1) { $uiWidth = 80 }
        }
        catch {
            $uiWidth = 80
        }
    }

    $fgInfo = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Info')

    # Check for running processes
    $ProcMariaDB = $null
    $ProcDigiKam = $null

    $projects = Get-PSmmUiConfigMemberValue -Object $Config -Name 'Projects'
    $currentProjectSource = Get-PSmmUiConfigMemberValue -Object $projects -Name 'Current'

    if ($null -ne $currentProjectSource) {
        $currentProject = [ProjectCurrentConfig]::FromObject($currentProjectSource)

        if (-not [string]::IsNullOrWhiteSpace($currentProject.Databases)) {
            $allMariaDB = $Process.GetProcess('mariadbd')
            if ($null -ne $allMariaDB) {
                $ProcMariaDB = $allMariaDB | Where-Object { $_.CommandLine -like "*$($currentProject.Databases)*" }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($currentProject.Config)) {
            $allDigiKam = $Process.GetProcess('digikam')
            if ($null -ne $allDigiKam) {
                $ProcDigiKam = $allDigiKam | Where-Object { $_.CommandLine -like "*$($currentProject.Config)*" }
            }
        }
    }

    $ProcessesRunning = ($null -ne $ProcMariaDB) -or ($null -ne $ProcDigiKam)

    if (-not $ProcessesRunning) {
        # Display backup and database management options when no processes are running
        try {
            Show-ProjectMenuOption_NoProcess -Config $Config
        }
        catch {
            Write-Warning "Show-ProjectMenuOption_NoProcess failed: $_"
            Write-PSmmHost "Error details: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    else {
        # Display limited options when processes are running
        try {
            Show-ProjectMenuOptions_ProcessesRunning -Config $Config
        }
        catch {
            Write-Warning "Show-ProjectMenuOptions_ProcessesRunning failed: $_"
            Write-PSmmHost "Error details: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-PSmmHost ''

    # Common footer with navigation options
    $ReturnColumns = @(
        New-UiColumn -Text '[R] Return to previous menu' -Width 'auto' -Alignment 'l' -TextColor $fgInfo
        New-UiColumn -Text 'Quit [Q]' -Width 'auto' -Alignment 'r' -TextColor $fgInfo
    )

    $borderChar = $PSSpecialChar.SixPointStar

    Format-UI -Columns $ReturnColumns -Width $uiWidth -Border $borderChar -Config $Config
}

<#
.SYNOPSIS
    Displays menu options when no processes are running.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Show-ProjectMenuOption_NoProcess {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    $uiWidthSource = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'Width')
    $uiWidth = 80
    if ($null -ne $uiWidthSource) {
        try {
            $uiWidth = [int]$uiWidthSource
            if ($uiWidth -lt 1) { $uiWidth = 80 }
        }
        catch {
            $uiWidth = 80
        }
    }

    $fgPrimary = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Primary')

    # Note: Backup operations removed - not yet implemented

    # DigiKam management
    $DigiKamColumns = @(
        New-UiColumn -Text '[1] Start digiKam' -Width $uiWidth -Alignment 'l' -TextColor $fgPrimary -Bold
    )
    Format-UI -Columns $DigiKamColumns -Width $uiWidth -Config $Config
}

<#
.SYNOPSIS
    Displays limited menu options when processes are running.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Show-ProjectMenuOptions_ProcessesRunning {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    $uiWidthSource = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'Width')
    $uiWidth = 80
    if ($null -ne $uiWidthSource) {
        try {
            $uiWidth = [int]$uiWidthSource
            if ($uiWidth -lt 1) { $uiWidth = 80 }
        }
        catch {
            $uiWidth = 80
        }
    }

    $fgInfo        = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Info')
    $fgAccent      = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Accent')
    $fgAccentLight = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'AccentLight')
    $fgSecondary   = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Secondary')
    $fgError       = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Error')

    Write-PSmmHost ''

    # Media overview
    $OverviewColumns = @(
        New-UiColumn -Text '[11] Published Media Overview' -Width $uiWidth -Alignment 'l' -TextColor $fgInfo
    )
    Format-UI -Columns $OverviewColumns -Width $uiWidth -Config $Config

    Write-PSmmHost ''

    # Pricing options
    $PricingColumns = @(
        New-UiColumn -Text '[2]  Pricing    : Get prices for media files' -Width $uiWidth -Alignment 'l' -TextColor $fgAccent
    )
    Format-UI -Columns $PricingColumns -Width $uiWidth -Config $Config

    $BundleColumns = @(
        New-UiColumn -Text '[22] Bundle  : Get prices for bundles media files' -Width $uiWidth -Alignment 'l' -TextColor $fgAccent
    )
    Format-UI -Columns $BundleColumns -Width $uiWidth -Config $Config

    $NewPricingColumns = @(
        New-UiColumn -Text '[2n] Pricing : NEW Get prices for media files' -Width $uiWidth -Alignment 'l' -TextColor $fgAccentLight
    )
    Format-UI -Columns $NewPricingColumns -Width $uiWidth -Config $Config

    Write-PSmmHost ''

    # Media processing plugins
    $ImageMagickColumns = @(
        New-UiColumn -Text '[3] ImageMagick: Convert and process Images' -Width $uiWidth -Alignment 'l' -TextColor $fgSecondary
    )
    Format-UI -Columns $ImageMagickColumns -Width $uiWidth -Config $Config

    $FfmpegColumns = @(
        New-UiColumn -Text '[4] FFmpeg     : Rebuild Chunk Offset Table (mp4, mov)' -Width $uiWidth -Alignment 'l' -TextColor $fgSecondary
    )
    Format-UI -Columns $FfmpegColumns -Width $uiWidth -Config $Config

    Write-PSmmHost ''

    # Stop processes option
    $StopColumns = @(
        New-UiColumn -Text 'Stop digiKam Processes [S]' -Width $uiWidth -Alignment 'r' -TextColor $fgError
    )
    Format-UI -Columns $StopColumns -Width $uiWidth -Config $Config
}

#endregion ########## Project Menu ##########


#region ########## System Info ##########

<#
.SYNOPSIS
    Displays the system information menu.

.DESCRIPTION
    Shows menu options for viewing system information such as storage
    and runtime configuration.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Show-Menu_SysInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    $uiWidthSource = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'Width')
    $uiWidth = 80
    if ($null -ne $uiWidthSource) {
        try {
            $uiWidth = [int]$uiWidthSource
            if ($uiWidth -lt 1) { $uiWidth = 80 }
        }
        catch {
            $uiWidth = 80
        }
    }

    $fgInfo = Get-PSmmUiConfigNestedValue -Object $Config -Path @('UI', 'ANSI', 'FG', 'Info')

    $StorageColumns = @(
        New-UiColumn -Text '[1] Show Storage Information' -Width $uiWidth -Alignment 'l' -TextColor $fgInfo
    )
    Format-UI -Columns $StorageColumns -Width $uiWidth -Config $Config

    $ConfigColumns = @(
        New-UiColumn -Text '[2] Show Runtime Configuration' -Width $uiWidth -Alignment 'l' -TextColor $fgInfo
    )
    Format-UI -Columns $ConfigColumns -Width $uiWidth -Config $Config

    Write-PSmmHost ''

    $ReturnColumns = @(
        New-UiColumn -Text '[R] Return to previous menu' -Width 'auto' -Alignment 'l'
        New-UiColumn -Text 'Quit [Q]' -Width 'auto' -Alignment 'r'
    )
    Format-UI -Columns $ReturnColumns -Width $uiWidth -Border 'Box' -Config $Config
}

#endregion ########## System Info ##########
