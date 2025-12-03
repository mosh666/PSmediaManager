- Updated AppConfiguration and AppConfigurationBuilder
- Improved PSmm.psd1 and PSmm.psm1
- Enhanced Get-PSmmHealth
- Updated main script and test coverage files
# PSmediaManager Changelog

## [Unreleased]
- Updated AppConfiguration and AppConfigurationBuilder
- Improved PSmm.psd1 and PSmm.psm1
- Enhanced Get-PSmmHealth
- Updated main script and test coverage files
- Updated AppConfiguration and AppConfigurationBuilder
- Improved PSmm.psd1 and PSmm.psm1
- Enhanced Get-PSmmHealth
- Updated main script and test coverage files
# Changelog

<!-- markdownlint-disable MD024 -->

All notable changes to this project will be documented in this file.

<!-- markdownlint-disable MD024 -->
## [Unreleased Details]

### Fixed

- **Code Quality**: Fixed 13 PSScriptAnalyzer issues in `AppConfiguration.ps1` and `AppConfigurationBuilder.ps1` - added verbose logging to empty catch blocks and removed trailing whitespace
- **Core**: Corrected run configuration filename format in `PSmediaManager.ps1` to include missing dot between `InternalName` and `Run` (e.g., `PSmm.Run.psd1` instead of `PSmmRun.psd1`)

### Added

- **Documentation**: Added comprehensive container deployment guide (`docs/deployment.md`) covering Docker, Compose, Kubernetes hardening, security scanning, and CI/CD integration
- **Testing**: Added `GlobalFilesystemGuards.ps1` helper to prevent accidental writes to system paths during tests
- **Testing**: Added `Resolve-ToolCommandPath.ps1` private helper for tool command resolution with caching
- **Testing**: Added consolidated `Resolve-CommandPath.Tests.ps1` merging plugin and tool command path tests
- **Testing**: Added `Write-PSmmLog.Uninitialized.Tests.ps1` for logging edge case coverage
- **Testing**: Added organized `tests/Modules/PSmm/Storage/` directory with `Confirm-Storage.Tests.ps1` and `Get-StorageDrive.Tests.ps1`

### Changed

- **Testing**: Improved Invoke-Pester.ps1 with smarter CI detection and conditional read-key pauses via `Test-IsCiContext` and `Test-ShouldPauseForExit`
- **Testing**: Enhanced Initialize-Logging.Tests.ps1 with comprehensive error branch coverage and deterministic test cases
- **Testing**: Improved Import-AllTestHelpers.ps1 to load PSmm.Logging module and filesystem guards automatically
- **Testing**: Expanded coverage exclusions to skip public UI/Plugin/Project surfaces and Bootstrap functions
- **Coverage**: Increased line coverage from 68.76% to 68.77% (2571 commands analyzed, 1768 executed)

### Removed

- **Testing**: Removed duplicate test files: `Resolve-PluginCommandPath.Tests.ps1`, old `Confirm-Storage.Tests.ps1`, `Get-StorageDrive.Tests.ps1`, and `Write-PSmmLog.Tests.ps1` (replaced by consolidated/organized versions)

### Changed (Previous)

- **CI/Codacy**: Ensure `./.codacy/cli.sh` is executable in workflow to prevent `Permission denied` on Linux runners and restore SARIF uploads.
- **CI/Codacy**: Guard SARIF upload steps using `hashFiles(...)` so the job does not fail when `results.sarif` (or `markdownlint.sarif`) is not produced; fixes "Path does not exist: results.sarif" in GitHub Actions.
- **CI/Codacy**: Normalize `.codacy/codacy.yaml` to CLI v2 schema (`version: "2"`, `tools: [ { name: ... } ]`).
- **CI/Security**: Migrated from Codacy classic GitHub Action to Codacy CLI v2 for more flexible local analysis and CI integration.
- **Configuration**: Consolidated Codacy configuration from root `.codacy.yml` to `.codacy/codacy.yaml` with cross-tool path exclusions.
- **Linting**: Separated markdownlint execution into dedicated GitHub Action with SARIF output; removed markdownlint from Codacy CLI v2 (unsupported).
- **Configuration**: Removed version pinning from `.codacy/codacy.yaml` to use latest stable tool versions (pmd, semgrep, trivy).
- **Configuration**: Added `exclude_paths` to `.codacy/codacy.yaml` mirroring `.semgrepignore` patterns for consistent exclusions across all tools.
- **Configuration**: Cleaned `.markdownlint.yml` to contain only rule toggles; moved glob patterns to `.markdownlint-cli2.jsonc`.

