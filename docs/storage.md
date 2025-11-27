# Storage Drive Management

This document provides comprehensive documentation for the storage drive management subsystem in PSmediaManager.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Storage Configuration](#storage-configuration)
- [Public Functions](#public-functions)
- [Classes](#classes)
- [StorageService](#storageservice)
- [Usage Examples](#usage-examples)
- [Bootstrap Integration](#bootstrap-integration)
- [Testing](#testing)
- [Best Practices](#best-practices)

## Overview

The storage drive management subsystem is responsible for:

- **Discovery**: Detecting physical drives via Windows CIM APIs
- **Validation**: Verifying drive availability by serial number
- **Configuration**: Managing Master/Backup drive groups
- **Persistence**: Storing configuration on-drive in `PSmm.Storage.psd1`
- **Runtime Updates**: Tracking drive letters, paths, and space metrics

Storage is a **core infrastructure component** called during application bootstrap, before UI and Projects modules load.

### Key Concepts

- **Storage Group**: A logical grouping of one Master drive and zero or more Backup drives
- **Serial Number Matching**: Drives are identified by unique serial numbers, not drive letters
- **Runtime-Derived Properties**: `DriveLetter`, `Path`, `FreeSpaceGB`, `TotalSpaceGB` are detected at runtime
- **On-Drive Configuration**: Configuration files live on the storage drives themselves (`<DriveRoot>\PSmm.Config\PSmm.Storage.psd1`)

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Bootstrap                    │
│                        (Invoke-PSmm)                         │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Storage Orchestration                      │
│                    (Confirm-Storage)                         │
└──────────┬──────────────────────────────┬───────────────────┘
           │                              │
           ▼                              ▼
┌──────────────────────┐      ┌──────────────────────────────┐
│   StorageService     │      │  AppConfigurationBuilder     │
│  (Drive Discovery)   │      │  (File I/O Operations)       │
└──────────────────────┘      └──────────────────────────────┘
           │                              │
           ▼                              ▼
┌──────────────────────┐      ┌──────────────────────────────┐
│ Windows CIM APIs     │      │  PSmm.Storage.psd1           │
│ - Win32_DiskDrive    │      │  (On-drive config file)      │
│ - Win32_LogicalDisk  │      └──────────────────────────────┘
│ - Get-Disk/Volume    │
└──────────────────────┘

           Consumed By:
┌──────────────────────────────────────────────────────────────┐
│  PSmm.UI Module    │  PSmm.Projects Module  │  User Scripts  │
│  - Storage menus   │  - Project discovery   │  - Custom CLI  │
│  - Drive selection │  - Drive validation    │                │
└──────────────────────────────────────────────────────────────┘
```

### Layered View

```
┌─────────────────────────────────────────────────────────────┐
│                      Public Functions                        │
│  Confirm-Storage, Get-StorageDrive, Invoke-StorageWizard    │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────────┐
│                     Service Layer (New)                      │
│                    StorageService Class                      │
│  - GetStorageDrives(), FindDriveBySerial(), etc.            │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────────┐
│                   Configuration Classes                      │
│        StorageDriveConfig, StorageGroupConfig               │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────────┐
│                     Platform APIs                            │
│         Windows CIM, Get-Disk, Get-Volume, Get-PSDrive      │
└─────────────────────────────────────────────────────────────┘
```

### File Locations

```
src/Modules/PSmm/
├── Classes/
│   ├── Interfaces.ps1                    # IStorageService interface
│   ├── AppConfiguration.ps1              # StorageDriveConfig, StorageGroupConfig classes
│   └── Services/
│       └── StorageService.ps1            # NEW: StorageService implementation
├── Public/Storage/
│   ├── Confirm-Storage.ps1               # Bootstrap validator (287 lines)
│   ├── Get-StorageDrive.ps1              # Public wrapper (68 lines, refactored)
│   ├── Invoke-StorageWizard.ps1          # Add/Edit wizard (411 lines)
│   ├── Invoke-ManageStorage.ps1          # Management menu (240 lines)
│   ├── Remove-StorageGroup.ps1           # Group removal (183 lines)
│   ├── Show-StorageInfo.ps1              # Display utility (161 lines)
│   └── Test-DuplicateSerial.ps1          # Serial validation (159 lines)
└── Private/
    └── Get-ResourceString.ps1            # Localization helper (58 lines)

tests/Modules/PSmm/
├── Confirm-Storage.Tests.ps1
├── Get-StorageDrive.Tests.ps1
├── Invoke-StorageWizard.Tests.ps1
└── ... (25+ storage-related test files)
```

**Total Code**: ~1,772 lines (including classes, functions, tests)

## Storage Configuration

### Data Model

#### StorageDriveConfig Class

Represents a single physical drive (Master or Backup).

```powershell
class StorageDriveConfig {
    [string]$Label              # User-friendly label (e.g., "Media-1")
    [string]$SerialNumber       # Hardware serial number (immutable)
    [string]$DriveLetter        # Runtime-derived (e.g., "Z:")
    [string]$Path               # Runtime-derived root path
    [bool]$IsAvailable          # Runtime-derived availability
    [long]$FreeSpaceGB          # Runtime-derived free space
    [long]$TotalSpaceGB         # Runtime-derived total space
}
```

**Key Properties:**

- **Immutable**: `Label`, `SerialNumber` (set during configuration)
- **Runtime-Derived**: `DriveLetter`, `Path`, `IsAvailable`, `FreeSpaceGB`, `TotalSpaceGB` (updated by `UpdateStatus()`)

#### StorageGroupConfig Class

Represents a logical group of Master + Backup drives.

```powershell
class StorageGroupConfig {
    [string]$GroupId                                     # Numeric ID (e.g., "1", "2")
    [string]$DisplayName                                 # User-friendly name
    [StorageDriveConfig]$Master                          # Master drive
    [Dictionary[string, StorageDriveConfig]]$Backups     # Backup drives keyed by ID
    [Dictionary[string, string]]$Paths                   # Custom paths (future use)
}
```

**Methods:**

- `IsValid()` - Returns true if Master drive is available
- `UpdateStatus()` - Refreshes Master and all Backup drives' runtime properties

### Configuration File Format

Storage configuration is persisted to `<DriveRoot>\PSmm.Config\PSmm.Storage.psd1`:

```powershell
@{
    Storage = @{
        '1' = @{
            DisplayName = 'My Media Collection'
            Master      = @{
                Label        = 'Media-1'
                SerialNumber = 'R381505X0SNNM7S'
            }
            Backup      = @{
                '1' = @{
                    Label        = 'Media-1-Backup-1'
                    SerialNumber = '2204EQ403864'
                }
                '2' = @{
                    Label        = 'Media-1-Backup-2'
                    SerialNumber = '2204GS402792'
                }
            }
        }
        '2' = @{
            DisplayName = 'Archive Storage'
            Master      = @{
                Label        = 'Archive-Master'
                SerialNumber = 'ABC123XYZ789'
            }
            Backup      = @{}  # No backup drives configured
        }
    }
}
```

**File Location**: The configuration file is stored on the same drive that runs PSmediaManager (typically the Master drive of Storage.1).

### AppConfiguration Integration

Storage is embedded in the main `AppConfiguration` class:

```powershell
class AppConfiguration {
    [Dictionary[string, StorageGroupConfig]]$Storage
    [hashtable]$InternalErrorMessages   # Contains Storage = @{} section
    # ... other properties
}
```

Access pattern:

```powershell
# Access storage group 1
$masterDrive = $Config.Storage['1'].Master
if ($masterDrive.IsAvailable) {
    $projectsPath = Join-Path -Path $masterDrive.Path -ChildPath 'PSmm.Projects'
}

# Iterate all storage groups
foreach ($groupKey in $Config.Storage.Keys) {
    $group = $Config.Storage[$groupKey]
    Write-Host "Group: $($group.DisplayName)"
}
```

## Public Functions

### Confirm-Storage

**Purpose**: Bootstrap validator that checks Master/Backup drives by serial number.

**Signature**:
```powershell
function Confirm-Storage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AppConfiguration]$Config)
}
```

**Behavior**:

1. Calls `Get-StorageDrive` to enumerate all physical drives
2. Iterates all storage groups in `$Config.Storage`
3. For each Master drive:
   - Searches for matching serial number in available drives
   - Updates `DriveLetter`, `Path`, `IsAvailable`, space metrics
   - Logs error if required Master is missing
4. For each Backup drive:
   - Same validation process
   - Respects `Optional` flag (future feature)
5. Persists updated configuration via `AppConfigurationBuilder::WriteStorageFile()`

**Called By**: `Invoke-PSmm` during bootstrap (line 234 of `PSmm.ps1`)

**Error Handling**: Missing Master drives are logged to `$Config.InternalErrorMessages.Storage`

---

### Get-StorageDrive

**Purpose**: Public wrapper around `StorageService` for drive discovery.

**Signature**:
```powershell
function Get-StorageDrive {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]], [object[]])]
    param()
}
```

**Refactored Implementation** (v1.1.0):

```powershell
function Get-StorageDrive {
    try {
        $storageService = [StorageService]::new()
        return $storageService.GetStorageDrives()
    }
    catch {
        Write-Error "Failed to retrieve storage drive information: $_"
        throw
    }
}
```

**Returns**: Array of PSCustomObjects with properties:
- `Label`, `DriveLetter`, `SerialNumber`, `Number`
- `Manufacturer`, `Model`, `Name`
- `FileSystem`, `PartitionKind`, `BusType`, `InterfaceType`, `DriveType`
- `TotalSpace`, `FreeSpace`, `UsedSpace` (in GB)
- `HealthStatus`, `IsRemovable`

**Platform Compatibility**: Returns empty array on non-Windows systems (handled in `StorageService`)

---

### Invoke-StorageWizard

**Purpose**: Interactive wizard for adding/editing storage groups.

**Signature**:
```powershell
function Invoke-StorageWizard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Add', 'Edit')][string]$Mode,
        [Parameter(Mandatory)][AppConfiguration]$Config,
        [string]$GroupId,  # Required for Edit mode
        [string]$TestInputs  # Semicolon-delimited inputs for testing
    )
}
```

**Workflow**:

1. **Step 1**: Prompt for `DisplayName`
2. **Step 2**: Select Master drive from available USB/removable drives
3. **Step 3**: Select Backup drive(s) (can add multiple)
4. **Duplicate Detection**: Calls `Test-DuplicateSerial` before adding
5. **Persistence**: Writes to `PSmm.Storage.psd1` via `AppConfigurationBuilder`
6. **Auto-Renumbering**: Groups are renumbered sequentially (1, 2, 3...) on write

**Test Mode**: Set `$env:MEDIA_MANAGER_TEST_INPUTS` for automated testing

**Example Usage**:

```powershell
# Add new storage group
Invoke-StorageWizard -Mode Add -Config $Config

