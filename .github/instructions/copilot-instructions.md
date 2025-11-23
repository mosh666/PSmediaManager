# PSmediaManager AI Guide
## Big Picture
- `src/PSmediaManager.ps1` is the only entrypoint; it imports modules in strict order (PSmm→PSmm.Logging→PSmm.Plugins→PSmm.Projects→PSmm.UI), constructs `[AppConfiguration]` via `AppConfigurationBuilder`, runs `Invoke-PSmm`, then `Invoke-PSmmUI` unless `-NonInteractive`.
- `src/Modules/PSmm/PSmm.psm1` loads classes/services/DI before dot-sourcing public/private functions; touching loader order will break type resolution because interfaces/exceptions/services build on each other.
- Bootstrapping in `src/Modules/PSmm/Public/Bootstrap/Invoke-PSmm.ps1` handles folder creation, logging, vault provisioning, secret loading, requirement checks, storage validation, and version discovery; new setup steps belong here so cleanup still fires.
- UI flows live in `src/Modules/PSmm.UI/Public/Invoke-PSmmUI.ps1` and expect project data from `Get-PSmmProjects`; keep UI changes aligned with that structure.
## Configuration & Storage
- `src/Modules/PSmm/Classes/AppConfigurationBuilder.ps1` merges `Config/PSmm/PSmm.App.psd1` + `PSmm.Requirements.psd1`, matches disks via serial numbers (`Get-StorageDrive`), and hydrates typed objects (`AppPaths`, `StorageGroupConfig`, `AppSecrets`); avoid loosening code to raw hashtables.
- Storage definitions (`src/Config/PSmm/PSmm.App.psd1`) rely on numeric group keys and master/backup serials; `Confirm-Storage` and `UpdateStorageStatus()` update drive letters automatically—never hardcode letters in code.
- Projects must be emitted as `@{ Master = @{ <DriveLabel> = @(projects) }; Backup = @{ ... } }`; `Get-PSmmProjects` caches registry data under `Config.Projects.Registry` and flags changes via drive timestamps, so extend caching through that API.
- Secrets are always pulled via `AppConfiguration.Secrets` and KeePassXC; first-run logic sits in `Invoke-FirstRunSetup` and `Test-SecretsSecurity`, so don't reach for plaintext token files.
## Plugin Integrations
- `src/Modules/PSmm.Plugins` owns all external plugin orchestration (Confirm-Plugins, digiKam helpers, etc.) while Requirements stay in `src/Config/PSmm/PSmm.Requirements.psd1` grouped alphabetically (`a_Essentials`, `b_GitEnv`, …); `Confirm-Plugins` walks those groups, uses injectable `Http/FileSystem/Process` services, and installs everything under `App.Paths.App.Plugins` (Root/_Downloads/_Temp) without mutating the session PATH—callers must reference plugin install paths directly.
- Adding or updating a plugin means editing the PSD1 (asset patterns, commands, GitHub repo info) and letting the pipeline handle download + version detection; prefer custom `Get-CurrentVersion-<Plugin>` helpers when directory names are ambiguous.
- digiKam templates under `src/Config/digiKam/` are copied by `Initialize-PSmmProjectDigiKamConfig`; keep these assets in sync with UI flows before referencing new metadata knobs.
## Logging & Diagnostics
- `Initialize-Logging` (`src/Modules/PSmm.Logging/Public/Initialize-Logging.ps1`) ensures PSLogs is installed, builds filenames like `yyyyMMdd-PSmm-<user>@<machine>.log`, and clears the file only in `-Dev` runs; always call it before `Write-PSmmLog`.
- Use `Write-PSmmLog -Context <Area>` instead of `Write-Host` for operational output; bootstrap and UI paths expect NOTICE/INFO/SUCCESS levels for console mirroring.
- `Get-ApplicationVersion` shells out to `gitversion.exe` (falling back to `git describe`); missing Git metadata returns `Unknown-Version`, so gate features accordingly.
## Developer Workflow
- Run the app through `pwsh -File src/PSmediaManager.ps1 -Dev -Verbose` for local work, `-Update` to force plugin refresh, and `-NonInteractive` for CI bootstrap-only validation.
- Tests: `pwsh -File tests/Invoke-Pester.ps1 [-CodeCoverage] [-TestPath tests/Modules/PSmm,tests/Modules/PSmm.Plugins]`; the harness exports `MEDIA_MANAGER_TEST_MODE=1` and `MEDIA_MANAGER_SKIP_READKEY=1` so your code should honor those env vars instead of exiting.
- After ANY code edit, execute `pwsh -NoProfile -File ./.codacy/Invoke-CodacyWSL.ps1 -RepositoryPath "." -Verbose`; if you add dependencies, immediately rerun with `-CliArguments analyze --tool trivy` before continuing.
- Logs land under `src/Log/`; check them after bootstrap or UI work to confirm plugin installs, storage matches, and project scans.
## Coding Patterns
- Every script/function starts with `#Requires -Version 7.5.4` and `Set-StrictMode -Version Latest`; public functions accept `[AppConfiguration]$Config` parameter.
- Service classes live in `src/Modules/PSmm/Classes/Services/*` and are resolved via the DI container (`Classes/DependencyInjection.ps1`); inject these when adding IO/Process/HTTP logic so tests can swap implementations.
- UI identifiers use `B##` tokens for backups and rely on per-drive color themes from `PSmm.App.psd1`; preserve those conventions if you surface new menu options.
- Cleanup is centralized in `src/PSmediaManager.ps1` (safe config export, PATH unregistration, module removal); helper functions should throw exceptions and let that finally block run instead of calling `exit`.