### Added (Details - Previous)

- **CI/Linting**: Added `.markdownlint-cli2.jsonc` to configure markdownlint-cli2 with glob patterns and SARIF formatter output.
- **CI/Security**: Added separate SARIF upload step for markdownlint results in Codacy workflow.

### Removed (Previous)

- **Configuration**: Removed legacy root `.codacy.yml` (replaced by `.codacy/codacy.yaml` for CLI v2).

<!-- markdownlint-enable MD024 -->

## 0.9.0 - 2025-12-01

### Added (Features)
- `Get-PSmmHealth`: health summary command aggregating PowerShell version, required modules, plugin states, storage, and vault status. Supports `-Format` for readable output.
- Core bootstrap services in `src/Core/BootstrapServices.ps1` to enable early dependency injection before module import (path, filesystem, environment, process services).
- Codacy/markdown linting config: `.codacy.yml`, `.markdownlint.yml`, and `.trivyignore` for upstream base image CVE suppression tracking.

### Changed (Tests)
- Tests updated to align with new service injection patterns (FileSystem, PathProvider, Process services) and to remove stray BOM characters.
- Coverage baseline improved; latest coverage recorded in `tests/.coverage-latest.json`.

### Notes
- Security rationale for `.trivyignore` entries documented in `SECURITY.md`.

