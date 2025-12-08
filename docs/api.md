# PSmediaManager Public API Documentation

**Version:** 1.0.0  
**Last Updated:** 2025-12-07

This document defines the public API surface for PSmediaManager. Functions listed here are part of the stable public interface and can be safely used by external scripts and extensions.

## Public API Functions

### Core Application

#### `Invoke-PSmm`
Main entry point for the PSmediaManager application. Initializes the environment, loads configuration, and orchestrates the application lifecycle.

**Module:** PSmm  
**Stability:** Stable

---

### Configuration Management

#### `Export-SafeConfiguration`
Exports application configuration with sensitive data redacted. Safe for sharing and debugging purposes.

**Module:** PSmm  
**Stability:** Stable

#### `Get-PSmmHealth`
Retrieves health status of the PSmediaManager application and its dependencies.

**Module:** PSmm  
**Stability:** Stable

---

### File System Operations

#### `New-CustomFileName`
Generates custom filenames based on configurable patterns and metadata.

**Module:** PSmm  
**Stability:** Stable

#### `New-DirectoriesFromHashtable`
Creates a directory structure from a hashtable definition.

**Module:** PSmm  
**Stability:** Stable

---

### Storage Management

#### `Confirm-Storage`
Validates storage configuration and availability.

**Module:** PSmm  
**Stability:** Stable

#### `Get-StorageDrive`
Retrieves information about configured storage drives.

**Module:** PSmm  
**Stability:** Stable

#### `Invoke-StorageWizard`
Interactive wizard for configuring storage locations.

**Module:** PSmm  
**Stability:** Stable

#### `Invoke-ManageStorage`
Management interface for storage operations.

**Module:** PSmm  
**Stability:** Stable

#### `Remove-StorageGroup`
Removes a storage group from configuration.

**Module:** PSmm  
**Stability:** Stable

#### `Test-DuplicateSerial`
Checks for duplicate drive serial numbers in storage configuration.

**Module:** PSmm  
**Stability:** Stable

#### `Show-StorageInfo`
Displays detailed information about configured storage.

**Module:** PSmm  
**Stability:** Stable

---

### Secret Management (KeePassXC Integration)

#### `Get-SystemSecret`
Retrieves a secret from the KeePassXC vault.

**Module:** PSmm  
**Stability:** Stable  
**Note:** Requires KeePassXC CLI to be installed and configured.

#### `Initialize-SystemVault`
Initializes the system secret vault for first-time use.

**Module:** PSmm  
**Stability:** Stable

#### `Save-SystemSecret`
Saves a secret to the KeePassXC vault.

**Module:** PSmm  
**Stability:** Stable

---

### Utilities

#### `New-DriveRootLauncher`
Creates a launcher script in the drive root for portable execution.

**Module:** PSmm  
**Stability:** Stable

#### `Write-PSmmHost`
Centralized host output function for consistent logging and display.

**Module:** PSmm  
**Stability:** Stable

---

## Internal Functions (Not Part of Public API)

The following functions exist in the codebase but are **NOT** part of the public API. They are subject to change without notice and should not be used by external scripts:

- `Get-KeePassCli` (moved to Private, internal bootstrap helper)
- `Get-SystemSecretMetadata` (internal helper for Get-SystemSecret)
- `Invoke-HttpRestMethod` (internal HTTP service wrapper)
- All functions in `Private/` folders

---

## Module Dependencies

### PSmm (Core Module)
Foundation module containing classes, services, and core functionality.

**Dependencies:** None  
**Exports:** All functions listed above

### PSmm.Logging
Structured logging functionality.

**Dependencies:** PSmm  
**Exports:** See PSmm.Logging documentation

### PSmm.Plugins
Plugin orchestration and external tool integration.

**Dependencies:** PSmm, PSmm.Logging  
**Exports:** See PSmm.Plugins documentation

### PSmm.Projects
Project management functionality.

**Dependencies:** PSmm  
**Exports:** See PSmm.Projects documentation

### PSmm.UI
User interface components.

**Dependencies:** PSmm, PSmm.Logging, PSmm.Plugins, PSmm.Projects  
**Exports:** See PSmm.UI documentation

---

## Breaking Changes Policy

This public API follows semantic versioning:

- **Major version changes** (e.g., 1.x.x → 2.0.0) may include breaking changes
- **Minor version changes** (e.g., 1.0.x → 1.1.0) add new features without breaking existing ones
- **Patch version changes** (e.g., 1.0.0 → 1.0.1) fix bugs without changing the API

---

## Support

For issues, questions, or contributions:

- **Repository:** <https://github.com/mosh666/PSmediaManager>
- **Issues:** <https://github.com/mosh666/PSmediaManager/issues>
- **License:** MIT

---

## Changelog

### 2025-12-07 - API Cleanup
- Removed unused `ProjectInfo` and `PortInfo` classes from public API
- Removed factory functions: `New-ProjectInfo`, `New-PortInfo`, `Get-ProjectInfoFromPath`
- Moved internal functions to Private folder: `Get-KeePassCli`
- Removed from exports: `Get-SystemSecretMetadata`, `Invoke-HttpRestMethod`
- Clarified public vs. internal API boundaries