# Edit existing group
Invoke-StorageWizard -Mode Edit -Config $Config -GroupId '1'
```

---

### Invoke-ManageStorage

**Purpose**: Interactive menu for storage management.

**Signature**:
```powershell
function Invoke-ManageStorage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AppConfiguration]$Config)
}
```

**Menu Options**:

- **[E]dit**: Modify existing storage group
- **[A]dd**: Create new storage group
- **[R]emove**: Delete storage group(s)
- **[B]ack**: Return to main menu

**Delegates To**:
- `Invoke-StorageWizard` (for Add/Edit)
- `Remove-StorageGroup` (for Remove)

---

### Remove-StorageGroup

**Purpose**: Removes one or more storage groups and renumbers remaining.

**Signature**:
```powershell
function Remove-StorageGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AppConfiguration]$Config,
        [Parameter(Mandatory)][string[]]$GroupIds
    )
}
```

**Behavior**:

1. Validates all `GroupIds` exist
2. Removes specified groups from `$Config.Storage`
3. Renumbers remaining groups sequentially (1, 2, 3...)
4. Persists to `PSmm.Storage.psd1`
5. Refreshes available drives display

**Safety**: Validates group existence before removal

---

### Show-StorageInfo

**Purpose**: Displays storage configuration summary.

**Signature**:
```powershell
function Show-StorageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AppConfiguration]$Config,
        [switch]$ShowDetails  # Include extended drive metadata
    )
}
```

**Output Example**:

```
Storage Configuration:
  Group 1: My Media Collection
    Master: Media-1 (Z:) - 512GB / 1024GB free
    Backup 1: Media-1-Backup-1 (Y:) - 256GB / 1024GB free
    Backup 2: Media-1-Backup-2 (Not Available)
