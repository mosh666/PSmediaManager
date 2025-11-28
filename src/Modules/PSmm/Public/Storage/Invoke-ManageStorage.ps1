<#
.SYNOPSIS
    Interactive menu for managing storage groups (Edit/Add/Remove).

.DESCRIPTION
    Provides a submenu interface for storage management operations:
    - [E]dit: Modify an existing storage group
    - [A]dd: Configure a new storage group
    - [R]emove: Delete one or more storage groups
    - [B]ack: Return to main menu

.PARAMETER Config
    The AppConfiguration object containing application state.

.PARAMETER DriveRoot
    The root path of the drive where PSmm.Storage.psd1 is stored.

.PARAMETER NonInteractive
    Suppresses all interactive prompts. Used for testing.

.EXAMPLE
    Invoke-ManageStorage -Config $config -DriveRoot 'D:\'

.NOTES
    Respects MEDIA_MANAGER_TEST_MODE and MEDIA_MANAGER_TEST_INPUTS for testing.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Invoke-ManageStorage {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AppConfiguration]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DriveRoot,

        [switch]$NonInteractive
    )

    $logAvail = Get-Command Write-PSmmLog -ErrorAction SilentlyContinue
    function Write-ManageLog([string]$level, [string]$context, [string]$msg) {
        if ($logAvail) { Write-PSmmLog -Level $level -Context $context -Message $msg -File }
        else { Write-Verbose "$context : $msg" }
    }

    # Test input feed for non-interactive testing
    $testInputs = $null
    $testInputIndex = 0
    try {
        if (-not [string]::IsNullOrWhiteSpace($env:MEDIA_MANAGER_TEST_INPUTS)) {
            $parsed = $env:MEDIA_MANAGER_TEST_INPUTS | ConvertFrom-Json -ErrorAction Stop
            if ($parsed -is [System.Array]) { $testInputs = [string[]]$parsed }
        }
    } catch { $testInputs = $null }

    # In test mode without inputs, abort early
    if ([string]::Equals($env:MEDIA_MANAGER_TEST_MODE, '1', [System.StringComparison]::OrdinalIgnoreCase) -and (-not $NonInteractive)) {
        if (-not $testInputs -or $testInputs.Count -eq 0) { return $false }
    }

    function Read-ManageInput([string]$Prompt) {
        if ($testInputs -and ($testInputIndex -lt $testInputs.Count)) {
            $val = [string]$testInputs[$testInputIndex]
            $testInputIndex++
            return $val
        }
        return Read-Host -Prompt $Prompt
    }

    :ManageLoop while ($true) {
        if (-not $NonInteractive) {
            Write-Information ''
            Write-PSmmHost '=== Manage Storage ===' -ForegroundColor Cyan
            Write-Information ''

            $menuOptions = @()
            $optionMap = @{}
            $idx = 1
            $hasStorage = ($null -ne $Config.Storage -and $Config.Storage.Keys.Count -gt 0)
            if ($hasStorage) {
                $menuOptions += "${idx}. Edit Existing Group"
                $optionMap[$idx] = 'E'
                $idx++
            }
            $menuOptions += "${idx}. Add New Group"
            $optionMap[$idx] = 'A'
            $idx++
            if ($hasStorage) {
                $menuOptions += "${idx}. Remove Group(s)"
                $optionMap[$idx] = 'R'
                $idx++
            }
            $menuOptions += "${idx}. Back to Main Menu"
            $optionMap[$idx] = 'B'

            Write-PSmmHost 'Available options:' -ForegroundColor Cyan
            foreach ($opt in $menuOptions) { Write-PSmmHost $opt -ForegroundColor White }
            Write-Information ''

            if (-not $hasStorage) {
                Write-PSmmHost 'No storage groups configured. Only Add and Back are available.' -ForegroundColor Yellow
            }

            $promptMsg = 'Select an option by number (see above)'
            $selection = Read-ManageInput $promptMsg

            if ($selection -notmatch '^[0-9]+$' -or -not $optionMap.ContainsKey([int]$selection)) {
                Write-PSmmHost 'Invalid selection. Please choose a valid number from the menu above.' -ForegroundColor Yellow
                if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                continue
            }
            $chosen = $optionMap[[int]$selection]

            switch -Regex ($chosen) {
                '^(?i)e$' {
                    # Edit existing group
                    Write-ManageLog -level 'DEBUG' -context 'ManageStorage' -msg 'User selected Edit'

                    # List groups
                    if ($null -eq $Config.Storage -or $Config.Storage.Keys.Count -eq 0) {
                        Write-PSmmHost 'No storage groups configured.' -ForegroundColor Yellow
                        if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                        continue
                    }

                    Write-Information ''
                    Write-PSmmHost 'Select a group to edit:' -ForegroundColor Cyan
                    Write-Information ''
                    foreach ($groupId in ($Config.Storage.Keys | Sort-Object {[int]$_})) {
                        $group = $Config.Storage[$groupId]
                        $displayName = if ($group.DisplayName) { $group.DisplayName } else { "Storage Group $groupId" }
                        Write-PSmmHost "  [$groupId] $displayName" -ForegroundColor White

                        # Show Master drive
                        if ($group.Master) {
                            $masterLabel = if ($group.Master.Label) { $group.Master.Label } else { 'N/A' }
                            $masterSerial = if ($group.Master.SerialNumber) { $group.Master.SerialNumber } else { 'N/A' }
                            Write-PSmmHost "      Master: $masterLabel (S/N: $masterSerial)" -ForegroundColor Gray
                        }

                        # Show Backup drives
                        if ($group.Backups -and $group.Backups.Keys.Count -gt 0) {
                            foreach ($backupId in ($group.Backups.Keys | Sort-Object {[int]$_})) {
                                $backup = $group.Backups[$backupId]
                                $backupLabel = if ($backup.Label) { $backup.Label } else { 'N/A' }
                                $backupSerial = if ($backup.SerialNumber) { $backup.SerialNumber } else { 'N/A' }
                                Write-PSmmHost "      Backup $backupId`: $backupLabel (S/N: $backupSerial)" -ForegroundColor Gray
                            }
                        }
                        Write-Information ''
                    }
                    Write-Information ''

                    $groupChoice = Read-ManageInput 'Enter group number or B to go back'
                    if ($groupChoice -match '^(?i)b$') { continue }

                    if ($groupChoice -notmatch '^[0-9]+$' -or -not $Config.Storage.ContainsKey($groupChoice)) {
                        Write-PSmmHost 'Invalid group selection.' -ForegroundColor Yellow
                        if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                        continue
                    }

                    # Call wizard in Edit mode
                    try {
                        $result = Invoke-StorageWizard -Config $Config -DriveRoot $DriveRoot -Mode 'Edit' -GroupId $groupChoice
                        if ($result) {
                            Confirm-Storage -Config $Config
                            Write-PSmmHost 'Storage group updated successfully.' -ForegroundColor Green
                        }
                        else {
                            Write-PSmmHost 'Edit cancelled or no changes made.' -ForegroundColor Yellow
                        }
                    }
                    catch {
                        Write-ManageLog -level 'ERROR' -context 'ManageStorage' -msg "Failed to edit group: $_"
                        Write-PSmmHost "Failed to edit group: $_" -ForegroundColor Red
                    }
                    if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                }

                '^(?i)a$' {
                    # Add new group
                    Write-ManageLog -level 'DEBUG' -context 'ManageStorage' -msg 'User selected Add'

                    try {
                        $result = Invoke-StorageWizard -Config $Config -DriveRoot $DriveRoot -Mode 'Add'
                        if ($result) {
                            Confirm-Storage -Config $Config
                            Write-PSmmHost 'New storage group added successfully.' -ForegroundColor Green
                        }
                        else {
                            Write-PSmmHost 'Add cancelled or no changes made.' -ForegroundColor Yellow
                        }
                    }
                    catch {
                        Write-ManageLog -level 'ERROR' -context 'ManageStorage' -msg "Failed to add group: $_"
                        Write-PSmmHost "Failed to add group: $_" -ForegroundColor Red
                    }
                    if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                }

                '^(?i)r$' {
                    # Remove group(s)
                    Write-ManageLog -level 'DEBUG' -context 'ManageStorage' -msg 'User selected Remove'

                    if ($null -eq $Config.Storage -or $Config.Storage.Keys.Count -eq 0) {
                        Write-PSmmHost 'No storage groups configured.' -ForegroundColor Yellow
                        if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                        continue
                    }

                    Write-Information ''
                    Write-PSmmHost 'Select group(s) to remove:' -ForegroundColor Cyan
                    Write-Information ''
                    foreach ($groupId in ($Config.Storage.Keys | Sort-Object {[int]$_})) {
                        $group = $Config.Storage[$groupId]
                        $displayName = if ($group.DisplayName) { $group.DisplayName } else { "Storage Group $groupId" }
                        Write-PSmmHost "  [$groupId] $displayName" -ForegroundColor White

                        # Show Master drive
                        if ($group.Master) {
                            $masterLabel = if ($group.Master.Label) { $group.Master.Label } else { 'N/A' }
                            $masterSerial = if ($group.Master.SerialNumber) { $group.Master.SerialNumber } else { 'N/A' }
                            Write-PSmmHost "      Master: $masterLabel (S/N: $masterSerial)" -ForegroundColor Gray
                        }

                        # Show Backup drives
                        if ($group.Backups -and $group.Backups.Keys.Count -gt 0) {
                            foreach ($backupId in ($group.Backups.Keys | Sort-Object {[int]$_})) {
                                $backup = $group.Backups[$backupId]
                                $backupLabel = if ($backup.Label) { $backup.Label } else { 'N/A' }
                                $backupSerial = if ($backup.SerialNumber) { $backup.SerialNumber } else { 'N/A' }
                                Write-PSmmHost "      Backup $backupId`: $backupLabel (S/N: $backupSerial)" -ForegroundColor Gray
                            }
                        }
                        Write-Information ''
                    }
                    Write-Information ''

                    $removeChoice = Read-ManageInput 'Enter numbers (e.g., 2,3) or B to go back'
                    if ($removeChoice -match '^(?i)b$') { continue }

                    $groupsToRemove = @()
                    $nums = $removeChoice -split '[, ]+' | Where-Object { $_ -match '^[0-9]+$' } | ForEach-Object { [string]$_ } | Select-Object -Unique
                    foreach ($n in $nums) {
                        if ($Config.Storage.ContainsKey($n)) {
                            $groupsToRemove += $n
                        }
                    }

                    if ($groupsToRemove.Count -eq 0) {
                        Write-PSmmHost 'No valid groups selected.' -ForegroundColor Yellow
                        if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                        continue
                    }

                    # Confirm removal
                    Write-Information ''
                    Write-PSmmHost "You are about to remove $($groupsToRemove.Count) group(s):" -ForegroundColor Yellow
                    foreach ($gid in $groupsToRemove) {
                        $g = $Config.Storage[$gid]
                        $dname = if ($g.DisplayName) { $g.DisplayName } else { "Storage Group $gid" }
                        Write-Information "  - Group $gid : $dname"
                    }
                    Write-Information ''
                    $confirm = Read-ManageInput 'Confirm removal? (Y/N)'
                    if ($confirm -notmatch '^(?i)y$') {
                        Write-PSmmHost 'Removal cancelled.' -ForegroundColor Yellow
                        if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                        continue
                    }

                    # Remove groups
                    try {
                        Remove-StorageGroup -Config $Config -DriveRoot $DriveRoot -GroupIds $groupsToRemove
                        Write-PSmmHost "Successfully removed $($groupsToRemove.Count) group(s)." -ForegroundColor Green
                    }
                    catch {
                        Write-ManageLog -level 'ERROR' -context 'ManageStorage' -msg "Failed to remove groups: $_"
                        Write-PSmmHost "Failed to remove groups: $_" -ForegroundColor Red
                    }
                    if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                }

                '^(?i)b$' {
                    # Back to main menu
                    Write-ManageLog -level 'DEBUG' -context 'ManageStorage' -msg 'User selected Back'
                    return $true
                }

                default {
                    Write-PSmmHost 'Invalid selection. Please choose E, A, R, or B.' -ForegroundColor Yellow
                    if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
                }
            }
        }
        else {
            # NonInteractive mode - not supported for manage menu
            Write-ManageLog -level 'WARNING' -context 'ManageStorage' -msg 'NonInteractive mode not supported for Manage Storage menu'
            return $false
        }
    }
}
