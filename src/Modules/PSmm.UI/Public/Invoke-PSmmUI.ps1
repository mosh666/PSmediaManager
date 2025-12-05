<#
.SYNOPSIS
    Displays and manages the main interactive menu for PSmediaManager.

.DESCRIPTION
    Main UI loop that displays the application menu, handles user input, and
    routes to appropriate sub-menus or actions. Supports system information,
    project management, and application settings.

.PARAMETER Config
    The AppConfiguration object containing application state and settings.


.EXAMPLE
    Invoke-PSmmUI -Config $appConfig

    Launches the UI using the AppConfiguration object.


.NOTES
    This function runs in an interactive loop until the user chooses to quit (Q).
    Requires all Show-* menu functions to be available.
#>


#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Invoke-PSmmUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Process,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $PathProvider
    )

    # PS 7.5.4+ baseline and entrypoint import order guarantee core types are available
    # Defensive: ensure AppConfiguration class is loaded (runtime resilience against import order issues)
    try {
        $appConfigTypeLoaded = [System.AppDomain]::CurrentDomain.GetAssemblies().GetTypes() | Where-Object { $_.Name -eq 'AppConfiguration' } | Select-Object -First 1
    }
    catch {
        $appConfigTypeLoaded = $null
    }
    if (-not $appConfigTypeLoaded) {
        try {
            $uiPublicDir = $PSScriptRoot
            $uiModuleRoot = Split-Path -Path $uiPublicDir -Parent  # PSmm.UI module root
            $modulesRoot  = Split-Path -Path $uiModuleRoot -Parent # Modules root containing PSmm
            $classesPath  = Join-Path -Path $modulesRoot -ChildPath 'PSmm\Classes\AppConfiguration.ps1'
            if (Test-Path -Path $classesPath -PathType Leaf) {
                . $classesPath
                if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                    Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message 'AppConfiguration class dynamically loaded (fallback)' -File
                }
            }
        }
        catch {
            if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level WARNING -Context 'Invoke-PSmmUI' -Message "Failed dynamic AppConfiguration load: $_" -File -Console
            }
        }
    }

    try {
        Write-Verbose 'Starting PSmediaManager UI...'
        # Ensure at least one visible line even if formatting fails
        Write-PSmmHost '[UI] Starting interactive session...' -ForegroundColor Green
        if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
            Write-PSmmLog -Level NOTICE -Context 'Invoke-PSmmUI' -Message 'UI interactive session starting' -File
        }

        # Validate storage configuration and update drive availability using typed configuration
        Write-Verbose 'Validating storage configuration...'
        try {
            Confirm-Storage -Config $Config
        }
        catch {
            Write-PSmmLog -Level WARNING -Context 'Invoke-PSmmUI' `
                -Message 'Storage validation encountered issues' -Console -File
        }

        # Track selected storage group (default to Storage Group 1)
        $SelectedStorageGroup = '1'

        do {
            # Display main menu
            try {
                Clear-Host
            }
            catch {
                Write-Verbose 'Clear-Host not supported by current host; continuing without clearing screen.'
            }
            if ($Config.Parameters.Debug -or $Config.Parameters.Dev) { '1234567890' * 8 } # Visual separator for debugging
            if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message 'Rendering header' -File
            }
            try {
                Show-Header -Config $Config -ShowProject $false -StorageGroupFilter $SelectedStorageGroup
                if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                    Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message 'Header rendered' -File
                }
            }
            catch {
                if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                    Write-PSmmLog -Level ERROR -Context 'Invoke-PSmmUI' -Message ("Header rendering failed: {0}" -f $_) -ErrorRecord $_ -File
                }
                throw
            }

            # Retrieve projects once per loop iteration (centralized) and pass downstream
            $loopProjects = $null
            try {
                Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message "Loading projects. Storage groups: $($Config.Storage.Keys.Count)" -File
                $loopProjects = Get-PSmmProjects -Config $Config -FileSystem $FileSystem
                $masterCount = if ($loopProjects.Master) { $loopProjects.Master.Keys.Count } else { 0 }
                $backupCount = if ($loopProjects.Backup) { $loopProjects.Backup.Keys.Count } else { 0 }
                Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message "Projects loaded. Master drives: $masterCount, Backup drives: $backupCount" -File
            }
            catch {
                Write-PSmmLog -Level ERROR -Context 'Invoke-PSmmUI' -Message "Project retrieval failed: $_" -ErrorRecord $_ -File
                $loopProjects = @{ Master = @{}; Backup = @{} }
            }

            try {
                Show-MenuMain -Config $Config -StorageGroup $SelectedStorageGroup -Projects $loopProjects
                Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message 'Show-MenuMain completed successfully' -File
            }
            catch {
                Write-PSmmLog -Level ERROR -Context 'Invoke-PSmmUI' -Message "Show-MenuMain failed: $_" -ErrorRecord $_ -File
                throw
            }

            if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message 'Rendering footer' -File
            }
            try {
                Show-Footer -Config $Config
                if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                    Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message 'Footer rendered' -File
                }
            }
            catch {
                if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                    Write-PSmmLog -Level ERROR -Context 'Invoke-PSmmUI' -Message ("Footer rendering failed: {0}" -f $_) -ErrorRecord $_ -File
                }
                throw
            }
            if ($Config.Parameters.Debug -or $Config.Parameters.Dev) { '1234567890' * 10 } # Visual separator for debugging

            Write-Host ''
            if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message 'Awaiting user selection' -File
            }
            $Selection = Read-Host 'Please make a selection'

            # Treat empty / whitespace-only input (plain Enter) as an invalid selection without exiting the UI loop.
            if ([string]::IsNullOrWhiteSpace($Selection)) {
                Show-InvalidSelection
                continue
            }

            # Process menu selection
            switch ($Selection) {
                'I' {
                    # System Information sub-menu
                    $sysInfoResult = Invoke-SystemInfoMenu -Config $Config

                    # Check if user quit from system info menu
                    if ($sysInfoResult -eq 'QUIT') {
                        $Selection = 'Q'
                        break
                    }
                }
                'S' {
                    # Storage Group selector
                    Write-Host ''
                    Write-PSmmHost 'Available Storage Groups:' -ForegroundColor Cyan

                    # Display each storage group with Master drive info
                    foreach ($groupKey in ($Config.Storage.Keys | Sort-Object)) {
                        $masterDrive = $Config.Storage.$groupKey.Master
                        if ($masterDrive) {
                            $driveInfo = "$($masterDrive.Label)"
                            if (-not [string]::IsNullOrWhiteSpace($masterDrive.DriveLetter)) {
                                $driveInfo += " ($($masterDrive.DriveLetter))"
                            }
                            Write-PSmmHost "  [$groupKey] $driveInfo" -ForegroundColor Cyan
                        }
                        else {
                            Write-PSmmHost "  [$groupKey] (No Master Drive)" -ForegroundColor DarkGray
                        }
                    }

                    Write-PSmmHost '  [A] Show All' -ForegroundColor Cyan
                    Write-Host ''
                    $GroupSelection = Read-Host 'Select Storage Group'

                    if ($GroupSelection -eq 'A' -or [string]::IsNullOrWhiteSpace($GroupSelection)) {
                        $SelectedStorageGroup = $null
                        Write-PSmmHost 'Showing all storage groups' -ForegroundColor Green
                    }
                    else {
                        # Find matching storage group key (handles string vs int comparison)
                        $MatchingKey = $Config.Storage.Keys | Where-Object { $_.ToString() -eq $GroupSelection.ToString() } | Select-Object -First 1

                        if ($MatchingKey) {
                            $SelectedStorageGroup = $MatchingKey
                            Write-PSmmHost "Filtering to Storage Group $MatchingKey" -ForegroundColor Green
                        }
                        else {
                            Write-Warning "Invalid storage group '$GroupSelection'. Available: $($Config.Storage.Keys -join ', ')"
                        }
                    }
                    Start-Sleep -Seconds 1
                }
                'C' {
                    # Create new project
                    try {
                        New-PSmmProject -Config $Config
                    }
                    catch {
                        Write-Warning "Failed to create project: $_"
                        Pause
                    }
                }
                'K' {
                    # Launch KeePassXC
                    try {
                        Write-Verbose 'Launching KeePassXC...'
                        $Process.StartProcess('KeePassXC.exe', @())
                    }
                    catch {
                        Write-Warning "Failed to start KeePassXC: $_"
                        Pause
                    }
                }

                'R' {
                    # Manage Storage (Edit/Add/Remove)
                    try {
                        $driveRoot = [System.IO.Path]::GetPathRoot($Config.Paths.Root)
                        if (-not [string]::IsNullOrWhiteSpace($driveRoot)) {
                            if (Get-Command Invoke-ManageStorage -ErrorAction SilentlyContinue) {
                                Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message "Storage groups before management: $($Config.Storage.Keys.Count)" -File
                                $null = Invoke-ManageStorage -Config $Config -DriveRoot $driveRoot
                                Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message "Storage groups after management: $($Config.Storage.Keys.Count)" -File
                                # After storage changes, ensure storage status is refreshed
                                if (Get-Command Confirm-Storage -ErrorAction SilentlyContinue) {
                                    Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message "Refreshing storage status" -File
                                    Confirm-Storage -Config $Config
                                    Write-PSmmLog -Level DEBUG -Context 'Invoke-PSmmUI' -Message "Storage status refreshed" -File
                                }
                            }
                            else {
                                Write-Warning 'Invoke-ManageStorage not available.'
                            }
                        }
                        else {
                            Write-Warning 'Unable to determine drive root for storage configuration.'
                        }
                    }
                    catch {
                        Write-Warning "Failed to manage storage: $_"
                    }
                    # No Pause here - ManageStorage handles its own pauses
                }

                'Q' {
                    # Quit application
                    Write-Verbose 'User selected Quit'
                    return
                }
                default {
                    # Check if it's a project selection (numeric or B## format where # are drive and project numbers)
                    if ($Selection -match '^\d+$' -or $Selection -match '(?i)^B\d{2,}$') {
                        try {
                            # Use already retrieved projects for mapping selection (no fallback fetch)
                            # $loopProjects is always set above (or to an empty structure on failure)
                            $Projects = $loopProjects
                            $SelectedProject = $null

                            # Determine which storage groups to include based on filter
                            $StorageGroupsToFilter = if ([string]::IsNullOrWhiteSpace($SelectedStorageGroup)) {
                                # Show all storage groups
                                $Config.Storage.Keys | Sort-Object
                            }
                            else {
                                # Show only the specified storage group
                                $MatchingKey = $Config.Storage.Keys | Where-Object { $_.ToString() -eq $SelectedStorageGroup.ToString() } | Select-Object -First 1
                                if ($MatchingKey) {
                                    @($MatchingKey)
                                }
                                else {
                                    $Config.Storage.Keys | Sort-Object
                                }
                            }

                            # Determine if it's a backup project (B prefix, case-insensitive)
                            # Format: B + BackupId + ProjectNumber (e.g., B21 = BackupId 2, Project 1)
                            $IsBackup = $Selection -match '(?i)^B'

                            if ($IsBackup) {
                                # Parse the backup selection format: B[BackupId][ProjectNum]
                                # Example: B21 = BackupId 2, Project 1
                                $NumberPart = $Selection -replace '(?i)^B', ''
                                if ($NumberPart.Length -lt 2) {
                                    Write-Warning "Invalid backup project format. Use B[BackupId][ProjectNumber] (e.g., B21 for Backup 2, Project 1)"
                                    Pause
                                    continue
                                }

                                # Extract backup ID (first digit) and project number (remaining digits)
                                $BackupId = [int]$NumberPart.Substring(0, 1)
                                $ProjectNumber = [int]$NumberPart.Substring(1)

                                # Find the backup drive with matching BackupId
                                $TargetDriveLabel = $null

                                # Check if Backup projects exist before accessing
                                if ($Projects.ContainsKey('Backup') -and $null -ne $Projects.Backup -and $Projects.Backup.Count -gt 0) {
                                    foreach ($storageGroupKey in $StorageGroupsToFilter) {
                                        foreach ($driveLabel in ($Projects.Backup.Keys | Sort-Object)) {
                                            $driveProjectArray = $Projects.Backup[$driveLabel]
                                            if ($driveProjectArray -and $driveProjectArray.Count -gt 0) {
                                                $firstProject = $driveProjectArray | Select-Object -First 1
                                                # Match by BackupId instead of sequential counter
                                                if ($firstProject.StorageGroup.ToString() -eq $storageGroupKey.ToString() -and
                                                    $firstProject.BackupId -eq $BackupId) {
                                                    $TargetDriveLabel = $driveLabel
                                                    break
                                                }
                                            }
                                        }
                                        if ($TargetDriveLabel) { break }
                                    }
                                }

                                # Select the project from the target drive
                                if ($TargetDriveLabel) {
                                    $driveProjectArray = $Projects.Backup[$TargetDriveLabel]
                                    $ValidProjects = @($driveProjectArray | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) })

                                    if ($ProjectNumber -gt 0 -and $ProjectNumber -le $ValidProjects.Count) {
                                        $SelectedProject = $ValidProjects[$ProjectNumber - 1]
                                    }
                                }
                            }
                            else {
                                # Map to master projects (respecting storage group filter)
                                $ProjectIndex = [int]$Selection
                                $MasterProjects = @()

                                # Check if Master projects exist before accessing
                                if ($Projects.ContainsKey('Master') -and $null -ne $Projects.Master -and $Projects.Master.Count -gt 0) {
                                    foreach ($storageGroupKey in $StorageGroupsToFilter) {
                                        foreach ($driveLabel in ($Projects.Master.Keys | Sort-Object)) {
                                            $driveProjectArray = $Projects.Master[$driveLabel]
                                            if ($driveProjectArray) {
                                                foreach ($proj in $driveProjectArray) {
                                                    if (-not [string]::IsNullOrWhiteSpace($proj.Name) -and
                                                        $proj.StorageGroup.ToString() -eq $storageGroupKey.ToString()) {
                                                        $MasterProjects += $proj
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                if ($ProjectIndex -gt 0 -and $ProjectIndex -le $MasterProjects.Count) {
                                    $SelectedProject = $MasterProjects[$ProjectIndex - 1]
                                }
                            }

                            if ($SelectedProject) {
                                # Select the project, passing the SerialNumber to ensure correct disk selection
                                Select-PSmmProject -Config $Config -pName $SelectedProject.Name -SerialNumber $SelectedProject.SerialNumber -FileSystem $FileSystem -PathProvider $PathProvider

                                # Display the project menu
                                $projectMenuResult = Invoke-ProjectMenu -Config $Config

                                # Check if user quit from project menu
                                if ($projectMenuResult -eq 'QUIT') {
                                    $Selection = 'Q'
                                    break
                                }
                            }
                            else {
                                Write-Warning "Invalid project selection: $Selection"
                                Pause
                            }
                        }
                        catch {
                            Write-Warning "Failed to select project: $_"
                            Pause
                        }
                    }
                    else {
                        # Invalid selection
                        Show-InvalidSelection
                    }
                }
            }
        } while ($Selection -ne 'Q')
    }
    catch {
        Write-Error "UI error: $_"
        throw
    }
    finally {
        Write-Verbose 'PSmediaManager UI closed'
    }
}

<#
.SYNOPSIS
    Displays and manages the System Information sub-menu.

.DESCRIPTION
    Internal function that displays system information options and handles
    user navigation within the system info menu.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Invoke-SystemInfoMenu {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    do {
        Clear-Host
        Show-Header -Config $Config -ShowStorageErrors $false
        Show-Menu_SysInfo -Config $Config

        Write-Host ''
        $SubSelection = Read-Host 'Please make a selection'

        switch ($SubSelection) {
            '1' {
                # Show Storage
                Write-Host ''
                Show-StorageInfo -Config $Config -ShowDetails
                Pause
            }
            '2' {
                # Show Runtime Config
                Write-Host ''
                try {
                    # Use injected services for path/content operations
                    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                    $tempPath = $PathProvider.CombinePath(@($env:TEMP, "PSmm-RuntimeConfig-$timestamp.psd1"))
                    Export-SafeConfiguration -Configuration $Config -Path $tempPath -FileSystem $FileSystem
                    $configContent = $FileSystem.GetContent($tempPath)
                    $configContent | Write-Output
                    Write-Output ""
                    Write-Output "Configuration exported to: $tempPath"
                }
                catch {
                    Write-Warning "Failed to export configuration: $_"
                }
                Pause
            }
            'R' {
                # Return to main menu
                break
            }
            'Q' {
                # Quit application - return signal to main loop
                return 'QUIT'
            }
            default {
                # Invalid selection
                Show-InvalidSelection
            }
        }
    } while ($SubSelection -ne 'R')

    # Return to main menu (user pressed R)
    return 'RETURN'
}

<#
.SYNOPSIS
    Displays and manages the Project sub-menu.

.DESCRIPTION
    Internal function that displays project-specific options and handles
    user navigation within the project menu.

.PARAMETER Run
    The runtime configuration hashtable.
#>
function Invoke-ProjectMenu {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config
    )

    do {
        Clear-Host
        try {
            Show-Header -Config $Config -ShowStorageErrors $false
        }
        catch {
            Write-Warning "Header display failed: $_"
        }

        try {
            Show-Menu_Project -Config $Config -Process $Process
        }
        catch {
            Write-Warning "Project menu display failed: $_"
            Write-PSmmHost "Error details: $($_.Exception.Message)" -ForegroundColor Red
            Write-PSmmHost "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
            Pause
        }

        Write-Host ''
        $SubSelection = Read-Host 'Please make a selection'

        # Check for running processes to control menu actions
        $ProcMariaDB = $null
        $ProcDigiKam = $null

        if ($null -ne $Config.Projects -and $Config.Projects.ContainsKey('Current')) {
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

        switch ($SubSelection) {
            '1' {
                # Start digiKam
                try {
                    if (Get-Command -Name Start-PSmmdigiKam -ErrorAction SilentlyContinue) {
                        Start-PSmmdigiKam -Config $Config -FileSystem $FileSystem -PathProvider $PathProvider -Process $Process
                    }
                    else {
                        Write-Host ''
                        Write-Warning 'Start digiKam function is not yet implemented'
                    }
                    Pause
                }
                catch {
                    Write-Warning "Failed to start digiKam: $_"
                    Pause
                }
            }

            'S' {
                # Stop digiKam Processes
                if ($ProcessesRunning) {
                    try {
                        if (Get-Command -Name Stop-PSmmdigiKam -ErrorAction SilentlyContinue) {
                            Stop-PSmmdigiKam -Config $Config -FileSystem $FileSystem -PathProvider $PathProvider -Process $Process
                        }
                        else {
                            Write-Host ''
                            Write-Warning 'Stop digiKam function is not yet implemented'
                        }
                        Pause
                    }
                    catch {
                        Write-Warning "Failed to stop digiKam: $_"
                        Pause
                    }
                }
                else {
                    Write-Warning 'No digiKam processes are running'
                    Pause
                }
            }
            'R' {
                # Return to main menu
                break
            }
            'Q' {
                # Quit application - return signal to main loop
                return 'QUIT'
            }
            default {
                # Invalid selection
                Show-InvalidSelection
            }
        }
    } while ($SubSelection -ne 'R')

    # Return to main menu (user pressed R)
    return 'RETURN'
}