```

---

### Test-DuplicateSerial

**Purpose**: Validates serial numbers for uniqueness across groups.

**Signature**:
```powershell
function Test-DuplicateSerial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AppConfiguration]$Config,
        [Parameter(Mandatory)][string]$SerialNumber,
        [string]$ExcludeGroupId  # Exclude this group from duplicate check
    )
    [OutputType([bool])]
}
```

**Returns**: `$true` if duplicate exists, `$false` otherwise

**Use Case**: Called by `Invoke-StorageWizard` before adding/editing drives

## Classes

### StorageDriveConfig

**Location**: `src/Modules/PSmm/Classes/AppConfiguration.ps1` (lines 378-433)

**Constructor**:
```powershell
StorageDriveConfig()                                    # Empty constructor
StorageDriveConfig([string]$label, [string]$driveLetter) # Initialize with label
```

**Methods**:

```powershell
[void] UpdateStatus()
```

- Updates `IsAvailable`, `FreeSpaceGB`, `TotalSpaceGB`, `Path` by querying `Get-PSDrive`
- Respects test mode (`$env:MEDIA_MANAGER_TEST_MODE = '1'`) to skip live probing
- Safely handles missing drives (sets `IsAvailable = $false`)

```powershell
[string] ToString()
```

- Returns formatted string: `"Media-1 (Z:) - 512GB free of 1024GB"` or `"Media-1 (Not Available)"`

---

### StorageGroupConfig

**Location**: `src/Modules/PSmm/Classes/AppConfiguration.ps1` (lines 434-479)

**Constructor**:
```powershell
StorageGroupConfig()                # Empty constructor
StorageGroupConfig([string]$groupId) # Initialize with GroupId
```

**Methods**:

```powershell
[bool] IsValid()
```

- Returns `$true` if Master drive exists and is available
- Used to filter valid storage groups for UI/Projects

```powershell
[void] UpdateStatus()
```

- Calls `UpdateStatus()` on Master and all Backup drives
- Should be called after `Confirm-Storage` updates drive letters

## StorageService

**Location**: `src/Modules/PSmm/Classes/Services/StorageService.ps1` (NEW in v1.1.0)

**Purpose**: Testable abstraction for storage drive operations.

**Interface**: `IStorageService`

**Methods**:

```powershell
[object[]] GetStorageDrives()
```

- Wraps Windows CIM APIs (Win32_DiskDrive, Win32_LogicalDisk, Get-Disk, Get-Volume)
- Returns array of drive metadata objects (same structure as old `Get-StorageDrive`)
- Platform-safe: Returns empty array on non-Windows systems
- Filters for drives with valid partitions and volumes

```powershell
[object] FindDriveBySerial([string]$serialNumber)
```

- Searches for drive matching the specified serial number
- Returns single matching drive or `$null`
- Throws `ArgumentException` if `$serialNumber` is empty

```powershell
[object] FindDriveByLabel([string]$label)
```

- Searches for drive matching the specified volume label
- Returns single matching drive or `$null`
- Throws `ArgumentException` if `$label` is empty

```powershell
[object[]] GetRemovableDrives()
```

- Filters drives where `IsRemovable = $true`
- Used by `Invoke-StorageWizard` to show only USB/removable drives
- Returns empty array if no removable drives found

**Error Handling**:

- Verbose logging for skipped disks/partitions (no metadata, no volumes)
- Graceful handling of CIM query failures (continues to next disk)
- Throws `InvalidOperationException` for catastrophic failures

**Example Usage**:

```powershell
# Direct usage in new code
$storageService = [StorageService]::new()
$drives = $storageService.GetStorageDrives()

