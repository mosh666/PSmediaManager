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
        [object]$Config,

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

    if (-not (Get-Command Get-PSmmConfigNestedValue -ErrorAction SilentlyContinue)) {
        $nestedAccessPath = Join-Path $PSScriptRoot '..\..\Private\Get-PSmmConfigNestedValue.ps1'
        if (Test-Path $nestedAccessPath) { . $nestedAccessPath }
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
            try {
                if ($Map.ContainsKey($Key)) { return $true }
            }
            catch {
                Write-Verbose "Test-MapContainsKey: ContainsKey() failed: $($_.Exception.Message)"
                # fall through
            }

            try {
                if ([bool]$Map.Contains($Key)) { return $true }
            }
            catch {
                Write-Verbose "Test-MapContainsKey: Contains() failed: $($_.Exception.Message)"
                # fall through
            }

            try {
                foreach ($k in $Map.Keys) {
                    if ($k -eq $Key) { return $true }
                }
            }
            catch { return $false }

            return $false
        }

        try { return [bool]$Map.ContainsKey($Key) } catch { return $false }
    }

    $storageMap = Get-PSmmConfigMemberValue -Object $Config -Name 'Storage' -Default $null
    if ($null -eq $storageMap -and $Config -is [System.Collections.IDictionary]) {
        # Allow passing a Storage-map directly in legacy/test scenarios
        $storageMap = $Config
    }
    if ($null -eq $storageMap) {
        $storageMap = @{}
        Set-PSmmConfigMemberValue -Object $Config -Name 'Storage' -Value $storageMap
    }

    # Validate parameters
    if ($Mode -eq 'Edit') {
        if ([string]::IsNullOrWhiteSpace($GroupId)) {
            throw [ValidationException]::new("GroupId is required when Mode is 'Edit'", "GroupId")
        }
        if (-not (Test-MapContainsKey -Map $storageMap -Key $GroupId)) {
            throw [StorageException]::new("Storage group '$GroupId' not found in configuration", $GroupId)
        }
    }

    $logAvail = Get-Command Write-PSmmLog -ErrorAction SilentlyContinue
    function Write-WizardLog([string]$level, [string]$id, [string]$msg) {
        if ($logAvail) { Write-PSmmLog -Level $level -Context 'StorageWizard' -Message ("$($id): $($msg)") -File }
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
    if (-not $NonInteractive) {
        Write-PSmmHost "Scanning for available storage drives..." -ForegroundColor Cyan
    }

    $allDrives = @()
    try { $allDrives = Get-StorageDrive } catch { $allDrives = @() }

    if (-not $NonInteractive) {
        Write-PSmmHost "  Found $($allDrives.Count) total drive(s)" -ForegroundColor Gray
    }

    $candidateDrives = @($allDrives | Where-Object { $_.IsRemovable -or ($_.BusType -eq 'USB') -or ($_.InterfaceType -eq 'USB') })

    # Filter out drives already assigned to other storage groups
    $usedSerials = @()
    foreach ($gKey in $storageMap.Keys) {
        # Skip the group being edited (if in Edit mode)
        if ($Mode -eq 'Edit' -and $gKey -eq $GroupId) { continue }

        $group = $storageMap[$gKey]

        $masterSerial = Get-PSmmConfigNestedValue -Object $group -Path @('Master', 'SerialNumber') -Default ''
        if (-not [string]::IsNullOrWhiteSpace($masterSerial)) {
            $usedSerials += ([string]$masterSerial).Trim()
        }

        $backupsCfg = Get-PSmmConfigMemberValue -Object $group -Name 'Backups' -Default $null
        if ($null -eq $backupsCfg) {
            $backupsCfg = Get-PSmmConfigMemberValue -Object $group -Name 'Backup' -Default $null
        }
        if ($backupsCfg -is [System.Collections.IDictionary] -and $backupsCfg.Count -gt 0) {
            foreach ($bKey in $backupsCfg.Keys) {
                $backup = $backupsCfg[$bKey]
                $backupSerial = Get-PSmmConfigMemberValue -Object $backup -Name 'SerialNumber' -Default ''
                if (-not [string]::IsNullOrWhiteSpace($backupSerial)) {
                    $usedSerials += ([string]$backupSerial).Trim()
                }
            }
        }
    }

    # Filter candidate drives to exclude already-used ones
    if ($usedSerials.Count -gt 0) {
        $candidateDrives = @($candidateDrives | Where-Object {
            $serial = if ([string]::IsNullOrWhiteSpace($_.SerialNumber)) { '' } else { $_.SerialNumber.Trim() }
            -not ($usedSerials -contains $serial)
        })
    }

    if (-not $NonInteractive) {
        Write-PSmmHost "  Detected $($candidateDrives.Count) removable/USB drive(s)" -ForegroundColor $(if($candidateDrives.Count -gt 0){'Green'}else{'Yellow'})
        Write-PSmmHost ""
    }

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
        $existingGroup = $storageMap[$groupId]
        $defaultDisplayNameValue = Get-PSmmConfigMemberValue -Object $existingGroup -Name 'DisplayName' -Default ''
        $defaultDisplayName = if (-not [string]::IsNullOrWhiteSpace([string]$defaultDisplayNameValue)) { [string]$defaultDisplayNameValue } else { "Storage Group $groupId" }
        # Try to match existing drives to current candidates
        $existingMasterSerial = [string](Get-PSmmConfigNestedValue -Object $existingGroup -Path @('Master', 'SerialNumber') -Default '')
        $existingBackupSerials = @()
        $existingBackupsCfg = Get-PSmmConfigMemberValue -Object $existingGroup -Name 'Backups' -Default $null
        if ($null -eq $existingBackupsCfg) {
            $existingBackupsCfg = Get-PSmmConfigMemberValue -Object $existingGroup -Name 'Backup' -Default $null
        }
        if ($existingBackupsCfg -is [System.Collections.IDictionary]) {
            foreach ($bk in $existingBackupsCfg.Keys) {
                $b = $existingBackupsCfg[$bk]
                $bSerial = [string](Get-PSmmConfigMemberValue -Object $b -Name 'SerialNumber' -Default '')
                if (-not [string]::IsNullOrWhiteSpace($bSerial)) {
                    $existingBackupSerials += $bSerial
                }
            }
        }
    }
    else {
        # Add mode: compute next group id
        $existingNumericKeys = @()
        foreach ($k in $storageMap.Keys) { if ($k -match '^[0-9]+$') { $existingNumericKeys += [int]$k } }
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

    # Display wizard header
    if (-not $NonInteractive) {
        Write-PSmmHost "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        if ($Mode -eq 'Edit') {
            Write-PSmmHost "║           Storage Configuration Wizard - Edit Mode               ║" -ForegroundColor Cyan
            Write-PSmmHost "║                   Editing Group: $($groupId.PadRight(35))║" -ForegroundColor Cyan
        } else {
            Write-PSmmHost "║           Storage Configuration Wizard - Add Mode                 ║" -ForegroundColor Cyan
            Write-PSmmHost "║                Creating Group: $($groupId.PadRight(35))║" -ForegroundColor Cyan
        }
        Write-PSmmHost "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-PSmmHost ""
        Write-PSmmHost "This wizard will guide you through 3 steps:" -ForegroundColor Gray
        Write-PSmmHost "  1. Set a display name for this storage group" -ForegroundColor Gray
        Write-PSmmHost "  2. Select the Master (primary) drive" -ForegroundColor Gray
        Write-PSmmHost "  3. Optionally select Backup drive(s)" -ForegroundColor Gray
        Write-PSmmHost ""
    }

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
                if (-not $NonInteractive) {
                    Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                    Write-PSmmHost "Step 1 of 3: Display Name" -ForegroundColor Cyan
                    Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                    Write-PSmmHost ""
                    Write-PSmmHost "Choose a descriptive name for this storage group." -ForegroundColor Gray
                    Write-PSmmHost "This name will help you identify this group in the system." -ForegroundColor Gray
                    Write-PSmmHost ""
                }

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
                    Write-PSmmHost ""
                    Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                    Write-PSmmHost "Step 2 of 3: Master Drive Selection" -ForegroundColor Cyan
                    Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                    Write-PSmmHost ""
                    Write-PSmmHost "The Master drive is your primary storage location." -ForegroundColor Gray
                    Write-PSmmHost "Select the main drive where media files will be stored." -ForegroundColor Gray
                    Write-PSmmHost ""

                    $promptPrefix = if ($Mode -eq 'Edit' -and -not [string]::IsNullOrWhiteSpace($existingMasterSerial)) {
                        "Available drives [current serial: $existingMasterSerial]:"
                    } else {
                        "Available drives:"
                    }
                    Write-PSmmHost $promptPrefix -ForegroundColor Cyan
                    foreach ($row in $indexed) {
                        $view = $row.View
                        $marker = if ($row.Raw.SerialNumber -eq $existingMasterSerial) { ' <-- current' } else { '' }
                        Write-Information ("  [{0}] {1,-16} {2,-4} {3,6}GB {4}{5}" -f $row.Index, ($view.Label.Substring(0, [Math]::Min(16, $view.Label.Length))), $view.Letter, $view.SizeGB, $view.Serial, $marker) -InformationAction Continue
                    }
                    Write-Information '' -InformationAction Continue
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
                    Write-PSmmHost ""
                    Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                    Write-PSmmHost "Step 3 of 3: Backup Drive Selection (Optional)" -ForegroundColor Cyan
                    Write-PSmmHost "─────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                    Write-PSmmHost ""
                    Write-PSmmHost "Backup drives provide redundancy for your media files." -ForegroundColor Gray
                    Write-PSmmHost "You can select multiple drives or press Enter to skip." -ForegroundColor Gray
                    Write-PSmmHost ""

                    $promptPrefix = if ($Mode -eq 'Edit' -and $existingBackupSerials.Count -gt 0) {
                        "Available drives [current serials: $($existingBackupSerials -join ', ')]:"
                    } else {
                        "Available drives (excluding Master):"
                    }
                    Write-PSmmHost $promptPrefix -ForegroundColor Cyan
                    foreach ($row in $indexed) {
                        if ($row.Raw.DriveLetter -eq $master.DriveLetter -and $row.Raw.SerialNumber -eq $master.SerialNumber) { continue }
                        $view = $row.View
                        $marker = if ($existingBackupSerials -contains $row.Raw.SerialNumber) { ' <-- current' } else { '' }
                        Write-Information ("  [{0}] {1,-16} {2,-4} {3,6}GB {4}{5}" -f $row.Index, ($view.Label.Substring(0, [Math]::Min(16, $view.Label.Length))), $view.Letter, $view.SizeGB, $view.Serial, $marker) -InformationAction Continue
                    }
                    Write-Information '' -InformationAction Continue
                    $multi = Read-WizardInput 'Enter numbers (e.g., 2,3 for multiple), B=Back, C=Cancel, or Enter for none'
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
    # Summary message not used directly; removing unused assignment for analyzer compliance
    if (-not $NonInteractive) {
        Write-PSmmHost ""
        Write-PSmmHost "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-PSmmHost "Configuration Summary" -ForegroundColor Green
        Write-PSmmHost "═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
        Write-PSmmHost ""
        Write-PSmmHost "Group ID    : $groupId" -ForegroundColor Cyan
        Write-PSmmHost "Display Name: $displayName" -ForegroundColor Cyan
        Write-PSmmHost ""
        $mView = (Format-DriveRow $master)
        Write-Information ("Master  : {0,-16} {1,-4} {2,6}GB {3}" -f ($mView.Label.Substring(0, [Math]::Min(16, $mView.Label.Length))), $mView.Letter, $mView.SizeGB, $mView.Serial) -InformationAction Continue
        $idx = 1
        foreach ($b in $backups) {
            $bView = (Format-DriveRow $b)
            Write-Information ("Backup {0}: {1,-16} {2,-4} {3,6}GB {4}" -f $idx, ($bView.Label.Substring(0, [Math]::Min(16, $bView.Label.Length))), $bView.Letter, $bView.SizeGB, $bView.Serial) -InformationAction Continue
            $idx++
        }
        Write-Information '' -InformationAction Continue
        $confirmText = if ($Mode -eq 'Edit') { 'Update storage configuration?' } else { 'Write storage configuration?' }
        $confirm = Read-WizardInput "$confirmText (y/N)"
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
        $fs = Get-PSmmConfigMemberValue -Object $Config -Name 'FileSystem' -Default $null
        if ($null -eq $fs) {
            throw [ValidationException]::new('FileSystem service is required to write storage configuration', 'FileSystem', $null)
        }

        [AppConfigurationBuilder]::WriteStorageFile($storagePath, $storageHashtable, $fs)
        $actionVerb = if ($Mode -eq 'Edit') { 'updated' } else { 'written' }
        Write-WizardLog -level 'NOTICE' -id 'PSMM-STORAGE-WRITTEN' -msg "Storage configuration $actionVerb to $storagePath"

        if (-not $NonInteractive) {
            Write-PSmmHost ""
            Write-PSmmHost "✓ Storage configuration $actionVerb successfully" -ForegroundColor Green
            Write-PSmmHost "  Location: $storagePath" -ForegroundColor Gray
        }
    }
    catch {
        Write-WizardLog -level 'ERROR' -id 'PSMM-STORAGE-WRITE-FAILED' -msg "Failed to write storage file: $_"
        throw
    }

    # Reload storage from file to get renumbered groups
    $storageMap.Clear()
    $reloaded = [AppConfigurationBuilder]::ReadStorageFile($storagePath)

    if ($null -ne $reloaded) {
        foreach ($gKey in $reloaded.Keys) {
            $gTable = $reloaded[$gKey]
            $group = [StorageGroupConfig]::new([string]$gKey)
            $displayNameValue = Get-PSmmConfigMemberValue -Object $gTable -Name 'DisplayName' -Default $null
            if (-not [string]::IsNullOrWhiteSpace([string]$displayNameValue)) { $group.DisplayName = [string]$displayNameValue }

            $mTable = Get-PSmmConfigMemberValue -Object $gTable -Name 'Master' -Default $null
            if ($null -ne $mTable) {
                $mLabel = [string](Get-PSmmConfigNestedValue -Object $gTable -Path @('Master', 'Label') -Default '')
                $mSerial = [string](Get-PSmmConfigNestedValue -Object $gTable -Path @('Master', 'SerialNumber') -Default '')
                $group.Master = [StorageDriveConfig]::new($mLabel, '')
                $group.Master.SerialNumber = $mSerial
            }

            $bTable = Get-PSmmConfigMemberValue -Object $gTable -Name 'Backup' -Default $null
            if ($bTable -is [System.Collections.IDictionary] -and $bTable.Count -gt 0) {
                foreach ($bk in ($bTable.Keys | Where-Object { $_ -match '^[0-9]+' } | Sort-Object { [int]$_ })) {
                    $b = $bTable[$bk]
                    if ($null -eq $b) { continue }
                    $bLabel = [string](Get-PSmmConfigMemberValue -Object $b -Name 'Label' -Default '')
                    $bSerial = [string](Get-PSmmConfigMemberValue -Object $b -Name 'SerialNumber' -Default '')
                    $cfg = [StorageDriveConfig]::new($bLabel, '')
                    $cfg.SerialNumber = $bSerial
                    $group.Backups[[string]$bk] = $cfg
                }
            }

            $storageMap[[string]$gKey] = $group
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

    foreach ($gKey in $storageMap.Keys) {
        $group = $storageMap[$gKey]

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
