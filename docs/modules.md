# Modules Overview

This document expands on module responsibilities, public APIs, and extension practices.

## PSmm (Core)

Purpose: Bootstrapping, storage confirmation, secrets integration, configuration lifecycle.

Key Functions:

```text
Invoke-PSmm
Confirm-Storage / Get-StorageDrive
Export-SafeConfiguration
Get-SystemSecret / Save-SystemSecret / Initialize-SystemVault
New-CustomFileName
```

Key Services:

```text
StorageService (Classes/Services/StorageService.ps1)
- GetStorageDrives(), FindDriveBySerial(), FindDriveByLabel()
- Testable abstraction for drive discovery via Windows CIM APIs
```

Extension Tips:

- Keep cross-cutting concerns (logging, UI) out of the core.
- Add new services under `Classes/Services` when logic grows beyond simple functions.
- Use `Write-PSmmHost` (exported from the core module) instead of raw `Write-Host` so shutdown messaging, analyzer suppressions, and UI parity remain intact.
- For storage operations, prefer using `StorageService` class directly for better testability.

Storage Documentation:

- See [Storage Drive Management](storage.md) for comprehensive documentation on storage subsystem architecture, configuration, and usage patterns.

## PSmm.Logging

Structured logging abstraction.

Key Functions:

```text
Initialize-Logging
Write-PSmmLog
Set-LogContext
Invoke-LogRotation
```

Practices:

- Enrich context early (session id, project name).
- Keep log messages action-oriented & concise.
- Consider future JSON line output mode for ingestion pipelines.

## PSmm.Plugins

External tool acquisition & lifecycle management.

Key Functions:

```text
Confirm-Plugins
Install-KeePassXC
Start-PSmmdigiKam / Stop-PSmmdigiKam
Get-PSmmAvailablePort / Get-PSmmProjectPorts
Initialize-PSmmProjectDigiKamConfig
```

Asset Patterns:

- Regex-like patterns ensure deterministic selection (e.g. portable ImageMagick builds).

Extension:

1. Add definition entry to `PSmm.Requirements.psd1`.
2. Implement acquisition logic if special handling needed.
3. Add tests for version resolution.

## PSmm.Projects

Project isolation & registry management.

Key Functions:

```text
New-PSmmProject
Get-PSmmProjects
Select-PSmmProject
Clear-PSmmProjectRegistry
```

Practices:

- Keep project names human-readable & filesystem-safe.
- Ensure database paths are unique per project.

## PSmm.UI

Interactive console interface & prompting utilities.

Key Functions:

```text
Invoke-PSmmUI
Invoke-MultiOptionPrompt
```

Guidelines:

- Avoid business logic inside UI functions; delegate to services.
- Provide clear, short labels for option prompts.
- Emit console output via `Write-PSmmHost` to keep analyzer suppressions centralized and to respect the interactive/CI separation baked into the wrapper.

## Adding a New Module

1. Create folder under `src/Modules/<Name>`.
2. Author manifest `<Name>.psd1` with minimal exports & metadata.
3. Implement `<Name>.psm1` internal functions; expose only stable public ones.
4. Add tests targeting new public functions.
5. Update `README.md` and this document.

Proceed to [Development](development.md) for contribution processes.