# Find specific drive
$masterDrive = $storageService.FindDriveBySerial('R381505X0SNNM7S')
if ($masterDrive) {
    Write-Host "Found: $($masterDrive.Label) at $($masterDrive.DriveLetter)"
}

# Get removable drives only
$usbDrives = $storageService.GetRemovableDrives()
```

**Testing Benefits**:

- Mock `IStorageService` in tests without touching real hardware
- Inject deterministic drive data for edge case testing
- Validate logic independently of CIM API availability

## Usage Examples

### Bootstrap Integration

**Application Startup** (`src/PSmm.ps1`, line 234):

```powershell
#region ----- Confirm Storage Structure
Write-PSmmLog -Level NOTICE -Context 'Confirm-Storage' `
    -Message 'Checking Master and Backup Storage' -Console -File
Confirm-Storage -Config $Config
Write-Verbose "Storage structure confirmed"
#endregion
```

**Effect**:

- Validates all configured storage groups
- Updates drive letters for available drives
- Logs errors for missing required drives
- UI/Projects modules can safely access `$Config.Storage` afterward

---

### UI Module: Drive Selection

**Location**: `src/Modules/PSmm.UI/Public/Invoke-PSmmUI.ps1` (lines 151-182)

```powershell
# Display available storage groups
Write-PSmmHost "`nAvailable Storage Groups:" -Style Info
foreach ($groupKey in ($Config.Storage.Keys | Sort-Object)) {
    $masterDrive = $Config.Storage.$groupKey.Master
    if ($masterDrive.IsAvailable) {
        Write-PSmmHost " [$groupKey] $($masterDrive.Label) ($($masterDrive.DriveLetter))"
    }
}

