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
        [object]$Config,

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

    function Get-ConfigMemberValue {
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            $Object,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,

            [Parameter()]
            $Default = $null
        )

        if ($null -eq $Object) { return $Default }

        if ($Object -is [System.Collections.IDictionary]) {
            try {
                if ($Object.ContainsKey($Name)) { return $Object[$Name] }
            }
            catch {
                Write-Verbose "Get-ConfigMemberValue: ContainsKey('$Name') failed: $($_.Exception.Message)"
            }

            try {
                if ($Object.Contains($Name)) { return $Object[$Name] }
            }
            catch {
                Write-Verbose "Get-ConfigMemberValue: Contains('$Name') failed: $($_.Exception.Message)"
            }

            try {
                foreach ($k in $Object.Keys) {
                    if ($k -eq $Name) { return $Object[$k] }
                }
            }
            catch {
                Write-Verbose "Get-ConfigMemberValue: Enumerating dictionary keys for '$Name' failed: $($_.Exception.Message)"
            }
        }

        $prop = $Object.PSObject.Properties[$Name]
        if ($null -ne $prop) { return $prop.Value }

        return $Default
    }

    function Test-MapContainsKey {
        param(
            [Parameter(Mandatory)]
            [AllowNull()]
            $Map,

            [Parameter(Mandatory)]
            [AllowNull()]
            $Key
        )

        if ($null -eq $Map) { return $false }

        if ($Map -is [System.Collections.IDictionary]) {
            $containsKey = $Map.PSObject.Methods['ContainsKey']
            if ($containsKey) {
                try {
                    if ($Map.ContainsKey($Key)) { return $true }
                }
                catch {
                    Write-Verbose "Test-MapContainsKey: ContainsKey('$Key') failed: $($_.Exception.Message)"
                }
            }

            try {
                if ([bool]$Map.Contains($Key)) { return $true }
            }
            catch {
                Write-Verbose "Test-MapContainsKey: Contains('$Key') failed: $($_.Exception.Message)"
            }

            try {
                foreach ($k in $Map.Keys) {
                    if ($k -eq $Key) { return $true }
                }
            }
            catch { return $false }

            return $false
        }

        $containsKey = $Map.PSObject.Methods['ContainsKey']
        if ($containsKey) {
            try { return [bool]$Map.ContainsKey($Key) } catch { return $false }
        }

        return $false
    }

    $storageMap = Get-ConfigMemberValue -Object $Config -Name 'Storage' -Default $null
    if ($null -eq $storageMap -and $Config -is [System.Collections.IDictionary]) {
        # Allow passing a Storage-map directly in legacy/test scenarios
        $storageMap = $Config
    }
    if ($null -eq $storageMap) {
        $storageMap = @{}
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

    # Helper to skip Pause in test mode
    function Invoke-PauseIfInteractive {
        if (-not [string]::Equals($env:MEDIA_MANAGER_TEST_MODE, '1', [System.StringComparison]::OrdinalIgnoreCase)) {
            if (Get-Command Pause -ErrorAction SilentlyContinue) { Pause }
        }
    }

    function Read-ManageInput([string]$Prompt) {
        if ($testInputs) {
            if ($testInputIndex -lt $testInputs.Count) {
                $val = [string]$testInputs[$testInputIndex]
                $testInputIndex++
                return $val
            }
            # In test mode and the feed is exhausted, return Back-equivalent to avoid hanging on Read-Host
            if ([string]::Equals($env:MEDIA_MANAGER_TEST_MODE, '1', [System.StringComparison]::OrdinalIgnoreCase)) {
                return 'B'
            }
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
            $hasStorage = ($null -ne $storageMap -and $storageMap.Keys.Count -gt 0)
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
                Invoke-PauseIfInteractive
                continue
            }
            $chosen = $optionMap[[int]$selection]

            switch -Regex ($chosen) {
                '^(?i)e$' {
                    # Edit existing group
                    Write-ManageLog -level 'DEBUG' -context 'ManageStorage' -msg 'User selected Edit'

                    # List groups
                    if ($null -eq $storageMap -or $storageMap.Keys.Count -eq 0) {
                        Write-PSmmHost 'No storage groups configured.' -ForegroundColor Yellow
                        Invoke-PauseIfInteractive
                        continue
                    }

                    Write-Information ''
                    Write-PSmmHost 'Select a group to edit:' -ForegroundColor Cyan
                    Write-Information ''
                    foreach ($groupId in ($storageMap.Keys | Sort-Object {[int]$_})) {
                        $group = $storageMap[$groupId]
                        $displayNameValue = Get-ConfigMemberValue -Object $group -Name 'DisplayName' -Default ''
                        $displayName = if (-not [string]::IsNullOrWhiteSpace([string]$displayNameValue)) { [string]$displayNameValue } else { "Storage Group $groupId" }
                        Write-PSmmHost "  [$groupId] $displayName" -ForegroundColor White

                        # Show Master drive
                        $masterCfg = Get-ConfigMemberValue -Object $group -Name 'Master' -Default $null
                        if ($masterCfg) {
                            $masterLabelValue = Get-ConfigMemberValue -Object $masterCfg -Name 'Label' -Default ''
                            $masterSerialValue = Get-ConfigMemberValue -Object $masterCfg -Name 'SerialNumber' -Default ''
                            $masterLabel = if (-not [string]::IsNullOrWhiteSpace([string]$masterLabelValue)) { [string]$masterLabelValue } else { 'N/A' }
                            $masterSerial = if (-not [string]::IsNullOrWhiteSpace([string]$masterSerialValue)) { [string]$masterSerialValue } else { 'N/A' }
                            Write-PSmmHost "      Master: $masterLabel (S/N: $masterSerial)" -ForegroundColor Gray
                        }

                        # Show Backup drives
                        $backupsCfg = Get-ConfigMemberValue -Object $group -Name 'Backups' -Default $null
                        if ($null -eq $backupsCfg) { $backupsCfg = Get-ConfigMemberValue -Object $group -Name 'Backup' -Default $null }
                        if ($backupsCfg -is [System.Collections.IDictionary] -and $backupsCfg.Keys.Count -gt 0) {
                            foreach ($backupId in ($backupsCfg.Keys | Sort-Object { [int]$_ })) {
                                $backup = $backupsCfg[$backupId]
                                $backupLabelValue = Get-ConfigMemberValue -Object $backup -Name 'Label' -Default ''
                                $backupSerialValue = Get-ConfigMemberValue -Object $backup -Name 'SerialNumber' -Default ''
                                $backupLabel = if (-not [string]::IsNullOrWhiteSpace([string]$backupLabelValue)) { [string]$backupLabelValue } else { 'N/A' }
                                $backupSerial = if (-not [string]::IsNullOrWhiteSpace([string]$backupSerialValue)) { [string]$backupSerialValue } else { 'N/A' }
                                Write-PSmmHost "      Backup $backupId`: $backupLabel (S/N: $backupSerial)" -ForegroundColor Gray
                            }
                        }
                        Write-Information ''
                    }
                    Write-Information ''

                    $groupChoice = Read-ManageInput 'Enter group number or B to go back'
                    if ($groupChoice -match '^(?i)b$') { continue }

                    if ($groupChoice -notmatch '^[0-9]+$' -or -not (Test-MapContainsKey -Map $storageMap -Key $groupChoice)) {
                        Write-PSmmHost 'Invalid group selection.' -ForegroundColor Yellow
                        Invoke-PauseIfInteractive
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
                    Invoke-PauseIfInteractive
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
                    Invoke-PauseIfInteractive
                }

                '^(?i)r$' {
                    # Remove group(s)
                    Write-ManageLog -level 'DEBUG' -context 'ManageStorage' -msg 'User selected Remove'

                    if ($null -eq $storageMap -or $storageMap.Keys.Count -eq 0) {
                        Write-PSmmHost 'No storage groups configured.' -ForegroundColor Yellow
                        Invoke-PauseIfInteractive
                        continue
                    }

                    Write-Information ''
                    Write-PSmmHost 'Select group(s) to remove:' -ForegroundColor Cyan
                    Write-Information ''
                    foreach ($groupId in ($storageMap.Keys | Sort-Object {[int]$_})) {
                        $group = $storageMap[$groupId]
                        $displayNameValue = Get-ConfigMemberValue -Object $group -Name 'DisplayName' -Default ''
                        $displayName = if (-not [string]::IsNullOrWhiteSpace([string]$displayNameValue)) { [string]$displayNameValue } else { "Storage Group $groupId" }
                        Write-PSmmHost "  [$groupId] $displayName" -ForegroundColor White

                        # Show Master drive
                        $masterCfg = Get-ConfigMemberValue -Object $group -Name 'Master' -Default $null
                        if ($masterCfg) {
                            $masterLabelValue = Get-ConfigMemberValue -Object $masterCfg -Name 'Label' -Default ''
                            $masterSerialValue = Get-ConfigMemberValue -Object $masterCfg -Name 'SerialNumber' -Default ''
                            $masterLabel = if (-not [string]::IsNullOrWhiteSpace([string]$masterLabelValue)) { [string]$masterLabelValue } else { 'N/A' }
                            $masterSerial = if (-not [string]::IsNullOrWhiteSpace([string]$masterSerialValue)) { [string]$masterSerialValue } else { 'N/A' }
                            Write-PSmmHost "      Master: $masterLabel (S/N: $masterSerial)" -ForegroundColor Gray
                        }

                        # Show Backup drives
                        $backupsCfg = Get-ConfigMemberValue -Object $group -Name 'Backups' -Default $null
                        if ($null -eq $backupsCfg) { $backupsCfg = Get-ConfigMemberValue -Object $group -Name 'Backup' -Default $null }
                        if ($backupsCfg -is [System.Collections.IDictionary] -and $backupsCfg.Keys.Count -gt 0) {
                            foreach ($backupId in ($backupsCfg.Keys | Sort-Object { [int]$_ })) {
                                $backup = $backupsCfg[$backupId]
                                $backupLabelValue = Get-ConfigMemberValue -Object $backup -Name 'Label' -Default ''
                                $backupSerialValue = Get-ConfigMemberValue -Object $backup -Name 'SerialNumber' -Default ''
                                $backupLabel = if (-not [string]::IsNullOrWhiteSpace([string]$backupLabelValue)) { [string]$backupLabelValue } else { 'N/A' }
                                $backupSerial = if (-not [string]::IsNullOrWhiteSpace([string]$backupSerialValue)) { [string]$backupSerialValue } else { 'N/A' }
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
                        if (Test-MapContainsKey -Map $storageMap -Key $n) {
                            $groupsToRemove += $n
                        }
                    }

                    if ($groupsToRemove.Count -eq 0) {
                        Write-PSmmHost 'No valid groups selected.' -ForegroundColor Yellow
                        Invoke-PauseIfInteractive
                        continue
                    }

                    # Confirm removal
                    Write-Information ''
                    Write-PSmmHost "You are about to remove $($groupsToRemove.Count) group(s):" -ForegroundColor Yellow
                    foreach ($gid in $groupsToRemove) {
                        $g = $storageMap[$gid]
                        $dname = if ($g.DisplayName) { $g.DisplayName } else { "Storage Group $gid" }
                        Write-Information "  - Group $gid : $dname"
                    }
                    Write-Information ''
                    $confirm = Read-ManageInput 'Confirm removal? (Y/N)'
                    if ($confirm -notmatch '^(?i)y$') {
                        Write-PSmmHost 'Removal cancelled.' -ForegroundColor Yellow
                        Invoke-PauseIfInteractive
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
                    Invoke-PauseIfInteractive
                }

                '^(?i)b$' {
                    # Back to main menu
                    Write-ManageLog -level 'DEBUG' -context 'ManageStorage' -msg 'User selected Back'
                    return $true
                }

                default {
                    Write-PSmmHost 'Invalid selection. Please choose E, A, R, or B.' -ForegroundColor Yellow
                    Invoke-PauseIfInteractive
                }
            }
            # In test mode with canned inputs, stop once we've consumed all inputs to avoid waiting for user input
            if ($testInputs -and $testInputIndex -ge $testInputs.Count) { break }
        }
        else {
            # NonInteractive mode - not supported for manage menu
            Write-ManageLog -level 'WARNING' -context 'ManageStorage' -msg 'NonInteractive mode not supported for Manage Storage menu'
            return $false
        }
    }

    # If we exit the loop (typically in tests after consuming canned inputs), return $true to signal completion
    return $true
}