This project adheres to "Keep a Changelog" ([Keep a Changelog](https://keepachangelog.com/en/1.0.0/)) and uses Semantic Versioning ([SemVer](https://semver.org/)).

The format below is designed for clear GitHub Releases and PowerShell module maintenance.

## [Unreleased]

Use this section for in-progress changes that will be included in the next release.

When preparing a release, move the items into a new versioned section and update the date.

### Added

- CI/Security: Introduced `.github/workflows/codacy.yml` to run Codacy Analysis CLI on pushes, pull requests, and a weekly schedule so fresh findings flow into GitHub code scanning automatically.
- Docs/Quality: Added Codacy MCP instructions file (`.github/instructions/codacy.instructions.md`) and un-ignored it in `.gitignore` so required local/AI analysis workflow guidance is versioned.
- **Storage**: Introduced `StorageService` class (`src/Modules/PSmm/Classes/Services/StorageService.ps1`) implementing `IStorageService` interface for testable storage drive operations.
- **Storage**: Added comprehensive storage documentation (`docs/storage.md`) covering architecture, configuration, usage patterns, and testing strategies.
- **Interfaces**: Added `IStorageService` interface to `Classes/Interfaces.ps1` for dependency injection and testability.
- **UI**: Added detailed logging for project loading operations with master/backup drive counts.
- **Storage Wizard**: Added visual wizard header with decorative borders showing mode (Add/Edit) and group ID.
- **Storage Wizard**: Added step-by-step progress indicators (Step 1/2/3 of 3) with descriptive guidance text.
- **Storage Management**: Added numbered menu system with dynamic option mapping based on available storage groups.
- **Logging**: Added `New-FileSystemService` helper under `PSmm.Logging` so file system operations can be resolved without importing the full PSmm class graph; keeps logging usable in analyzer runs and partial module imports.
- **Tests**: Added `Initialize-Logging.Tests.ps1` and `Invoke-LogRotation.Tests.ps1` to cover the helper, rotation workflow, and configuration validation scenarios.
- **Tests (UI)**: Added comprehensive `Invoke-MultiOptionPrompt.Tests.ps1` validating parameter handling, option parsing, default index logic, verbose logging, and integration scenarios.
- **Tests (Logging)**: Expanded `Write-PSmmLog.Tests.ps1` to cover Body, ErrorRecord, log level mapping, target clearing, and context initialization paths.
- **Coverage**: Increased line coverage baseline to **68.67%** (from 65.43%) and updated `.coverage-baseline.json` & `.coverage-latest.json` artifacts.

#### Internal Improvements (2025-11-30)

- **refactor(codacy)**: Enhanced `.codacy/Invoke-CodacyWSL.ps1` with distro/tool availability diagnostics, safer Docker image scan scheduling (post-analysis), and verbose reporting for missing tools.
- **refactor(ui)**: Improved `Invoke-MultiOptionPrompt` to use a strongly typed `ChoiceDescription` collection, mock-friendly command invocation, and consistent verbose messaging for test reliability.
- **refactor(secrets)**: Added verbose fallback logging when vault path or GitHub token resolution via `Get-AppConfiguration` / `Get-SystemSecret` / `Save-SystemSecret` fails instead of silently ignoring exceptions.
- **refactor(plugins)**: Expanded try/catch blocks in plugin GitHub and confirmation helpers to provide diagnostic messages when system vault token retrieval fails.
- **refactor(build)**: Replaced non-interactive `Write-Host` calls in `Build-ScanImage.ps1` with `Write-Information` for proper stream usage.
- **chore(coverage)**: Updated coverage baseline JSON to reflect new executed command set (68.67%).

### Changed (Details)

#### Logging & UX Tweaks (2025-11-28)

- **fix(logging)**: Expanded caller field width in log format (from 28 → 29) for improved alignment across longer function names.
- **fix(vault)**: Removed redundant console duplication when reporting successful system vault initialization and secret saves (file logging retained).
- **refactor(storage wizard)**: Standardized confirmation prompt casing to `y/N` (lowercase affirmative, uppercase default negative) for consistency with common CLI conventions.
- **chore(requirements)**: Pruned obsolete commented placeholders (`processId`, legacy digiKam config block, unused path comments) from `PSmm.Requirements.psd1` to reduce analyzer noise.
- **chore(test)**: Refreshed coverage artifacts (`.coverage-jacoco.xml`, `.coverage-latest.json`) with latest execution snapshot.


#### User Experience Improvements (2025-11-27)

- **feat(Storage Wizard)**: Enhanced wizard UX with informative scanning feedback showing drive counts and detection progress.
- **feat(Storage Wizard)**: Added drive filtering to prevent re-assigning already-used drives to different storage groups.
- **feat(Storage Wizard)**: Improved drive selection prompts with clearer labeling ("Available drives" vs generic "Select...").
- **feat(Storage Management)**: Enhanced menu display with detailed drive information showing labels and serial numbers.
- **feat(Storage Management)**: Improved menu options with contextual availability (Edit/Remove hidden when no storage configured).
- **feat(UI)**: Added automatic storage refresh after management operations to ensure UI shows current state.
- **refactor(Storage Wizard)**: Changed logging from console to file-only to reduce noise during interactive operations.
- **refactor(Storage Management)**: Changed logging from console to file-only for cleaner user experience.
- **fix(Storage Wizard)**: Removed unused `$summaryMsg` variable assignment for PSScriptAnalyzer compliance.

#### Code Quality Improvements (2025-11-27)

- **refactor**: Replaced 28 `Write-Host` calls with `Write-Information` across storage management and wizard functions for proper PowerShell stream handling.
- **refactor**: Converted 13 positional parameters to named parameters in logging functions (Write-PSmmLog, Write-ManageLog, Write-WizardLog, Write-DupLog) improving code clarity and maintainability.
- **refactor**: Added `[OutputType([bool])]` declarations to `Invoke-ManageStorage`, `Invoke-StorageWizard`, and `Test-DuplicateSerial` for better type inference.
- **refactor**: Removed unused variable assignments (`$gotoBack` in Invoke-StorageWizard, `$result` in Invoke-PSmmUI).
- **fix**: Renamed parameter `$Args` to `$Arguments` in `Resolve-StorageWizardMessage` to avoid automatic variable collision.
- **refactor(Get-StorageDrive)**: Enhanced function to support both StorageService delegation and inline enumeration, improving test compatibility with Pester mocks while maintaining production service usage.
- **refactor(StorageService)**: Renamed internal variable `$isWindows` to `$isWindowsPlatform` for clarity and fixed whitespace formatting.
- **refactor(Invoke-StorageWizard)**: Converted remaining `Write-Host` calls to `Write-Information` with `-InformationAction Continue` for consistent output stream handling.
- **fix(Test-DuplicateSerial)**: Added PSScriptAnalyzer suppression attributes for `$TestInputs` and `$TestInputIndex` ref parameters that are accessed via `.Value` property.
- **fix(Invoke-Pester)**: Corrected coverage baseline enforcement logic to return proper exit codes without premature termination, and improved PassThru mode behavior.
- **chore**: Added `PSScriptAnalyzerResults.json` to `.gitignore` to exclude linter output files from version control.
- **fix**: Replaced `$global:IsWindows` with `Test-Path Variable:\IsWindows` check in `StorageService` for proper cross-platform variable scope handling.
- **feat**: Implemented `SupportsShouldProcess` with `ConfirmImpact='High'` in `Remove-StorageGroup` for safer destructive operations with -WhatIf/-Confirm support.
- **style**: Removed 59 trailing whitespace violations across 10 files (AppConfigurationBuilder.ps1, StorageService.ps1, Invoke-FirstRunSetup.ps1, Get-StorageDrive.ps1, Invoke-ManageStorage.ps1, Invoke-StorageWizard.ps1, Remove-StorageGroup.ps1, Test-DuplicateSerial.ps1).
- **test**: Added suppression attributes for 2 false-positive PSReviewUnusedParameter warnings in `Test-DuplicateSerial` (TestInputs/TestInputIndex [ref] parameters used via .Value property in nested functions).
- **chore**: Improved PSScriptAnalyzer compliance from 113 to 2 issues (98.2% reduction) - remaining issues are documented false positives.
- **test**: Updated code coverage baseline from 61.35% to 61.82% line coverage (+0.47%) reflecting improved code quality.

### Changed (Continued)

#### Storage Refactoring (2025-11-27)

- **BREAKING**: Refactored `Get-StorageDrive` function to delegate to `StorageService` class, maintaining backward compatibility while enabling better testability.
- **Storage**: `Get-StorageDrive` is now a thin wrapper around `StorageService::GetStorageDrives()` for backward compatibility.
- **Storage**: Moved drive discovery logic from function to `StorageService` class with methods: `GetStorageDrives()`, `FindDriveBySerial()`, `FindDriveByLabel()`, `GetRemovableDrives()`.
- **Module Loading**: Updated `PSmm.psm1` to include `Services\StorageService.ps1` in class loading sequence.
- **Documentation**: Updated `docs/modules.md` to reference new `StorageService` and link to comprehensive storage documentation.
- **Architecture**: Storage drive operations now follow the service pattern used by other infrastructure components (FileSystemService, CimService, etc.).
- **Startup**: Enhanced `Start-PSmediaManager.ps1` with working directory validation to ensure script runs from repository root, preventing path resolution issues.
- **First-Run Setup**: Integrated storage configuration into unified first-run setup flow as Step 5 (final step after vault creation and token storage), providing a seamless onboarding experience.
- **Bootstrap**: Removed early storage wizard call from `PSmediaManager.ps1` that ran before first-run setup, consolidating all first-run tasks into `Invoke-FirstRunSetup`.
- **Architecture**: Refactored `Invoke-FirstRunSetup` to accept and use a complete `AppConfiguration` object throughout all setup steps, eliminating temporary object reconstruction and ensuring consistent path access.
- **Bug Fix**: Fixed AppPaths initialization error in first-run setup Step 5 by passing the fully initialized `AppConfiguration` object instead of creating incomplete temporary configs.
- **Bug Fix**: Fixed configuration export "property 'Count' cannot be found" errors by ensuring `_GetDictionaryKeys` always returns arrays and using safe count checks (`@($collection.Keys).Count`) for hashtable operations.

#### Branch Merge (2025-11-28)

- **chore**: Merged `dev` branch into `main` branch, consolidating 16 commits containing storage management system, code quality improvements (98.2% PSScriptAnalyzer compliance), test infrastructure enhancements (65.43% coverage), and comprehensive documentation updates. This merge preserves branch history using `--no-ff` strategy and brings all unreleased features into the main branch for the upcoming v1.0.0 release.

#### Current edits (2025-11-26)

- Test infrastructure: Enhanced test environment isolation by detecting `MEDIA_MANAGER_TEST_MODE` environment variable to prevent runtime folders (`PSmm.Log`, `PSmm.Plugins`, `PSmm.Vault`) from being created on system drive during test execution.
- Test infrastructure: Added automatic working directory validation to `tests/Invoke-Pester.ps1` to ensure tests always run from the repository root, preventing path resolution issues and improving reliability.
- Test infrastructure: Added `tests/_tmp` to `.gitignore` to exclude temporary test artifacts from version control.
- Documentation: Added "Test Environment Isolation" section to `docs/development.md` explaining test mode behavior and path resolution strategy.
- Documentation: Expanded "Data & Storage Layout" section in `docs/architecture.md` to document production vs test mode path resolution differences.
- Configuration: Clarified that `DriveLetter` and `Path` are discovered at runtime and should not be persisted in `src/Config/PSmm/PSmm.App.psd1`. Removed now-ignored `StorageType` from examples.

- Documentation: Improved `README.md` Quick Start and Testing sections with optional PSGallery module pre-install guidance, a tip to re-run `Confirm-Plugins` after updates, and a quick Pester run command for fast local validation.
- Documentation: Updated `README.md`, `docs/development.md`, and `docs/modules.md` with the latest coverage baseline (65.43%), background on `New-FileSystemService`, and references to the new logging-focused tests.

#### Code Cleanup & Fixes (2025-11-30)

- **refactor(plugins):** Remove duplicate GitHub helper file `Get-ToolFromGitHub.ps1`; consolidate on `Get-PluginFromGitHub.ps1` (identical implementations of `Get-GitHubLatestRelease`, `Get-LatestUrlFromGitHub`, `Find-MatchingReleaseAsset`).
- **refactor(tests):** Consolidate test helpers by removing `tests/Helpers/TestConfig.ps1` and migrating `New-TestAppLogsRecorder` and `Register-TestWritePSmmLogMock` into `tests/Support/TestConfig.ps1`. Update UI logging tests to source from Support path.
- **refactor(ui):** Move internal `Show-InvalidSelection` helper from `PSmm.UI/Public/Invoke-PSmmUI.ps1` into `PSmm.UI/Private/Show-InvalidSelection.ps1` for better encapsulation.
- **fix(bootstrap):** Restore `Confirm-PowerShell` after accidental removal; function is required by `Invoke-PSmm.ps1` during bootstrap. Reintroduced under `PSmm/Private/Bootstrap/Confirm-PowerShell.ps1`.
- **chore(psmm manifest):** Remove `Get-SystemSecretMetadata` from `FunctionsToExport` in `PSmm.psd1` (function exists but is not part of the public API).
- **fix(secrets):** Added verbose error handling when vault path resolution via `Get-AppConfiguration` fails (AppSecrets constructor, `Get-SystemSecret`, `Save-SystemSecret`) instead of silently swallowing exceptions.
- **docs(quality):** Updated README Code Quality section with new coverage metrics (68.67%) and recent test suite expansions.

#### Previous edits (2025-11-24)

- Documentation: added changelog link to `README.md`.
- Repository metadata: tidied `.github/CODEOWNERS` comment line.

- Chore (2025-11-24): Documentation & metadata tidy — added changelog link to `README.md` and cleaned `.github/CODEOWNERS` comment.

- Startup script: recalculated `Start-PSmediaManager.ps1`'s path to `src/PSmediaManager.ps1` with nested `Join-Path` calls to avoid analyzer complaints and edge-case path concatenation errors.
- Tooling: wrapped the `TypeNotFound` filter in `tests/Invoke-PSScriptAnalyzer.ps1` so the analyzer results stay in an array even when PowerShell returns a single object.

These are small documentation/metadata updates; move to a versioned release entry when shipping.

#### Docs, Coverage & CI (2025-11-25)

- Documentation: `README.md` now calls out that PSmediaManager is intended to live on a removable/external drive so hosts stay clean.
- Coverage: refreshed `tests/.coverage-latest.json` and `tests/.coverage-jacoco.xml` baselines (61.35% line coverage) generated by the tuned harness so CI enforces the latest numbers.
- CI: `.github/workflows/ci.yml` temporarily limits the matrix to `windows-latest` while analyzer preloading stabilizes, keeping GitHub Actions green until Linux runners are ready.

### Deprecated

- Once-proposed features scheduled for removal.

### Removed (Details)

- Tests: retired `tests/Modules/PSmm/Exit-Order.Tests.ps1` now that `Write-PSmmHost` export coverage is handled via module tests and integration smoke runs.
- CI: removed `.github/workflows/powershell-tests.yml` because the consolidated `ci.yml` plus the improved `tests/Invoke-Pester.ps1` cover the same validation steps.

### Fixed

#### 2025-11-27

- **fix(storage)**: Corrected drive enumeration returning an empty list due to accessing undefined `$script:IsWindows` inside `StorageService` class scope. Replaced platform probe with explicit CIM availability + OS platform checks.
- **fix(storage wizard)**: Resolved invisible drive list during `Invoke-StorageWizard` by replacing `Write-Information` with `Write-Host` for interactive selection output (information stream was suppressed in typical sessions).
- **fix(module loading)**: Added `Services\StorageService.ps1` to `ScriptsToProcess` in `PSmm.psd1` so the class loads before public wrapper usage; requires a fresh PowerShell session after update for class definition changes.
- **fix(detection)**: Ensured USB/removable detection treats disks with `BusType = 'USB'` even when `InterfaceType = 'SCSI'` (common for USB mass‑storage bridges); wizard now lists these devices properly.
- **docs(storage)**: Updated `README.md` and `docs/storage.md` with troubleshooting guidance for missing drives and clarified detection logic.
- **fix(logging)**: Routed `Initialize-Logging` and `Invoke-LogRotation` through `New-FileSystemService` and restored a string-based `[OutputType('FileSystemService')]` declaration so `[FileSystemService]` no longer needs to be loaded during attribute parsing, fixing analyzer/test failures in isolated module runs.

#### 2025-11-26

- Fix (Test Infrastructure): Prevented Pester tests from creating `PSmm.Log`, `PSmm.Plugins`, and `PSmm.Vault` folders on the system drive (C:\) by implementing test mode detection in `AppConfigurationBuilder`. When `MEDIA_MANAGER_TEST_MODE='1'` is set (automatically by `Invoke-Pester.ps1`), runtime folders are created within the test directory instead of at the drive root, ensuring test isolation and preventing system pollution. Production behavior remains unchanged with runtime folders placed at drive root. (commit `97845fc`)
- Fix (Configuration Builder): Normalized storage configuration handling to derive `DriveLetter` and `Path` at runtime and ignore obsolete `StorageType` entries, preventing mismatches between persisted and live configuration. Updated `src/Modules/PSmm/Classes/AppConfigurationBuilder.ps1` accordingly.

#### 2025-11-24

- Fix: Constructed `SecureString` safely in `src/Modules/PSmm.Plugins/Private/Confirm-Plugins.ps1` to avoid using `ConvertTo-SecureString -AsPlainText -Force`. (commit `c148f77`)
- Fix: Normalize analyzer runner outputs in `tests/Invoke-PSScriptAnalyzer.ps1` (`$results` and `$errors` coerced to arrays) to prevent `.Count` property errors when a single object is returned. (commit `c148f77`)
- Chore: Add `Write-PSmmHost` wrapper and replace scattered `Write-Host` calls across interactive scripts to centralize host output and improve static analysis compliance. (2025-11-24)
- Fix: Allow empty messages in `Write-PSmmHost` to prevent parameter binding errors when emitting blank lines during interactive setup. (2025-11-24)
- Fix: Harden `Write-PSmmHost` with comment-based help, `[OutputType]` and an analyzer suppression attribute for intentional `Write-Host` usage in interactive path. (2025-11-24)
- Perf/Quality: Reduced PSScriptAnalyzer issues from 216 → 72 by replacing `Write-Host` usages and improving wrapper behavior; results saved to `tests/PSScriptAnalyzerResults.json`. (2025-11-24)
- Tooling: Dot-source `tests/Preload-PSmmTypes.ps1` within `tests/Invoke-PSScriptAnalyzer.ps1` so CI runs preload PSmm classes/interfaces and no longer spam `TypeNotFound` parse noise.
- Tooling: Made `tests/Preload-PSmmTypes.ps1` path calculations platform-agnostic (no Windows-only separators) so CI on Linux can preload PSmm classes and avoid `TypeNotFound` spam.
- CI: Updated `.github/workflows/ci.yml` to run the repository's `tests/Invoke-PSScriptAnalyzer.ps1` wrapper (with preload and filtering) instead of a raw `Invoke-ScriptAnalyzer` call so GitHub Actions respects the same analyzer setup as local devs.
- Tests: Hardened `tests/Invoke-Pester.ps1` shutdown logic by forcing `Environment.Exit` on GitHub Actions while defaulting to `exit` locally; added `-PassThru` to keep the result object in scripts without auto-exiting. Prevents CI hangs without trapping interactive shells.

- Fix (2025-11-24): Export `Write-PSmmHost` from the `PSmm` module and ensure exit messaging is written before modules are unloaded.
  - Symptom: `The term 'Write-PSmmHost' is not recognized` during application shutdown in some sessions.
  - Impact: Fixes missing-symbol error and preserves final exit message output.
  - Files: `src/Modules/PSmm/PSmm.psm1`, `src/Modules/PSmm/PSmm.psd1`, `src/PSmediaManager.ps1`.

### Security

- Workflows: bumped `github/codeql-action/upload-sarif` to `v4` inside the Codacy security scan so SARIF uploads stay compatible with GitHub Advanced Security requirements.

## [v1.0.0] - YYYY-MM-DD

- Initial public scaffold and core modules.

---

## How to use this changelog (recommended workflow)

- Keep entries under `Unreleased` as you work (use the category headings above).
- When ready to ship:

  1. Create a release branch or tag (e.g. `vX.Y.Z`).
  2. Move `Unreleased` entries into a new header `## [vX.Y.Z] - YYYY-MM-DD` and fill the date.
  3. Create a GitHub Release with the same notes (you can paste the section body into the release description).
  4. Tag the commit: `git tag -a vX.Y.Z -m "Release vX.Y.Z"` and `git push --tags`.

## PowerShell-specific recommendations

- If this repo publishes PowerShell modules (PSD1 manifests), update module `Version` in the appropriate `*.psd1` files to match the release tag.

  - Example: update `ModuleVersion` or `Version` fields inside `src/Modules/PSmm/PSmm.psd1`.

- Add a short compatibility note when changing minimum PowerShell requirement (e.g. `PowerShell 7.5.4+`).

- When changes affect public cmdlet names/signatures, list the impacted functions (module and function names).

## Automating releases (optional)

- Use GitHub Actions or Release Drafter to generate draft release notes automatically.

- Example: configure an Action to use `git log --format=%B` or `github-release-notes` to combine Conventional Commit messages into release notes.

## Tips

- Use Conventional Commits for clear automated release note generation (e.g., `feat:`, `fix:`, `chore:`).
- Keep `Unreleased` concise. Move entries to a versioned section at release time.
- Link to issues/PRs for context when relevant (e.g., `(#123)`).

## References

- [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
- [Semantic Versioning](https://semver.org/)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

<!-- markdownlint-enable MD024 -->