# Get user selection
$GroupSelection = Read-Host "`nSelect storage group number"

# Validate selection
$MatchingKey = $Config.Storage.Keys | 
    Where-Object { $_.ToString() -eq $GroupSelection.ToString() } | 
    Select-Object -First 1

if (-not $MatchingKey -or -not $Config.Storage[$MatchingKey].IsValid()) {
    Write-Warning "Invalid or unavailable storage group '$GroupSelection'"
    return
}
```

---

### Projects Module: Project Discovery

**Location**: `src/Modules/PSmm.Projects/Public/Get-PSmmProjects.ps1` (lines 103-248)

```powershell
# Scan all storage groups for projects
foreach ($storageGroup in ($Storage.Keys | Sort-Object)) {
    $MasterStorage = $Storage[$storageGroup].Master
    
    if ($null -ne $MasterStorage -and $MasterStorage.IsAvailable) {
        $masterProjectsPath = Join-Path -Path $MasterStorage.Path `
            -ChildPath 'PSmm.Projects'
        
        if (Test-Path $masterProjectsPath) {
            # Discover projects on Master drive
            $projectFolders = Get-ChildItem -Path $masterProjectsPath `
                -Directory -ErrorAction SilentlyContinue
            
            foreach ($folder in $projectFolders) {
                # ... process project metadata
            }
        }
    }
    
    # Also scan Backup drives
    $BackupStorage = $Storage[$storageGroup].Backups
    foreach ($backupId in ($BackupStorage.Keys | Sort-Object)) {
        $backupDrive = $BackupStorage[$backupId]
        if ($backupDrive.IsAvailable) {
            # ... scan backup drive for projects
        }
    }
}
```

---

### Custom Script: Drive Health Check

```powershell
Import-Module PSmm

# Get current configuration
$Config = [AppConfiguration]::new()
[AppConfigurationBuilder]::LoadConfiguration($Config, $PSScriptRoot)

