# Architecture

This document explains how PSmediaManager composes modules, services, and external tooling to deliver a portable media management experience.

## Layered View

```text
┌───────────────────────────────────────────────┐
│ User Entry Points                             │
│ • Start-PSmediaManager.ps1                    │
│ • Invoke-PSmm / Invoke-PSmmUI                 │
└───────────────────────────────────────────────┘
              │ (bootstraps modules)
┌───────────────────────────────────────────────┐
│ Modules                                       │
│ • PSmm (core)                                 │
│ • PSmm.Logging                                │
│ • PSmm.Plugins                                │
│ • PSmm.Projects                               │
│ • PSmm.UI                                     │
└───────────────────────────────────────────────┘
              │ (depend on)
┌───────────────────────────────────────────────┐
│ Services (Classes/Services)                   │
│ FileSystemService, EnvironmentService,        │
│ ProcessService, HttpService, GitService,      │
│ CryptoService, CimService, etc.               │
└───────────────────────────────────────────────┘
              │ (wrap)
┌───────────────────────────────────────────────┐
│ External Tools / OS APIs                      │
│ Portable plugins (FFmpeg, digiKam, KeePassXC) │
│ PowerShell runtime & .NET APIs                │
└───────────────────────────────────────────────┘
```

## Execution Flow

1. `Start-PSmediaManager.ps1` launches PowerShell with strict mode and imports module manifests.
2. `Invoke-PSmm` initializes configuration, logging, storage directories, and secret providers.
3. Users interact either via `Invoke-PSmmUI` (menus) or individual functions (`Confirm-Plugins`, `New-PSmmProject`).
4. Plugin calls resolve tool assets and ensure executables exist before launching dependent workflows (e.g., digiKam startup script).
5. Logging is configured once per session; all modules write through `Write-PSmmLog` to keep a consistent format.

## Component Responsibilities

- **PSmm**: Hosts bootstrap routines, configuration builder, KeePassXC integration, storage orchestration, safe configuration export.
- **PSmm.Logging**: Wraps PSLogs; ensures timestamps, levels, rotation, and contextual metadata.
- **PSmm.Plugins**: Downloads/verifies portable binaries, tracks versions via `PSmm.Requirements.psd1`, launches services (MariaDB, digiKam).
- **PSmm.Projects**: Maintains project registry, ensures per-project directories/databases, exposes CRUD-style cmdlets.
- **PSmm.UI**: Provides ANSI-friendly prompts, multi-select choices, and dispatches to underlying commands.

## Data & Storage Layout

```text
<Drive Root>              # Production: drive root (e.g., D:\)
 ├─ PSmm.Log/            # Rotating logs (date-based filenames)
 ├─ PSmm.Plugins/        # Downloaded portable tools (FFmpeg, digiKam, etc.)
 │   ├─ _Downloads/      # Temporary download cache
 │   └─ _Temp/           # Extraction working directory
 └─ PSmm.Vault/          # KeePassXC database for secrets

<Repo Root>              # Repository structure
 ├─ src/
 │   ├─ Modules/         # Module manifests & implementations
 │   └─ Config/          # Requirements and template configs
 ├─ tests/               # Pester tests & coverage artifacts
 └─ docs/                # Documentation
```

**Path Resolution Strategy:**

- **Production Mode**: Runtime folders (`PSmm.Log`, `PSmm.Plugins`, `PSmm.Vault`) are placed at the drive root for easy access and management. This allows the application to maintain state independently of the source code location.

- **Test Mode**: When `MEDIA_MANAGER_TEST_MODE='1'` is set (automatically by `Invoke-Pester.ps1`), runtime folders are created within the test directory instead of the system drive. This ensures test isolation and prevents pollution of the system drive.

- **AppConfigurationBuilder**: Detects repository structure (presence of `src/` folder) and adjusts the runtime root accordingly:
  - In production: Uses `GetPathRoot()` to place runtime folders at drive root
  - In test mode: Uses the test root directory to contain all artifacts

Paths are derived from configuration objects to support relocating the repo or running in isolated test environments.

## Plugin Acquisition Lifecycle

