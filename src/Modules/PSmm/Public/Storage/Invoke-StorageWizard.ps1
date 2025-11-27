<#
.SYNOPSIS
    Interactive wizard to configure storage groups from USB/removable drives.

.DESCRIPTION
    Detects portable USB/removable drives, guides the user to create or edit a storage group
    with an auto-incremented ID (for Add mode), a customizable DisplayName, and a Master + optional
    Backup drives. Writes PSmm.Storage.psd1 to <DriveRoot>\PSmm.Config on confirmation
    and updates the provided AppConfiguration in-memory.

.PARAMETER Mode
    Operation mode: 'Add' (default) creates a new group, 'Edit' modifies an existing group.

.PARAMETER GroupId
    Required when Mode is 'Edit'. Specifies the group ID to edit.

.NOTES
    Supports duplicate serial validation with interactive confirmation or NonInteractive fail-fast.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Invoke-StorageWizard {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AppConfiguration]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DriveRoot,

        [Parameter()]
        [ValidateSet('Add', 'Edit')]
        [string]$Mode = 'Add',

        [Parameter()]
        [string]$GroupId = '',

        [switch]$NonInteractive
    )

    # Validate parameters
    if ($Mode -eq 'Edit') {
        if ([string]::IsNullOrWhiteSpace($GroupId)) {
            throw "GroupId is required when Mode is 'Edit'"
        }
        if (-not $Config.Storage.ContainsKey($GroupId)) {
            throw "Storage group '$GroupId' not found in configuration"
        }
    }

    $logAvail = Get-Command Write-PSmmLog -ErrorAction SilentlyContinue
    function Write-WizardLog([string]$level, [string]$id, [string]$msg) {
        if ($logAvail) { Write-PSmmLog -Level $level -Context 'StorageWizard' -Message ("$($ id): $($msg)") -Console -File }
        else { Write-Verbose "$($id): $($msg)" }
    }

    # Optional test input feed for non-interactive testing
    $testInputs = $null
    $testInputIndex = 0
    try {
        if (-not [string]::IsNullOrWhiteSpace($env:MEDIA_MANAGER_TEST_INPUTS)) {
            $parsed = $env:MEDIA_MANAGER_TEST_INPUTS | ConvertFrom-Json -ErrorAction Stop
            if ($parsed -is [System.Array]) { $testInputs = [string[]]$parsed }
        }
    } catch { $testInputs = $null }

    # In test mode, if running interactively without provided inputs, abort early to avoid hangs
    if ([string]::Equals($env:MEDIA_MANAGER_TEST_MODE, '1', [System.StringComparison]::OrdinalIgnoreCase) -and (-not $NonInteractive)) {
        if (-not $testInputs -or $testInputs.Count -eq 0) { return $false }
    }

    function Read-WizardInput([string]$Prompt) {
        if ($testInputs -and ($testInputIndex -lt $testInputs.Count)) {
            $val = [string]$testInputs[$testInputIndex]
            $testInputIndex++
            return $val
        }
        return Read-Host -Prompt $Prompt
    }

    # Gather drives and filter for USB/removable
    $allDrives = @()
    try { $allDrives = Get-StorageDrive } catch { $allDrives = @() }

    $candidateDrives = @($allDrives | Where-Object { $_.IsRemovable -or ($_.BusType -eq 'USB') -or ($_.InterfaceType -eq 'USB') })

    if (-not $candidateDrives -or $candidateDrives.Count -eq 0) {
        # Log excluded fixed/internal drives at VERBOSE level for diagnostics
        $excludedDrives = @($allDrives | Where-Object { -not ($_.IsRemovable -or ($_.BusType -eq 'USB') -or ($_.InterfaceType -eq 'USB')) })
        if ($excludedDrives.Count -gt 0) {
            Write-WizardLog -level 'VERBOSE' -id 'PSMM-STORAGE-EXCLUDED' -msg "Excluded $($excludedDrives.Count) fixed/internal drive(s) not matching USB/removable criteria:"
            foreach ($d in $excludedDrives) {
                $sizeGB = [int]([math]::Round([double]$d.TotalSpace, 0))
                $label = if ([string]::IsNullOrWhiteSpace($d.Label)) { '(NoLabel)' } else { $d.Label }
                $letter = if ([string]::IsNullOrWhiteSpace($d.DriveLetter)) { 'N/A' } else { $d.DriveLetter }
                $model = if ([string]::IsNullOrWhiteSpace($d.Model)) { 'Unknown' } else { $d.Model }
                Write-WizardLog -level 'VERBOSE' -id 'PSMM-STORAGE-EXCLUDED-DETAIL' -msg "  $letter $label ($sizeGB GB) - Model: $model, BusType: $($d.BusType), DriveType: $($d.DriveType), Serial: $($d.SerialNumber)"
            }
        }

        $m = Resolve-StorageWizardMessage -Key 'PSMM-STORAGE-NO-USB'
        Write-WizardLog -level 'WARNING' -id $m.Id -msg $m.Text
        if (-not $NonInteractive) {
            Write-PSmmHost $m.Text -ForegroundColor Yellow
        }
        return $false
    }

    # Determine group ID and load existing values if editing
    if ($Mode -eq 'Edit') {
        $groupId = $GroupId
        $existingGroup = $Config.Storage[$groupId]
        $defaultDisplayName = $existingGroup.DisplayName
        # Try to match existing drives to current candidates
        $existingMasterSerial = if ($existingGroup.Master) { $existingGroup.Master.SerialNumber } else { '' }
        $existingBackupSerials = @()
        if ($existingGroup.Backups) {
            foreach ($bk in $existingGroup.Backups.Keys) {
                $existingBackupSerials += $existingGroup.Backups[$bk].SerialNumber
            }
        }
    }
    else {
        # Add mode: compute next group id
        $existingNumericKeys = @()
        foreach ($k in $Config.Storage.Keys) { if ($k -match '^[0-9]+$') { $existingNumericKeys += [int]$k } }
        $nextId = if ($existingNumericKeys.Count -gt 0) { ([int]($existingNumericKeys | Measure-Object -Maximum).Maximum) + 1 } else { 1 }
        $groupId = [string]$nextId
        $defaultDisplayName = "Storage Group $groupId"
        $existingMasterSerial = ''
        $existingBackupSerials = @()
    }

    # Wizard step state
    $step = 1
    $displayName = $null
    $master = $null
    $backups = @()

    function Format-DriveRow($d) {
        $sizeGB = [int]([math]::Round([double]$d.TotalSpace, 0))
        $label = if ([string]::IsNullOrWhiteSpace($d.Label)) { '(NoLabel)' } else { $d.Label }
        $letter = if ([string]::IsNullOrWhiteSpace($d.DriveLetter)) { 'N/A' } else { $d.DriveLetter }
        return [PSCustomObject]@{ Label=$label; Letter=$letter; SizeGB=$sizeGB; Serial=$d.SerialNumber }
    }

    $indexed = @()
    $i = 1
    foreach ($d in $candidateDrives) {
        $indexed += [PSCustomObject]@{ Index=$i; Raw=$d; View=(Format-DriveRow $d) }
        $i++
    }

    :WizardLoop while ($step -le 3) {
        switch ($step) {
            1 {
                # DisplayName step
                $displayName = $defaultDisplayName
                if (-not $NonInteractive) {
                    $promptText = if ($Mode -eq 'Edit') {
                        "Enter a display name for group $groupId [current: $defaultDisplayName] (B=Back, C=Cancel)"
                    } else {
                        "Enter a display name for group $groupId [`$default: $defaultDisplayName`] (B=Back, C=Cancel)"
                    }
                    $inputName = Read-WizardInput $promptText
                    if ($inputName -match '^(?i)c$') { return $false }
                    if ($inputName -match '^(?i)b$') { $step--; continue }
                    if (-not [string]::IsNullOrWhiteSpace($inputName)) { $displayName = $inputName }
                }
                $step++
            }
            2 {
                # Master selection step
                if (-not $NonInteractive) {
                    $promptPrefix = if ($Mode -eq 'Edit' -and -not [string]::IsNullOrWhiteSpace($existingMasterSerial)) {
                        "Select Master drive [current serial: $existingMasterSerial]:"
                    } else {
                        "Select Master drive:"
                    }
                    Write-PSmmHost $promptPrefix -ForegroundColor Cyan
                    foreach ($row in $indexed) {
                        $view = $row.View
                        $marker = if ($row.Raw.SerialNumber -eq $existingMasterSerial) { ' <-- current' } else { '' }
                        Write-Information ("  [{0}] {1,-16} {2,-4} {3,6}GB {4}{5}" -f $row.Index, ($view.Label.Substring(0, [Math]::Min(16, $view.Label.Length))), $view.Letter, $view.SizeGB, $view.Serial, $marker)
                    }
                    Write-Information ''
                    $sel = Read-WizardInput 'Enter number, B=Back, C=Cancel'
                    if ($sel -match '^(?i)c$') { return $false }
                    if ($sel -match '^(?i)b$') { $step--; continue }
                    if ($sel -notmatch '^[0-9]+$') { continue }
                    $chosen = $indexed | Where-Object { $_.Index -eq [int]$sel } | Select-Object -First 1
                    if (-not $chosen) { continue }
                    $master = $chosen.Raw
                }
                else {
                    $master = $indexed | Select-Object -First 1 | ForEach-Object { $_.Raw }
                }
                $step++
            }
            3 {
                # Backup selection step
                $backups = @()
                if (-not $NonInteractive) {
                    $promptPrefix = if ($Mode -eq 'Edit' -and $existingBackupSerials.Count -gt 0) {
                        "Select Backup drive(s) [current serials: $($existingBackupSerials -join ', ')] (comma-separated), or Enter for none:"
                    } else {
                        "Select Backup drive(s) (comma-separated), or Enter for none:"
                    }
                    Write-PSmmHost $promptPrefix -ForegroundColor Cyan
                    foreach ($row in $indexed) {
                        if ($row.Raw.DriveLetter -eq $master.DriveLetter -and $row.Raw.SerialNumber -eq $master.SerialNumber) { continue }
                        $view = $row.View
                        $marker = if ($existingBackupSerials -contains $row.Raw.SerialNumber) { ' <-- current' } else { '' }
                        Write-Information ("  [{0}] {1,-16} {2,-4} {3,6}GB {4}{5}" -f $row.Index, ($view.Label.Substring(0, [Math]::Min(16, $view.Label.Length))), $view.Letter, $view.SizeGB, $view.Serial, $marker)
                    }
                    Write-Information ''
                    $multi = Read-WizardInput 'Enter numbers (e.g., 2,3), B=Back, C=Cancel, or press Enter'
                    if ($multi -match '^(?i)c$') { return $false }
                    if ($multi -match '^(?i)b$') { $step--; continue }
                    if (-not [string]::IsNullOrWhiteSpace($multi)) {
                        $nums = $multi -split '[, ]+' | Where-Object { $_ -match '^[0-9]+$' } | ForEach-Object { [int]$_ }
                        foreach ($n in $nums | Select-Object -Unique) {
                            $cand = $indexed | Where-Object { $_.Index -eq $n } | Select-Object -First 1
                            if ($cand) {
                                # Prevent collision with Master
                                if ($cand.Raw.SerialNumber -eq $master.SerialNumber) {
                                    $m = Resolve-StorageWizardMessage -Key 'PSMM-STORAGE-MASTER-BACKUP-COLLISION'
                                    Write-WizardLog -level 'WARNING' -id $m.Id -msg $m.Text
                                    continue
                                }
                                # Prevent duplicate serial within backups
                                if ($backups | Where-Object { $_.SerialNumber -eq $cand.Raw.SerialNumber }) {
                                    $m = Resolve-StorageWizardMessage -Key 'PSMM-STORAGE-DUPLICATE-SERIAL'
                                    Write-WizardLog -level 'WARNING' -id $m.Id -msg $m.Text
                                    continue
                                }
                                $backups += $cand.Raw
                            }
                        }
                    }
                }
                $step++
            }
        }
    }

    # Duplicate serial validation (check against other groups)
    $serialsToCheck = @($master.SerialNumber)
    foreach ($b in $backups) {
        $serialsToCheck += $b.SerialNumber
    }

    $testInputsRef = [ref]$testInputs
    $testInputIndexRef = [ref]$testInputIndex
    $excludeGroupId = if ($Mode -eq 'Edit') { $groupId } else { '' }

    try {
        $dupCheckResult = Test-DuplicateSerial -Config $Config -Serials $serialsToCheck -ExcludeGroupId $excludeGroupId -NonInteractive:$NonInteractive -TestInputs $testInputsRef -TestInputIndex $testInputIndexRef
        if (-not $dupCheckResult) {
            Write-WizardLog -level 'NOTICE' -id 'PSMM-STORAGE-DUPLICATE-CANCELLED' -msg 'User cancelled due to duplicate serial detection'
            return $false
        }
    }
    catch {
        Write-WizardLog -level 'ERROR' -id 'PSMM-STORAGE-DUPLICATE-ERROR' -msg "Duplicate validation failed: $_"
        throw
    }

    # Summary
    $summaryMsg = Resolve-StorageWizardMessage -Key 'PSMM-STORAGE-SUMMARY'
    if (-not $NonInteractive) {
        Write-Information ''
        Write-PSmmHost $summaryMsg.Text -ForegroundColor Cyan
        Write-Information ''
        $mView = (Format-DriveRow $master)
        Write-Information ("Master  : {0,-16} {1,-4} {2,6}GB {3}" -f ($mView.Label.Substring(0, [Math]::Min(16, $mView.Label.Length))), $mView.Letter, $mView.SizeGB, $mView.Serial)
        $idx = 1
        foreach ($b in $backups) {
            $bView = (Format-DriveRow $b)
            Write-Information ("Backup {0}: {1,-16} {2,-4} {3,6}GB {4}" -f $idx, ($bView.Label.Substring(0, [Math]::Min(16, $bView.Label.Length))), $bView.Letter, $bView.SizeGB, $bView.Serial)
            $idx++
        }
        Write-Information ''
        $confirmText = if ($Mode -eq 'Edit') { 'Update storage configuration?' } else { 'Write storage configuration?' }
        $confirm = Read-WizardInput "$confirmText (Y/N)"
        if ($confirm -notmatch '^(?i)y$') { return $false }
    }

    # Persist to file (merge-safe for Add/Edit modes)
    $storagePath = Join-Path -Path $DriveRoot -ChildPath 'PSmm.Config\PSmm.Storage.psd1'

    # Load existing storage hashtable
    $storageHashtable = [AppConfigurationBuilder]::ReadStorageFile($storagePath)
    if ($null -eq $storageHashtable) {
        $storageHashtable = @{}
    }

    # Build new group data
    $backupTable = @{}
    $bIdx = 1
    foreach ($b in $backups) {
        $backupTable[[string]$bIdx] = @{ Label = $b.Label; SerialNumber = $b.SerialNumber }
        $bIdx++
    }

    $groupData = @{
        DisplayName = $displayName
        Master      = @{ Label = $master.Label; SerialNumber = $master.SerialNumber }
        Backup      = $backupTable
    }

    # Update/add the group in the hashtable
    $storageHashtable[$groupId] = $groupData

    # Write to file (with renumbering for Add mode, preserving numbering for Edit mode)
    try {
        [AppConfigurationBuilder]::WriteStorageFile($storagePath, $storageHashtable)
        $actionVerb = if ($Mode -eq 'Edit') { 'updated' } else { 'written' }
        Write-WizardLog -level 'NOTICE' -id 'PSMM-STORAGE-WRITTEN' -msg "Storage configuration $actionVerb to $storagePath"
    }
    catch {
        Write-WizardLog -level 'ERROR' -id 'PSMM-STORAGE-WRITE-FAILED' -msg "Failed to write storage file: $_"
        throw
    }

    # Reload storage from file to get renumbered groups
    $Config.Storage.Clear()
    $reloaded = [AppConfigurationBuilder]::ReadStorageFile($storagePath)

    if ($null -ne $reloaded) {
        foreach ($gKey in $reloaded.Keys) {
            $gTable = $reloaded[$gKey]
            $group = [StorageGroupConfig]::new([string]$gKey)
            if ($gTable.ContainsKey('DisplayName')) { $group.DisplayName = $gTable.DisplayName }

            if ($gTable.ContainsKey('Master') -and $gTable.Master) {
                $mLabel = if ($gTable.Master.ContainsKey('Label')) { $gTable.Master.Label } else { '' }
                $mSerial = if ($gTable.Master.ContainsKey('SerialNumber')) { $gTable.Master.SerialNumber } else { '' }
                $group.Master = [StorageDriveConfig]::new($mLabel, '')
                $group.Master.SerialNumber = $mSerial
            }

            if ($gTable.ContainsKey('Backup') -and $gTable.Backup -is [hashtable]) {
                foreach ($bk in ($gTable.Backup.Keys | Where-Object { $_ -match '^[0-9]+' } | Sort-Object {[int]$_})) {
                    $b = $gTable.Backup[$bk]
                    if ($null -eq $b) { continue }
                    $bLabel = if ($b.ContainsKey('Label')) { $b.Label } else { '' }
                    $bSerial = if ($b.ContainsKey('SerialNumber')) { $b.SerialNumber } else { '' }
                    $cfg = [StorageDriveConfig]::new($bLabel, '')
                    $cfg.SerialNumber = $bSerial
                    $group.Backups[[string]$bk] = $cfg
                }
            }

            $Config.Storage[[string]$gKey] = $group
        }
    }

    # Update storage status (match drives and refresh availability)
    $availableDrives = @()
    try {
        if (Get-Command Get-StorageDrive -ErrorAction SilentlyContinue) {
            $availableDrives = Get-StorageDrive
        }
    }
    catch {
        Write-WizardLog -level 'WARNING' -id 'PSMM-STORAGE-DRIVE-REFRESH-FAILED' -msg "Failed to refresh storage drives: $_"
    }

    foreach ($gKey in $Config.Storage.Keys) {
        $group = $Config.Storage[$gKey]

        if ($null -ne $group.Master -and -not [string]::IsNullOrWhiteSpace($group.Master.SerialNumber)) {
            $matchedDrive = $availableDrives | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.SerialNumber) -and
                $_.SerialNumber.Trim() -eq $group.Master.SerialNumber.Trim()
            } | Select-Object -First 1

            if ($matchedDrive) {
                $group.Master.DriveLetter = $matchedDrive.DriveLetter
            }
        }

        if ($null -ne $group.Backups -and $group.Backups.Count -gt 0) {
            foreach ($backupKey in $group.Backups.Keys) {
                $backup = $group.Backups[$backupKey]
                if (-not [string]::IsNullOrWhiteSpace($backup.SerialNumber)) {
                    $matchedDrive = $availableDrives | Where-Object {
                        -not [string]::IsNullOrWhiteSpace($_.SerialNumber) -and
                        $_.SerialNumber.Trim() -eq $backup.SerialNumber.Trim()
                    } | Select-Object -First 1

                    if ($matchedDrive) {
                        $backup.DriveLetter = $matchedDrive.DriveLetter
                    }
                }
            }
        }

        $group.UpdateStatus()
    }

    return $true
}