# Check all storage groups
foreach ($groupKey in $Config.Storage.Keys) {
    $group = $Config.Storage[$groupKey]
    
    Write-Host "`nStorage Group $groupKey: $($group.DisplayName)"
    
    # Check Master
    if ($group.Master.IsAvailable) {
        $freePercent = [math]::Round(
            ($group.Master.FreeSpaceGB / $group.Master.TotalSpaceGB) * 100, 2
        )
        Write-Host "  Master: $($group.Master.Label) - $freePercent% free"
        
        if ($freePercent -lt 10) {
            Write-Warning "  Master drive is running low on space!"
        }
    }
    else {
        Write-Warning "  Master drive '$($group.Master.Label)' is NOT AVAILABLE"
    }
    
    # Check Backups
    foreach ($backupId in $group.Backups.Keys) {
        $backup = $group.Backups[$backupId]
        if ($backup.IsAvailable) {
            Write-Host "  Backup $backupId: $($backup.Label) - OK"
        }
        else {
            Write-Warning "  Backup $backupId: '$($backup.Label)' is NOT AVAILABLE"
        }
    }
}
```

## Bootstrap Integration

### Initialization Sequence

```
1. Start-PSmediaManager.ps1
   │
   ├─> Invoke-PSmm
       │
       ├─> Initialize-Logging
       ├─> Confirm-PowerShell (version check)
       ├─> Confirm-Plugins (KeePassXC, digiKam, etc.)
       │
       ├─> Confirm-Storage ◄── STORAGE VALIDATION HERE
       │   │
       │   ├─> Get-StorageDrive (enumerate all physical drives)
       │   ├─> Match serial numbers to configured groups
       │   ├─> Update DriveLetter, Path, IsAvailable, FreeSpaceGB
       │   └─> Log errors for missing Master drives
       │
       ├─> Invoke-PSmmUI (if -UI specified)
       └─> Other initialization...
```

### Critical Bootstrap Dependencies

**Storage MUST be validated**:

1. **After Logging**: So errors can be logged
2. **Before UI**: So drive menus display correctly
3. **Before Projects**: So project discovery works

**Dependency Chain**:

```
Logging → Storage → UI/Projects
```

## Testing

### Test Files

**Unit Tests** (25+ files in `tests/Modules/PSmm/`):

- `Confirm-Storage.Tests.ps1` - Bootstrap validation logic
- `Get-StorageDrive.Tests.ps1` - Drive discovery (CIM mocking)
- `Invoke-StorageWizard.Tests.ps1` - Wizard workflow testing
- `Remove-StorageGroup.Tests.ps1` - Group removal & renumbering
- `Test-DuplicateSerial.Tests.ps1` - Serial uniqueness validation
- `AppConfigurationBuilder.Tests.ps1` - Storage file I/O

**Integration Tests**:

- `PSmm.UI.Tests.ps1` - Storage menu interactions
- `PSmm.Projects.Tests.ps1` - Project discovery on storage drives

### Test Helpers

**Location**: `tests/Support/TestConfig.ps1`

```powershell
function New-TestStorageDrive {
    param(
        [string]$Label,
        [string]$SerialNumber,
        [string]$DriveLetter = '',
        [bool]$IsAvailable = $false
    )
    
    $drive = [StorageDriveConfig]::new()
    $drive.Label = $Label
    $drive.SerialNumber = $SerialNumber
    $drive.DriveLetter = $DriveLetter
    $drive.IsAvailable = $IsAvailable
    return $drive
}

function Add-TestStorageGroup {
    param(
        [AppConfiguration]$Config,
        [string]$GroupId,
        [StorageDriveConfig]$Master,
        [hashtable]$Backups = @{}
    )
    
    $group = [StorageGroupConfig]::new($GroupId)
    $group.DisplayName = "Test Group $GroupId"
    $group.Master = $Master
    foreach ($backupId in $Backups.Keys) {
        $group.Backups[$backupId] = $Backups[$backupId]
    }
    
    $Config.Storage[$GroupId] = $group
    return $group
}
```

### Test Mode

**Environment Variable**: `$env:MEDIA_MANAGER_TEST_MODE = '1'`

**Effects**:

- `StorageDriveConfig::UpdateStatus()` skips live `Get-PSDrive` queries
- Allows testing without physical drives attached
- Mocked drives remain "available" during tests

**Usage in Tests**:

```powershell
BeforeAll {
    $env:MEDIA_MANAGER_TEST_MODE = '1'
}