1. Definitions live in `src/Config/PSmm/PSmm.Requirements.psd1` with fields: source, repo/base URI, asset pattern, command path, command name.
2. `Confirm-Plugins` iterates each definition, checking existing archives / extracted binaries.
3. Missing assets trigger download via HttpService or GitHub release APIs.
4. Archives are extracted using 7Zip4PowerShell into the managed plugin directory.
5. Commands are validated (hash/exists) before being registered for use.
6. Plugin start/stop helpers (e.g., `Start-PSmmdigiKam`) initialize environment variables and launch processes with explicit working directories.

## Environment & PATH Management

PSmediaManager implements intelligent PATH management through the `EnvironmentService` to make plugin tools available without polluting the system:

**Batch Operations**: Plugin directories are registered to PATH in a single batch operation using `AddPathEntries()` instead of multiple sequential calls. This improves performance and ensures atomic updates with proper ordering.

**Scope Control**: PATH modifications support two scopes:
- **Process Scope**: Always updated for immediate command availability in the current session
- **User Scope**: Optionally persisted when `$persistUser = true`, allowing commands to remain available after session exit

**Development Mode**: When PSmediaManager is launched with `-Dev`:
- Plugin PATH entries persist to User scope (`$persistUser = true`)
- Tools remain available in new terminal sessions without re-launching PSmediaManager
- Useful for development workflows and debugging

**Normal Mode**: In standard operation:
- Plugin PATH entries are Process-scoped only (`$persistUser = false`)
- All registered paths are automatically cleaned up on application exit
- Ensures zero host system pollution

**Deduplication**: The service uses `HashSet<string>` for O(1) lookups and prevents duplicate entries across multiple registration attempts. Existing PATH entries are detected upfront to avoid redundant operations.

**Implementation Details**:
- `Register-PluginsToPATH` collects all plugin directories, checks for pre-existing entries, and batch-registers new paths
- `BootstrapServices.ps1` provides early environment service access before module imports
- Cleanup logic in `PSmediaManager.ps1` uses `RemovePathEntries()` for efficient batch removal

## Configuration & Secrets

- `AppConfigurationBuilder` pulls defaults, environment info (drive roots), and user overrides (future persisted files).
- Secret values never live in plaintext; helper cmdlets wrap KeePassXC CLI for storage/retrieval.
- `Export-SafeConfiguration` converts configuration to a sanitized script for bug reports (redacting secret placeholders, quoting scalars, detecting cycles).

## Logging Pipeline

1. `Initialize-Logging` configures log sinks (console, file) and severity.
2. Modules call `Write-PSmmLog` with structured payloads; optional context via `Set-LogContext` (e.g., project name, plugin).
3. Log rotation can be triggered manually (`Invoke-LogRotation`) or scheduled externally for long-running sessions.
4. Future enhancement: emit JSON lines for ingestion by observability stacks.

## Extending the Architecture

- **New Modules**: create dedicated folder + manifest, expose only intentional public functions, add tests & docs.
- **New Services**: implement under `Classes/Services`; keep them stateless and injectable (pass dependencies rather than using globals).
- **Additional Plugins**: expand requirements file, implement install/verify helpers, document in README and `docs/modules.md`.
- **Automation**: integrate GitHub Actions for lint/test, publish artifacts, and optionally sign releases.

## Quality Assurance Flow

- Developers and CI both call `tests/Invoke-Pester.ps1 -WithPSScriptAnalyzer -CodeCoverage`, ensuring analyzer preloading, coverage enforcement, and exit-code parity between local machines and GitHub Actions.
- Standalone analyzer runs (`tests/Invoke-PSScriptAnalyzer.ps1`) dot-source `tests/Preload-PSmmTypes.ps1` so Windows and Linux runners share the same type resolution path, eliminating `TypeNotFound` noise before errors are surfaced.
- GitHub Actions uploads analyzer/test/coverage artifacts, while Codacy SARIF uploads (via `codacy.yml`) keep GitHub Advanced Security dashboards populated with PowerShell-specific findings.

For conceptual entry points refer back to [docs/index.md](index.md) and module-specific pages.
