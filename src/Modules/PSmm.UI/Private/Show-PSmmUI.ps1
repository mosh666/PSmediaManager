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
    )    $Columns = @(
        @{
            Text = $Config.DisplayName
            Width = '50%'
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Primary
            Bold = $true
            Italic = $true
        }
        @{
            Text = $Config.AppVersion
            Width = 'auto'
            Alignment = 'r'
            TextColor = $Config.UI.ANSI.FG.Accent
            Italic = $true
        }
    )

    # PS 7.5.4+ baseline guarantees $PSSpecialChar
    $borderChar = $PSSpecialChar.SixPointStar

    Format-UI -Columns $Columns -Width $Config.UI.Width -ColumnSeparator '' -Border $borderChar -Config $Config
    Write-PSmmHost ''

    # Display error messages if enabled
    if ($ShowStorageErrors) {
        # Filter error messages based on storage group if specified
        $ErrorHashtable = if (-not [string]::IsNullOrWhiteSpace($StorageGroupFilter) -and
            $Config.InternalErrorMessages.ContainsKey('Storage')) {
            # Create filtered hashtable with only errors matching the storage group
            $FilteredErrors = @{}
            foreach ($errorKey in $Config.InternalErrorMessages.Storage.Keys) {
                # Error keys are formatted as: "StorageGroup.Type.BackupId" or "StorageGroup.Type"
                # e.g., "1.Backup.2" or "1.Master"
                if ($errorKey -match "^$([regex]::Escape($StorageGroupFilter))\.") {
                    $FilteredErrors[$errorKey] = $Config.InternalErrorMessages.Storage[$errorKey]
                }
            }
            @{ Storage = $FilteredErrors }
        }
        else {
            $Config.InternalErrorMessages
        }

        $ErrorMessages = Get-ErrorMessages -ErrorHashtable $ErrorHashtable
        if ($ErrorMessages -and @($ErrorMessages).Count -gt 0) {
            foreach ($ErrorMsg in $ErrorMessages) {
                $ErrorColumns = @(
                    @{
                        Text = $ErrorMsg
                        Width = $Config.UI.Width
                        Alignment = 'c'
                        TextColor = $Config.UI.ANSI.FG.Error
                        Bold = $true
                        Blink = $true
                    }
                )
                Format-UI -Columns $ErrorColumns -Width $Config.UI.Width -Config $Config
            }
            Write-PSmmHost ''
        }
    }

    # Display current project information if available and ShowProject is enabled
    if ($ShowProject -and $Config.Projects.ContainsKey('Current') -and $Config.Projects.Current.ContainsKey('Name')) {
        Write-PSmmHost ''

        # Get project name
        $CurrentProjectName = $Config.Projects.Current.Name

        # Build project display with folder icon
        # Use UTF-16 surrogate pairs for emoji > U+FFFF (0x1F4C1 = 📁)
        $ProjectDisplay = "$([char]::ConvertFromUtf32(0x1F4C1)) $CurrentProjectName"  # 📁 folder icon

        # Get storage disk information if available
        $DiskDisplay = ''
        $DiskColor = $Config.UI.ANSI.FG.Accent

        if ($Config.Projects.Current.ContainsKey('StorageDrive')) {
            $storageDrive = $Config.Projects.Current.StorageDrive

            # Determine drive type and icon based on label pattern
            # Use UTF-16 surrogate pairs for emoji > U+FFFF
            $driveIcon = [char]::ConvertFromUtf32(0x1F4BE)  # 💾 default storage icon

            if ($storageDrive.Label -match '-Backup-\d+$') {
                $driveIcon = [char]::ConvertFromUtf32(0x1F4C0)  # 📀 backup disc icon
                $DiskColor = $Config.UI.ANSI.FG.BackupDrive
            }
            elseif ($storageDrive.Label -notmatch '-Backup-') {
                $driveIcon = [char]::ConvertFromUtf32(0x1F4BF)  # 💿 master disc icon
                $DiskColor = $Config.UI.ANSI.FG.MasterDrive
            }

            # Build disk display string with icon
            $DiskDisplay = "$driveIcon $($storageDrive.Label) [$($storageDrive.DriveLetter)]"
        }

        # Display project info in a structured two-column layout
        if (-not [string]::IsNullOrWhiteSpace($DiskDisplay)) {
            # Two-column layout: Project on left, Disk info on right
            $ProjectMetadataColumns = @(
                @{
                    Text = $ProjectDisplay
                    Width = '50%'
                    Alignment = 'l'
                    TextColor = $Config.UI.ANSI.FG.Warning
                    Bold = $true
                }
                @{
                    Text = $DiskDisplay
                    Width = '50%'
                    Alignment = 'r'
                    TextColor = $DiskColor
                    Bold = $true
                }
            )
        }
        else {
            # Single column layout if no disk info
            $ProjectMetadataColumns = @(
                @{
                    Text = $ProjectDisplay
                    Width = $Config.UI.Width
                    Alignment = 'c'
                    TextColor = $Config.UI.ANSI.FG.Warning
                    Bold = $true
                    Underline = $true
                }
            )
        }

        Format-UI -Columns $ProjectMetadataColumns -Width $Config.UI.Width -Config $Config

        # Add a subtle separator line for visual clarity
        $SeparatorColumns = @(
            @{
                Text = [string]::new([char]0x2500, $Config.UI.Width)  # ─ horizontal line
                Width = $Config.UI.Width
                Alignment = 'c'
                TextColor = $Config.UI.ANSI.FG.Neutral4
                Dim = $true
            }
        )
        Format-UI -Columns $SeparatorColumns -Width $Config.UI.Width -Config $Config
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ProjectName)) {
        # Fallback to legacy parameter if no current project is set
        Write-PSmmHost ''
        $TitleColumns = @(
            @{
                Text = "$($Title): $ProjectName"
                Width = $Config.UI.Width
                Alignment = 'c'
                Underline = $true
            }
        )
        Format-UI -Columns $TitleColumns -Width $Config.UI.Width -Config $Config
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
    )    $FooterColumns = @(
        @{
            Text = '[K] Start KeePassXC'
            Width = '50%'
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Accent
        }
        @{
            Text = "Show System Info [I]`nQuit [Q]"
            Width = 'auto'
            Alignment = 'r'
            TextColor = $Config.UI.ANSI.FG.Info
        }
    )

    $borderChar = $PSSpecialChar.SixPointStar

    Format-UI -Columns $FooterColumns -Width $Config.UI.Width -Border $borderChar -Config $Config
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

        [Parameter()]
        [string]$StorageGroup = $null,

        [Parameter()]
        [hashtable]$Projects = $null
    )    if ($Config.Parameters.Debug -or $Config.Parameters.Dev) {
        Write-Verbose '[UI] Show-MenuMain starting diagnostics...'
        Write-Verbose ("[UI] Storage groups present: {0}" -f ($Config.Storage.Keys -join ', '))
        if ($Config.Projects -is [hashtable] -and $Config.Projects.ContainsKey('Registry') -and $null -ne $Config.Projects.Registry) {
            $hasRegMaster = ($Config.Projects.Registry -is [hashtable] -and $Config.Projects.Registry.ContainsKey('Master')) -or ($null -ne $Config.Projects.Registry.PSObject.Properties['Master'])
            if ($hasRegMaster -and $null -ne $Config.Projects.Registry.Master) {
                $keys = if ($Config.Projects.Registry.Master -is [hashtable]) { $Config.Projects.Registry.Master.Keys } else { @() }
                Write-Verbose ("[UI] Registry Master keys: {0}" -f ($keys -join ', '))
            }
        } else {
            Write-Verbose '[UI] Projects.Registry not present (skipping registry diagnostics)'
        }
    }

    # Display filter storage group option
    $FilterOptionColumns = @(
        @{
            Text = '[S] Filter Storage Group'
            Width = $Config.UI.Width
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Accent
        }
    )
    Format-UI -Columns $FilterOptionColumns -Width $Config.UI.Width -Config $Config
    Write-PSmmHost ''

    # Display current filter status
    if (-not [string]::IsNullOrWhiteSpace($StorageGroup)) {
        $FilterColumns = @(
            @{
                Text = "$('=' * 18) Storage Group $StorageGroup $('=' * 18)"
                Width = $Config.UI.Width
                Alignment = 'c'
                TextColor = $Config.UI.ANSI.FG.Warning
                Bold = $true
            }
        )
        Format-UI -Columns $FilterColumns -Width $Config.UI.Width -Config $Config
        Write-PSmmHost ''
    }

    # Action buttons
    $Columns = @(
        @{
            Text = '[C] Create Project'
            Width = '50%'
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Success
        },
        @{
            Text = '[R] Reconfigure Storage'
            Width = '50%'
            Alignment = 'r'
            TextColor = $Config.UI.ANSI.FG.Accent
        }

    )
    Format-UI -Columns $Columns -Width $Config.UI.Width -Config $Config
    Write-PSmmHost ''

    Write-PSmmLog -Level NOTICE -Context 'Show-Projects' -Message 'Load available projects' -File
    if ($null -eq $Projects) {
        $Projects = Get-PSmmProjects -Config $Config
    }

    if ($Config.Parameters.Debug -or $Config.Parameters.Dev) {
        $masterTotal = ($Projects.Master.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        $backupTotal = ($Projects.Backup.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        Write-Verbose ("[UI] Retrieved projects: MasterTotal={0} BackupTotal={1}" -f $masterTotal, $backupTotal)
        foreach ($k in $Projects.Master.Keys) { Write-Verbose ("[UI] Master[{0}] Count={1}" -f $k, $Projects.Master[$k].Count) }
        foreach ($k in $Projects.Backup.Keys) { Write-Verbose ("[UI] Backup[{0}] Count={1}" -f $k, $Projects.Backup[$k].Count) }
    }

    # Determine which storage groups to display
    $StorageGroupsToDisplay = if ([string]::IsNullOrWhiteSpace($StorageGroup)) {
        # Show all storage groups
        $Config.Storage.Keys | Sort-Object
    }
    else {
        # Show only the specified storage group
        # Find matching storage group key (handles string vs int comparison)
        $MatchingKey = $Config.Storage.Keys | Where-Object { $_.ToString() -eq $StorageGroup.ToString() } | Select-Object -First 1

        if ($MatchingKey) {
            @($MatchingKey)
        }
        else {
            Write-PSmmHost "Storage Group '$StorageGroup' not found. Available groups: $($Config.Storage.Keys -join ', ')" -ForegroundColor Red
            return
        }
    }

    # Group and display projects by storage group
    foreach ($storageGroupKey in $StorageGroupsToDisplay) {
        # Display Storage Group Header (only when not filtered, as it's shown above when filtered)
        if ([string]::IsNullOrWhiteSpace($StorageGroup)) {
            $StorageGroupColumns = @(
                @{
                    Text = "$('=' * 16) Storage Group $storageGroupKey $('=' * 16)"
                    Width = $Config.UI.Width
                    Alignment = 'c'
                    TextColor = $Config.UI.ANSI.FG.Warning
                    Bold = $true
                }
            )
            Format-UI -Columns $StorageGroupColumns -Width $Config.UI.Width -Config $Config
            Write-PSmmHost ''
        }

        # Collect all drives (Master and Backup) for this storage group
        $AllDrivesInGroup = @{}

        # Add Master drives
        if ($Projects.ContainsKey('Master') -and $null -ne $Projects.Master -and $Projects.Master.Count -gt 0) {
            foreach ($driveLabel in $Projects.Master.Keys) {
                $driveProjects = $Projects.Master[$driveLabel]
                if ($driveProjects -and $driveProjects.Count -gt 0) {
                    $firstProject = $driveProjects | Select-Object -First 1
                    if ($firstProject -and (Get-Member -InputObject $firstProject -Name 'StorageGroup' -MemberType Properties)) {
                        if ($firstProject.StorageGroup -eq $storageGroupKey) {
                            $AllDrivesInGroup[$driveLabel] = @{
                                Projects = $driveProjects
                                DriveType = 'Master Drive'
                                Prefix = ''
                            }
                        }
                    }
                }
            }
        }

        # Add Backup drives
        if ($Projects.ContainsKey('Backup') -and $null -ne $Projects.Backup -and $Projects.Backup.Count -gt 0) {
            foreach ($driveLabel in $Projects.Backup.Keys) {
                $driveProjects = $Projects.Backup[$driveLabel]
                if ($driveProjects -and $driveProjects.Count -gt 0) {
                    $firstProject = $driveProjects | Select-Object -First 1
                    if ($firstProject -and (Get-Member -InputObject $firstProject -Name 'StorageGroup' -MemberType Properties)) {
                        if ($firstProject.StorageGroup -eq $storageGroupKey) {
                            # Use BackupId from the project object instead of a counter
                            $backupId = if ($firstProject.BackupId) { $firstProject.BackupId } else { '1' }
                            $AllDrivesInGroup[$driveLabel] = @{
                                Projects = $driveProjects
                                DriveType = 'Backup Drive'
                                Prefix = "B$backupId"
                                BackupNumber = $backupId
                            }
                        }
                    }
                }
            }
        }

        # Display all drives in this storage group
        if ($AllDrivesInGroup.Count -gt 0) {
            if ($Config.Parameters.Debug -or $Config.Parameters.Dev) {
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
                $isFallback = $driveInfo.ContainsKey('Fallback') -and $driveInfo.Fallback
                $backupNumber = if ($driveInfo.ContainsKey('BackupNumber')) { $driveInfo.BackupNumber } else { $null }
                if ($Config.Parameters.Debug -or $Config.Parameters.Dev) {
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
            if ($Config.Parameters.Debug -or $Config.Parameters.Dev) {
                Write-Verbose ("[UI] No drives found for StorageGroup {0}. Displaying status block." -f $storageGroupKey)
            }
            # No projects found for this storage group - show storage status instead
            # Note: $Config.Storage contains runtime storage info with IsAvailable property
            $storageConfig = $Config.Storage[$storageGroupKey]
            if ($storageConfig) {
                # Display Master drive status
                # With StrictMode, ensure the 'Master' property exists before dereferencing.
                if ($null -ne $storageConfig.PSObject.Properties['Master']) {
                    $master = $storageConfig.Master

                    # Check if Master has a Label property (indicates it's configured)
                    $hasLabel = if ($master -is [hashtable]) {
                        $master.ContainsKey('Label')
                    } else {
                        $null -ne $master.PSObject.Properties['Label']
                    }

                    if ($hasLabel) {
                        $isAvailable = if ($master -is [hashtable]) {
                            if ($master.ContainsKey('IsAvailable')) { $master.IsAvailable } else { $false }
                        } elseif ($null -ne $master.PSObject.Properties['IsAvailable']) {
                            $master.IsAvailable
                        } else {
                            $false
                        }

                        $driveLetter = if ($master -is [hashtable]) { $master.DriveLetter } else { $master.DriveLetter }
                        $statusText = if ($isAvailable -and -not [string]::IsNullOrWhiteSpace($driveLetter)) {
                            "Available ($driveLetter)"
                        } elseif ($isAvailable) {
                            'Available (no drive letter)'
                        } else {
                            'Not mounted or unavailable'
                        }

                        $masterColumns = @(
                            @{
                                Text = "Master: $($master.Label)"
                                Width = '60%'
                                Alignment = 'l'
                                TextColor = if ($isAvailable) { $Config.UI.ANSI.FG.Success } else { $Config.UI.ANSI.FG.Error }
                            }
                            @{
                                Text = $statusText
                                Width = 'auto'
                                Alignment = 'r'
                                TextColor = if ($isAvailable) { $Config.UI.ANSI.FG.SuccessLight } else { $Config.UI.ANSI.FG.Warning }
                                Dim = -not $isAvailable
                            }
                        )
                        Format-UI -Columns $masterColumns -Width $Config.UI.Width -Config $Config
                    }
                }

                # Display Backup drive(s) status using typed Backups dictionary (defensive against legacy or partial config without Backups)
                if (
                    $storageConfig -and
                    $storageConfig.PSObject.Properties['Backups'] -and
                    $null -ne $storageConfig.Backups -and
                    ($storageConfig.Backups -is [hashtable] -or $storageConfig.Backups -is [System.Collections.IDictionary]) -and
                    $storageConfig.Backups.Count -gt 0
                ) {
                    foreach ($backupId in ($storageConfig.Backups.Keys | Sort-Object)) {
                        $backup = $storageConfig.Backups[$backupId]
                        if ($null -eq $backup) { continue }

                        # Determine availability & label
                        $label = $backup.Label
                        if ([string]::IsNullOrWhiteSpace($label)) { continue }

                        $isAvailable = if ($null -ne $backup.PSObject.Properties['IsAvailable']) { $backup.IsAvailable } else { $false }
                        $driveLetter = if ($null -ne $backup.PSObject.Properties['DriveLetter']) { $backup.DriveLetter } else { $null }
                        $statusText = if ($isAvailable -and -not [string]::IsNullOrWhiteSpace($driveLetter)) {
                            "Available ($driveLetter)"
                        } elseif ($isAvailable) {
                            'Available (no drive letter)'
                        } else {
                            'Not mounted or unavailable'
                        }

                        $backupColumns = @(
                            @{
                                Text = "Backup $backupId : $label"
                                Width = '60%'
                                Alignment = 'l'
                                TextColor = if ($isAvailable) { $Config.UI.ANSI.FG.Success } else { $Config.UI.ANSI.FG.Error }
                            }
                            @{
                                Text = $statusText
                                Width = 'auto'
                                Alignment = 'r'
                                TextColor = if ($isAvailable) { $Config.UI.ANSI.FG.SuccessLight } else { $Config.UI.ANSI.FG.Warning }
                                Dim = -not $isAvailable
                            }
                        )
                        Format-UI -Columns $backupColumns -Width $Config.UI.Width -Config $Config
                    }
                } elseif ($storageConfig -and -not $storageConfig.PSObject.Properties['Backups']) {
                    # Older configuration (or not yet built) where Backups property is missing entirely
                    Write-PSmmHost '  No backup configuration defined for this storage group' -ForegroundColor DarkGray
                } elseif ($storageConfig.PSObject.Properties['Backups'] -and ($null -eq $storageConfig.Backups -or $storageConfig.Backups.Count -eq 0)) {
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
    )    if ($null -eq $Projects -or $Projects.Count -eq 0) {
        return
    }

    $DriveProjects = @($Projects)

    # Get drive information from first project
    if ($DriveProjects.Count -eq 0) {
        return
    }

    $DriveInfo = $DriveProjects[0]

    # Determine colors and styling based on drive type
    $IsMaster = $DriveType -eq 'Master Drive'
    $BorderChar = if ($IsMaster) { [char]0x2550 } else { [char]0x2500 }  # ═ for Master, ─ for Backup
    $HeaderColor = if ($IsMaster) { $Config.UI.ANSI.FG.MasterDrive } else { $Config.UI.ANSI.FG.BackupDrive }
    $RoleColor = if ($IsMaster) { $Config.UI.ANSI.FG.MasterDriveLight } else { $Config.UI.ANSI.FG.BackupDriveLight }

    # Display drive header with label and role
    $DriveHeaderColumns = @(
        @{
            Text = "$([string]::new($BorderChar, 18)) $DriveLabel $([string]::new($BorderChar, 18))"
            Width = $Config.UI.Width
            Alignment = 'c'
            TextColor = $HeaderColor
            Bold = $true
        }
    )
    Format-UI -Columns $DriveHeaderColumns -Width $Config.UI.Width -Config $Config

    # Display role with icon
    $RoleIcon = if ($IsMaster) { '💿' } else { '📀' }
    $RoleText = "$RoleIcon Role: $DriveType"
    if ($IsFallback) {
        $RoleText += " (Automatic Fallback)"
        $RoleColor = $Config.UI.ANSI.FG.Warning
    }
    $RoleColumns = @(
        @{
            Text = $RoleText
            Width = $Config.UI.Width
            Alignment = 'c'
            TextColor = $RoleColor
            Bold = $true
        }
    )
    Format-UI -Columns $RoleColumns -Width $Config.UI.Width -Config $Config

    # Calculate space usage percentage
    $UsedPercent = if ($DriveInfo.TotalSpace -gt 0) {
        [math]::Round(($DriveInfo.UsedSpace / $DriveInfo.TotalSpace) * 100, 1)
    } else { 0 }
    $FreePercent = if ($DriveInfo.TotalSpace -gt 0) {
        [math]::Round(($DriveInfo.FreeSpace / $DriveInfo.TotalSpace) * 100, 1)
    } else { 0 }

    # Define metadata items in optimal sorted order for two-column display
    $MetadataItems = @(
        @{ Key = 'Drive Letter'; Value = $DriveInfo.Drive; Color = $Config.UI.ANSI.FG.Accent }
        @{ Key = 'Serial Number'; Value = $DriveInfo.SerialNumber; Color = $Config.UI.ANSI.FG.Neutral2 }
        @{ Key = 'Label'; Value = $DriveInfo.Label; Color = $Config.UI.ANSI.FG.Warning }
        @{ Key = 'Manufacturer'; Value = $DriveInfo.Manufacturer; Color = $Config.UI.ANSI.FG.Neutral1 }
        @{ Key = 'Model'; Value = $DriveInfo.Model; Color = $Config.UI.ANSI.FG.Neutral1 }
        @{ Key = 'File System'; Value = $DriveInfo.FileSystem; Color = $Config.UI.ANSI.FG.Info }
        @{ Key = 'Partition Kind'; Value = $DriveInfo.PartitionKind; Color = $Config.UI.ANSI.FG.Neutral2 }
        @{ Key = 'Total Space'; Value = "$([math]::Round($DriveInfo.TotalSpace, 2)) GB"; Color = $Config.UI.ANSI.FG.Info }
        @{ Key = 'Used Space'; Value = "$([math]::Round($DriveInfo.UsedSpace, 2)) GB ($UsedPercent%)"; Color = $Config.UI.ANSI.FG.Secondary }
        @{ Key = 'Free Space'; Value = "$([math]::Round($DriveInfo.FreeSpace, 2)) GB ($FreePercent%)"; Color = $Config.UI.ANSI.FG.Success }
        @{
            Key = 'Health Status'
            Value = $DriveInfo.HealthStatus
            Color = switch ($DriveInfo.HealthStatus) {
                'Healthy' { $Config.UI.ANSI.FG.Success }
                'Warning' { $Config.UI.ANSI.FG.Warning }
                'Unhealthy' { $Config.UI.ANSI.FG.Error }
                default { $Config.UI.ANSI.FG.Neutral1 }
            }
        }
        @{ Key = 'Projects'; Value = @($DriveProjects | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) }).Count; Color = $Config.UI.ANSI.FG.Neutral1 }
    )

    # Display metadata in side-by-side two-column layout centered
    $contentWidth = 76  # Optimized width for metadata display

    for ($i = 0; $i -lt $MetadataItems.Count; $i += 2) {
        $LeftItem = $MetadataItems[$i]
        $RightItem = if ($i + 1 -lt $MetadataItems.Count) { $MetadataItems[$i + 1] } else { $null }

        $MetadataColumns = @(
            @{
                Text = "$($LeftItem.Key):"
                Width = 17
                Alignment = 'r'
                TextColor = $Config.UI.ANSI.FG.Accent
                Bold = $false
            }
            @{
                Text = $LeftItem.Value
                Width = 21
                Alignment = 'l'
                TextColor = $LeftItem.Color
                Bold = $false
            }
        )

        if ($RightItem) {
            $MetadataColumns += @(
                @{
                    Text = "$($RightItem.Key):"
                    Width = 17
                    Alignment = 'r'
                    TextColor = $Config.UI.ANSI.FG.Accent
                    Bold = $false
                }
                @{
                    Text = $RightItem.Value
                    Width = 21
                    Alignment = 'l'
                    TextColor = $RightItem.Color
                    Bold = $false
                }
            )
        }

        # Generate the line (Format-UI handles output directly)
        Format-UI -Columns $MetadataColumns -Width $contentWidth -ColumnSeparator ' ' -Config $Config | Out-Null
    }

    # Projects header
    $ProjectsColumns = @(
        @{
            Text = "$([string]::new([char]0x2500, 7)) PROJECTS $([string]::new([char]0x2500, 7))"
            Width = $Config.UI.Width
            Alignment = 'c'
            TextColor = $Config.UI.ANSI.FG.Success
            Bold = $true
            Italic = $true
        }
    )
    Format-UI -Columns $ProjectsColumns -Width $Config.UI.Width -Config $Config
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
            $Config.UI.ANSI.FG.MasterDriveLight
        } else {
            $Config.UI.ANSI.FG.BackupDriveDark
        }

        $ProjectColumns = @(
            @{
                Text = "[$Prefix$Count]"
                Width = 10
                Alignment = 'c'
                TextColor = $ProjectNumColor
                Bold = $true
            }
            @{
                Text = $DisplayName
                Width = 20
                Alignment = 'l'
                TextColor = $Config.UI.ANSI.FG.Neutral1
            }
            @{
                Text = $Project.Path
                Width = 'auto'
                Alignment = 'l'
                TextColor = $Config.UI.ANSI.FG.Neutral3
            }
        )
        Format-UI -Columns $ProjectColumns -Width $Config.UI.Width -Config $Config
    }

    if ($Count -eq 0) {
        $NoProjectsColumns = @(
            @{
                Text = 'No projects found on this drive.'
                Width = $Config.UI.Width
                Alignment = 'c'
                TextColor = $Config.UI.ANSI.FG.Neutral4
                Italic = $true
            }
        )
        Format-UI -Columns $NoProjectsColumns -Width $Config.UI.Width -Config $Config
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
    )    # Check for running processes
    $ProcMariaDB = $null
    $ProcDigiKam = $null

    if ($Config.Projects.ContainsKey('Current')) {
        if ($Config.Projects.Current.ContainsKey('Databases')) {
            $allMariaDB = $Process.GetProcess('mariadbd')
            if ($null -ne $allMariaDB) {
                $ProcMariaDB = $allMariaDB | Where-Object { $_.CommandLine -like "*$($Config.Projects.Current.Databases)*" }
            }
        }

        if ($Config.Projects.Current.ContainsKey('Config')) {
            $allDigiKam = $Process.GetProcess('digikam')
            if ($null -ne $allDigiKam) {
                $ProcDigiKam = $allDigiKam | Where-Object { $_.CommandLine -like "*$($Config.Projects.Current.Config)*" }
            }
        }
    }

    $ProcessesRunning = ($null -ne $ProcMariaDB) -or ($null -ne $ProcDigiKam)

    if (-not $ProcessesRunning) {
        # Display backup and database management options when no processes are running
        try {
            Show-ProjectMenuOptions_NoProcesses -Config $Config
        }
        catch {
            Write-Warning "Show-ProjectMenuOptions_NoProcesses failed: $_"
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
        @{
            Text = '[R] Return to previous menu'
            Width = 'auto'
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Info
        }
        @{
            Text = 'Quit [Q]'
            Width = 'auto'
            Alignment = 'r'
            TextColor = $Config.UI.ANSI.FG.Info
        }
    )

    $borderChar = $PSSpecialChar.SixPointStar

    Format-UI -Columns $ReturnColumns -Width $Config.UI.Width -Border $borderChar -Config $Config
}

<#
.SYNOPSIS
    Displays menu options when no processes are running.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Show-ProjectMenuOptions_NoProcesses {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function displays multiple menu options')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )    # Note: Backup operations removed - not yet implemented

    # DigiKam management
    $DigiKamColumns = @(
        @{
            Text = '[1] Start digiKam'
            Width = $Config.UI.Width
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Primary
            Bold = $true
        }
    )
    Format-UI -Columns $DigiKamColumns -Width $Config.UI.Width -Config $Config
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
    )    Write-PSmmHost ''

    # Media overview
    $OverviewColumns = @(
        @{
            Text = '[11] Published Media Overview'
            Width = $Config.UI.Width
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Info
        }
    )
    Format-UI -Columns $OverviewColumns -Width $Config.UI.Width -Config $Config

    Write-PSmmHost ''

    # Pricing options
    $PricingColumns = @(
        @{
            Text = '[2]  Pricing    : Get prices for media files'
            Width = $Config.UI.Width
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Accent
        }
    )
    Format-UI -Columns $PricingColumns -Width $Config.UI.Width -Config $Config

    $BundleColumns = @(
        @{
            Text = '[22] Bundle  : Get prices for bundles media files'
            Width = $Config.UI.Width
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Accent
        }
    )
    Format-UI -Columns $BundleColumns -Width $Config.UI.Width -Config $Config

    $NewPricingColumns = @(
        @{
            Text = '[2n] Pricing : NEW Get prices for media files'
            Width = $Config.UI.Width
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.AccentLight
        }
    )
    Format-UI -Columns $NewPricingColumns -Width $Config.UI.Width -Config $Config

    Write-PSmmHost ''

    # Media processing plugins
    $ImageMagickColumns = @(
        @{
            Text = '[3] ImageMagick: Convert and process Images'
            Width = $Config.UI.Width
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Secondary
        }
    )
    Format-UI -Columns $ImageMagickColumns -Width $Config.UI.Width -Config $Config

    $FfmpegColumns = @(
        @{
            Text = '[4] FFmpeg     : Rebuild Chunk Offset Table (mp4, mov)'
            Width = $Config.UI.Width
            Alignment = 'l'
            TextColor = $Config.UI.ANSI.FG.Secondary
        }
    )
    Format-UI -Columns $FfmpegColumns -Width $Config.UI.Width -Config $Config

    Write-PSmmHost ''

    # Stop processes option
    $StopColumns = @(
        @{
            Text = 'Stop digiKam Processes [S]'
            Width = $Config.UI.Width
            Alignment = 'r'
            TextColor = $Config.UI.ANSI.FG.Error
        }
    )
    Format-UI -Columns $StopColumns -Width $Config.UI.Width -Config $Config
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
    )    $StorageColumns = @(
        @{
            Text = '[1] Show Storage Information'
                        TextColor = $Config.UI.ANSI.FG.Info
            Width = $Config.UI.Width
            Alignment = 'l'
        }
    )
    Format-UI -Columns $StorageColumns -Width $Config.UI.Width -Config $Config

    $ConfigColumns = @(
        @{
            Text = '[2] Show Runtime Configuration'
                        TextColor = $Config.UI.ANSI.FG.Info
            Width = $Config.UI.Width
            Alignment = 'l'
        }
    )
    Format-UI -Columns $ConfigColumns -Width $Config.UI.Width -Config $Config

    Write-PSmmHost ''

    $ReturnColumns = @(
        @{
            Text = '[R] Return to previous menu'
            Width = 'auto'
            Alignment = 'l'
        }
        @{
            Text = 'Quit [Q]'
            Width = 'auto'
            Alignment = 'r'
        }
    )
    Format-UI -Columns $ReturnColumns -Width $Config.UI.Width -Border 'Box' -Config $Config
}

#endregion ########## System Info ##########