AfterAll {
    $env:MEDIA_MANAGER_TEST_MODE = ''
}

It 'validates storage configuration without real drives' {
    $config = New-TestAppConfiguration
    $masterDrive = New-TestStorageDrive -Label 'Test-Master' `
        -SerialNumber 'TEST-001' -DriveLetter 'Z:' -IsAvailable $true
    Add-TestStorageGroup -Config $config -GroupId '1' -Master $masterDrive
    
    # Storage validation logic runs without touching real hardware
    Confirm-Storage -Config $config
    
    $config.Storage['1'].IsValid() | Should -Be $true
}
```

### Mocking StorageService

**Example**:

```powershell
BeforeAll {
    # Mock the StorageService for isolated testing
    Mock -CommandName 'StorageService' -MockWith {
        return [PSCustomObject]@{
            GetStorageDrives = {
                return @(
                    [PSCustomObject]@{
                        Label = 'Mock-Drive'
                        SerialNumber = 'MOCK-001'
                        DriveLetter = 'Z:'
                        IsRemovable = $true
                        TotalSpace = 1000
                        FreeSpace = 500
                    }
                )
            }
        }
    }
}

It 'uses mocked storage service' {
    $service = [StorageService]::new()
    $drives = $service.GetStorageDrives()
    $drives.Count | Should -Be 1
    $drives[0].Label | Should -Be 'Mock-Drive'
}
```

## Best Practices

### For Application Developers

1. **Always Validate Storage Early**: Call `Confirm-Storage` during bootstrap before accessing `$Config.Storage`

2. **Check `IsAvailable` Before Use**:
   ```powershell
   if ($Config.Storage['1'].Master.IsAvailable) {
       # Safe to access drive
   }
   ```

3. **Use Serial Numbers, Not Drive Letters**: Drive letters change; serial numbers don't

4. **Handle Missing Drives Gracefully**: Display warnings, don't crash

5. **Leverage `IsValid()`**: Filter valid storage groups in UI menus

6. **Use StorageService for New Code**: More testable than calling `Get-StorageDrive` directly

### For Module Developers

1. **Import PSmm Module**: Storage functions are exported from PSmm core

2. **Access via `$Config.Storage`**: Don't call storage functions directly in loops

3. **Don't Cache Drive Letters**: They can change between reboots

4. **Test Without Real Drives**: Use `$env:MEDIA_MANAGER_TEST_MODE = '1'`

5. **Mock StorageService**: Inject test data via IStorageService interface

### For Storage Configuration

1. **Use Descriptive Labels**: `Media-1`, `Media-1-Backup-1` (helps identify physical drives)

2. **Document Serial Numbers**: Keep a spreadsheet mapping labels to serial numbers

3. **Backup Configuration Files**: `PSmm.Storage.psd1` files are critical

4. **Test Failover**: Unplug Master, verify application handles gracefully

5. **Monitor Free Space**: Create health check scripts (see examples above)

### Common Pitfalls

❌ **DON'T**: Hardcode drive letters (`Z:\Projects`)  
✅ **DO**: Use `$Config.Storage['1'].Master.Path`

❌ **DON'T**: Assume Master is always available  
✅ **DO**: Check `IsAvailable` before access

❌ **DON'T**: Call `Get-StorageDrive` repeatedly in loops  
✅ **DO**: Call once, cache results

❌ **DON'T**: Modify `$Config.Storage` directly without persisting  
✅ **DO**: Use `AppConfigurationBuilder::WriteStorageFile()`

❌ **DON'T**: Test with live drives attached  
✅ **DO**: Use `$env:MEDIA_MANAGER_TEST_MODE = '1'` and mocks

## Migration Guide: Legacy to StorageService

### Before (Legacy)

```powershell
# Direct CIM calls everywhere
$allDrives = Get-StorageDrive
$myDrive = $allDrives | Where-Object { $_.SerialNumber -eq 'ABC123' }
```

### After (Refactored)

```powershell
# Use StorageService for better testability
$storageService = [StorageService]::new()
$myDrive = $storageService.FindDriveBySerial('ABC123')
```

### Backward Compatibility

The `Get-StorageDrive` function still exists as a public wrapper:

```powershell
function Get-StorageDrive {
    $storageService = [StorageService]::new()
    return $storageService.GetStorageDrives()
}
```

**Existing code continues to work** without modification. New code should prefer `StorageService` directly.

## Troubleshooting

### Issue: "Master drive not found"

**Symptoms**: `Confirm-Storage` logs errors about missing Master drive.

**Causes**:
1. Drive not physically connected
2. Serial number mismatch (wrong drive configured)
3. Drive failed health check (not detected by Windows)

**Solutions**:
1. Connect the drive and restart application
2. Run `Get-StorageDrive` to verify serial number
3. Check Windows Disk Management for drive health

---

### Issue: "Drive letter changed"

**Symptoms**: Projects not loading, paths invalid after reboot.

**Causes**:
- Windows assigned different drive letter
- New USB device took the expected letter

**Solutions**:
1. `Confirm-Storage` should auto-update drive letters
2. If not, restart application to re-detect drives
3. Assign static drive letters in Windows Disk Management (optional)

---

### Issue: "Storage configuration not persisting"

**Symptoms**: Changes made in `Invoke-StorageWizard` are lost after restart.

**Causes**:
1. `PSmm.Config` folder doesn't exist on drive root
2. Insufficient write permissions
3. Drive is read-only

**Solutions**:
1. Ensure drive root is writable
2. Check file permissions on `<DriveRoot>\PSmm.Config\`
3. Verify `AppConfigurationBuilder::WriteStorageFile()` completes without errors

---

### Issue: "CIM queries failing on non-Windows"

**Symptoms**: Empty drive list on Linux/WSL.

**Causes**:
- CIM APIs not available on non-Windows platforms

**Solutions**:
1. This is expected behavior (returns empty array)
2. Storage features only supported on Windows
3. Use test mode for cross-platform development: `$env:MEDIA_MANAGER_TEST_MODE = '1'`

## Future Enhancements

### Planned Features

1. **Optional Flag**: Mark Backup drives as optional (don't error if missing)
2. **Health Monitoring**: Periodic background checks for drive health
3. **Space Alerts**: Notify when drives reach capacity thresholds
4. **Network Drives**: Support for SMB/NFS storage (in addition to USB)
5. **Storage Pools**: Group multiple drives into logical pools
6. **Auto-Balancing**: Distribute projects across drives by free space

### Extensibility

New storage providers can implement `IStorageService`:

```powershell
class NetworkStorageService : IStorageService {
    [object[]] GetStorageDrives() {
        # Query SMB shares instead of CIM
    }
    
    [object] FindDriveBySerial([string]$serialNumber) {
        # Match by UNC path or share name
    }
}
```

## Related Documentation

- [Architecture Overview](architecture.md) - High-level system design
- [Modules Overview](modules.md) - Module responsibilities
- [Configuration Guide](configuration.md) - Application configuration
- [Development Guide](development.md) - Contributing guidelines

## Changelog

### v1.1.0 (November 27, 2025)

- ✅ **Refactored**: `Get-StorageDrive` now wraps `StorageService` class
- ✅ **Added**: `IStorageService` interface for testability
- ✅ **Added**: `StorageService` class with `GetStorageDrives()`, `FindDriveBySerial()`, `FindDriveByLabel()`, `GetRemovableDrives()`
- ✅ **Improved**: Error handling with `InvalidOperationException`
- ✅ **Documented**: Comprehensive storage documentation (this file)

### v1.0.0 (Initial Release)

- Storage drive discovery via CIM APIs
- Master/Backup drive configuration
- On-drive persistence (`PSmm.Storage.psd1`)
- Interactive storage wizard
- Bootstrap integration with `Confirm-Storage`

---

**Document Version**: 1.1.0  
**Last Updated**: November 27, 2025  
**Author**: Der Mosh
