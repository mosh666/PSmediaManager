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
- Uses a shim (`New-FileSystemService`) to construct the `FileSystemService` class lazily so logging functions work in isolation (e.g., when only PSmm.Logging is imported during tests).
- Dedicated specs (`Initialize-Logging.Tests.ps1`, `Invoke-LogRotation.Tests.ps1`) exercise the helper and rotation paths to guard against regressions.

## PSmm.Plugins

External tool acquisition & lifecycle management with manifest-based configuration.

Key Functions:

```text
Confirm-Plugins
Resolve-PluginsConfig
Install-KeePassXC
Start-PSmmdigiKam / Stop-PSmmdigiKam
Get-PSmmAvailablePort / Get-PSmmProjectPorts
Initialize-PSmmProjectDigiKamConfig
```

### Plugin Manifest System

Plugins are defined in `src/Config/PSmm/PSmm.Plugins.psd1` (global defaults) with optional project-level overrides:

- **Global Manifest**: Authoritative definitions for all available plugins
- **Project Manifest**: Per-project `Config/PSmm/PSmm.Plugins.psd1` can override `Enabled` flag for optional plugins
- **Resolution**: `Resolve-PluginsConfig` merges configurations with conflict validation

### Plugin Properties

Each plugin includes:
- `Mandatory`: Core requirement (`$true`) vs optional tool (`$false`)
- `Enabled`: Activation state (overridable per-project for optional plugins)
- `Source`: Acquisition method (`GitHub`, `Url`)
- `AssetPattern`: Regex for deterministic asset selection
- `Command`: Executable filename
- `CommandPath`: Relative path within plugin directory
- `RegisterToPath`: Whether to add to Process PATH

Asset Patterns:

- Regex-like patterns ensure deterministic selection (e.g. portable ImageMagick builds).
- Patterns support version capture groups for automated version resolution.

Extension:

1. Add definition entry to `src/Config/PSmm/PSmm.Plugins.psd1`.
2. Set appropriate `Mandatory` and `Enabled` flags.
3. Implement acquisition logic if special handling needed.
4. Add tests for version resolution.
5. Document any project-level override requirements.

### Configuration Access

After `Invoke-PSmm` or `Select-PSmmProject`:

```powershell
$resolvedPlugins = $Config.Plugins.Resolved
$isFFmpegEnabled = $Config.Plugins.Resolved.c_Misc.FFmpeg.Enabled
$pluginState = $Config.Plugins.Resolved.b_GitEnv.GitVersion.State
```

See [Configuration](configuration.md) for detailed plugin manifest documentation.

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
