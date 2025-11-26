# PSmediaManager

Portable, modular PowerShell-based media management application. PSmediaManager orchestrates external tooling (digiKam, FFmpeg, ImageMagick, MariaDB, ExifTool, KeePassXC, MKVToolNix, Git utilities) via a plugin layer while providing a safe configuration system, structured logging, project management, and an interactive console UI.

[![CI](https://github.com/mosh666/PSmediaManager/actions/workflows/ci.yml/badge.svg)](https://github.com/mosh666/PSmediaManager/actions/workflows/ci.yml)
[![Coverage Artifacts](https://img.shields.io/badge/coverage-uploaded--via--Pester-blue)](https://github.com/mosh666/PSmediaManager/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> Status: Early 1.0.0 foundation release. APIs and structure may evolve.

## Table of Contents

1. [Features](#features)
2. [Quick Start](#quick-start)
3. [Requirements](#requirements)
4. [Installation & Portability](#installation--portability)
5. [Usage](#usage)
6. [Configuration System](#configuration-system)
7. [Project Management](#project-management)
8. [Plugin Orchestration](#plugin-orchestration)
9. [Logging](#logging)
10. [User Interface](#user-interface)
11. [Modules Overview](#modules-overview)
12. [Testing](#testing)
13. [Development](#development)
14. [Security](#security)
15. [Contributing](#contributing)
16. [Roadmap](#roadmap)
17. [FAQ](#faq)
18. [Changelog](#changelog)
19. [License](#license)

## Features

- Modular architecture (`PSmm`, `PSmm.Logging`, `PSmm.Plugins`, `PSmm.Projects`, `PSmm.UI`).
- Portable – run directly from a cloned repository; avoids machine-global mutation.
- Plugin acquisition with explicit pinned asset patterns (GitHub / direct URLs).
- Safe configuration exporting with redaction & structured formatting.
- Structured logging (console + file, rotation support) built on PSLogs.
- Project isolation: discrete media project directories & tracked registries.
- Interactive ANSI-rich console UI with multi-option prompts.
- External tool coordination (digiKam, MariaDB, FFmpeg, ImageMagick, etc.).
- Secret management powered by KeePassXC CLI helpers.
- Pester test suite & coverage baseline scripts.
- PowerShell 7.5.4+ only (Core, cross-platform focus).

## Quick Start

```pwsh
# Clone
git clone https://github.com/mosh666/PSmediaManager.git
cd PSmediaManager

# Launch (portable, no profile side-effects)
pwsh -NoLogo -NoProfile -File .\Start-PSmediaManager.ps1

# Or from an existing PowerShell session
./Start-PSmediaManager.ps1
```

On first run PSmediaManager will initialize required directories and you can begin confirming plugins or creating projects via UI menus or exported functions.

## Requirements

Minimum PowerShell: 7.5.4 (see `src/Config/PSmm/PSmm.Requirements.psd1`).

Required Gallery Modules (installed on-demand or pre-install manually):

```pwsh
Install-Module 7Zip4PowerShell,Pester,PSLogs,PSScriptAnalyzer,PSScriptTools -Scope CurrentUser -Repository PSGallery
```

External Tools Managed via Plugins (examples):

- 7-Zip (GitHub `ip7z/7zip` assets)
- PortableGit / GitVersion / Git LFS
- ExifTool, FFmpeg, ImageMagick
- KeePassXC CLI
- MKVToolNix
- MariaDB
- digiKam

Each plugin definition includes: source type (GitHub/Url), asset pattern for reliable version resolution, command path, and executable name. See `PSmm.Requirements.psd1` for the authoritative list.

## Installation & Portability

The repository is designed for side-by-side usage without system-level installation:

- **External-drive first:** PSmediaManager is intended to live on a removable/external drive so it can travel with your media projects. Clone or extract the repo directly onto the target portable volume and run it from there to keep host machines clean.
- No mandatory `$env:PATH` mutation – tools are invoked via resolved explicit paths.
- All writable state lives under a designated root (projects, logs, temp, config snapshots).
- To "move" PSmediaManager: copy the entire folder to another location or machine; ensure external tool archives are re-confirmed if paths change.

Optional: Add a wrapper script or shortcut pointing to `Start-PSmediaManager.ps1` for convenience.

## Usage

Invoke core functionality via exported functions from the `PSmm` module or UI:

```pwsh
Import-Module ./src/Modules/PSmm/PSmm.psd1
Invoke-PSmm                    # Core bootstrap
Invoke-PSmmUI                  # Interactive menu system
New-PSmmProject -Name "MyMedia" -Root "D:/Media" # Create project
Select-PSmmProject -Name "MyMedia"               # Switch active project
Confirm-Plugins                # Validate / acquire external tooling
Export-SafeConfiguration -Path ./config-safe.ps1 # Redacted config export
Write-PSmmLog -Level Info -Message 'Started session'
```

See module manifests for full public function lists.

### Recent Fixes

- Exported `Write-PSmmHost` from the `PSmm` module and ensured exit messaging runs before modules are unloaded.
	- Symptom: `The term 'Write-PSmmHost' is not recognized` could occur during shutdown.
	- Files: `src/Modules/PSmm/PSmm.psm1`, `src/Modules/PSmm/PSmm.psd1`, `src/PSmediaManager.ps1`.

## Configuration System

Built around `AppConfiguration` and `AppConfigurationBuilder` classes:

- Allows layered configuration (defaults → environment → user overrides).
- Redaction & safe serialization via `Export-SafeConfiguration` for sharing.
- Supports quoting, scalar formatting, cyclic reference detection (see tests).

Best Practices:

- Keep secrets only in KeePassXC-managed vault; reference via secret retrieval functions (`Get-SystemSecret`).
- Export sanitized snapshots before filing issues to avoid leaking sensitive values.

## Project Management

The `PSmm.Projects` module provides isolated media project tracking:

```pwsh
New-PSmmProject -Name "Archive2025" -Root "E:/Archive2025"
Get-PSmmProjects
Select-PSmmProject -Name "Archive2025"
Clear-PSmmProjectRegistry   # Maintenance / reset
```

Projects encapsulate directories, database initialization (MariaDB/digiKam coordination), and plugin configuration alignment.

## Plugin Orchestration

`PSmm.Plugins` centralizes acquisition & verification:

- Deterministic asset selection using regex-like `AssetPattern` strings.
- Version discovery (e.g. remote `VersionUrl` endpoints).
- Start/Stop helpers for digiKam integration.
- Port management functions for local services.

Workflow:

```pwsh
Confirm-Plugins          # Acquire/mirror required external tools
Install-KeePassXC        # Example targeted installer
Start-PSmmdigiKam        # Launch digiKam with managed paths
Stop-PSmmdigiKam         # Graceful stop
```

## Logging

`PSmm.Logging` supplies structured logging built on PSLogs:

- `Initialize-Logging` sets sinks (console, rotating file) & levels.
- Context enrichment via `Set-LogContext`.
- `Write-PSmmLog -Level Debug|Info|Warn|Error` unified entrypoint.
- Rotation logic: `Invoke-LogRotation` (run in maintenance or scheduled).

Example:

```pwsh
Import-Module ./src/Modules/PSmm.Logging/PSmm.Logging.psd1
Initialize-Logging -Root "./logs" -Level Info
Set-LogContext -Name Session -Value (Get-Date -Format o)
Write-PSmmLog -Level Info -Message 'Initialization complete'
```

## User Interface

`PSmm.UI` enriches the console experience:

- Multi-option prompts & input validation (`Invoke-MultiOptionPrompt`).
- Colorized, accessible output formatting.
- `Invoke-PSmmUI` acts as the main interactive shell dispatcher.

## Modules Overview

| Module | Purpose | Key Public Functions |
|--------|---------|----------------------|
| PSmm | Core bootstrap, storage, secrets, configuration | `Invoke-PSmm`, `Confirm-Storage`, `Export-SafeConfiguration`, `Get-SystemSecret` |
| PSmm.Logging | Structured logging | `Initialize-Logging`, `Write-PSmmLog` |
| PSmm.Plugins | External tool lifecycle | `Confirm-Plugins`, `Install-KeePassXC`, `Start-PSmmdigiKam` |
| PSmm.Projects | Project isolation | `New-PSmmProject`, `Select-PSmmProject` |
| PSmm.UI | Interactive console UI | `Invoke-PSmmUI`, `Invoke-MultiOptionPrompt` |

## Testing

Pester suite resides under `tests/Modules/...` with helpers in `tests/Support`.

Run the repository harness (mirrors CI) to execute analyzer + tests with coverage:

```pwsh
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./tests/Invoke-Pester.ps1 -WithPSScriptAnalyzer -CodeCoverage -Quiet
```

Key behavior:

- Wraps `Invoke-PSScriptAnalyzer.ps1`, which preloads PSmm types so `TypeNotFound` noise is filtered before enforcing errors.
- Persists results to `tests/PSScriptAnalyzerResults.json`, `tests/TestResults.xml`, `.coverage-jacoco.xml`, and `.coverage-latest.json` (currently 61.35% line coverage enforced by baseline).
- Supports `-PassThru` for tooling scenarios and sets the exit code the same way GitHub Actions does (Environment.Exit in CI contexts).
- **Test Isolation**: Automatically sets `MEDIA_MANAGER_TEST_MODE='1'` to ensure runtime folders (`PSmm.Log`, `PSmm.Plugins`, `PSmm.Vault`) are created within test directories rather than on the system drive, preventing test pollution and enabling parallel test execution.

After legitimate coverage improvements, refresh the baseline to keep CI green:

```pwsh
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./tests/Update-CoverageBaseline.ps1
```

Guidelines:

- Prefer focused unit tests per exported function.
- Add regression tests when fixing bugs (especially config/serialization edge cases).
- Keep mocks isolated in `tests/Support` scripts.
- Use `-PassThru` during local authoring when you need the raw Pester result without exiting your shell.
- Tests run in isolated environments with automatic cleanup of temporary directories.

Static Analysis (standalone run with repo settings):

```pwsh
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./tests/Invoke-PSScriptAnalyzer.ps1 -TargetPath ./src -Verbose
```

## Development

Recommended workflow:

1. Use the GitHub issue templates to propose features/bugs before starting work.
2. Create a feature branch: `git switch -c feature/<short-desc>`.
3. Add or adjust module functions (use approved PowerShell verbs; prefer `Set-StrictMode -Version Latest`).
4. Write/extend Pester coverage alongside the change.
5. Run `./tests/Invoke-Pester.ps1 -WithPSScriptAnalyzer -CodeCoverage` (same command CI executes) plus any targeted analyzer runs.
6. Update README / docs for new public functions, configuration keys, or workflows.
7. Use Conventional Commits for history clarity: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `ci:`, `chore:`.
8. Submit PRs via the provided template and ensure the CODEOWNERS reviewers auto-requested by GitHub are satisfied.

Coding Practices:

- Strict mode everywhere (`Set-StrictMode -Version Latest`).
- Avoid global state; pass configuration objects explicitly.
- Use classes for complex services (see `Classes/Services`).
- Keep manifests (`*.psd1`) curated: only export intentional public surface.

Continuous integration:

- `.github/workflows/ci.yml` installs PowerShell 7.5.4, the required PSGallery modules, runs `tests/Invoke-PSScriptAnalyzer.ps1`, then `tests/Invoke-Pester.ps1 -CodeCoverage -Quiet`, and uploads analyzer/test/coverage artifacts.
- `.github/workflows/codacy.yml` runs Codacy Analysis CLI and uploads SARIF results via `github/codeql-action/upload-sarif@v4` so findings appear in GitHub code scanning alongside CodeQL results.
- Coverage baselines are enforced via `tests/.coverage-baseline.json`; commits that lower coverage fail CI until baseline is updated intentionally.

## Security

- Secrets stored via KeePassXC CLI integration (not plain text).
- Redaction utilities for configuration exports.
- No silent elevation or registry writes outside project registry scope.
- Automated scanning: CodeQL (via GitHub Advanced Security) and Codacy SARIF uploads run on every push/PR to `main` and `dev` plus a weekly schedule.
- Report vulnerabilities privately using the GitHub Security Advisories form (preferred) or follow the steps in [SECURITY.md](SECURITY.md) for a sanitized disclosure that includes an `Export-SafeConfiguration` snapshot.

## Contributing

See `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` for detailed guidelines. Highlights:

- Discuss large changes first via issue or GitHub Discussion; use the provided templates so maintainers have reproducible context.
- Ensure analyzer + tests pass locally using the same harness CI consumes; include docs updates for any public surface change.
- Maintain modular boundaries (do not couple UI logic into core services) and keep PowerShell best practices (approved verbs, comment-based help for public functions).
- By contributing you agree to follow the Code of Conduct and accept that CODEOWNERS may request additional changes before merge.

## Roadmap

Planned enhancements (subject to change):

- Re-enable the Linux matrix in CI once analyzer preloading stabilizes across platforms.
- Plugin caching strategy & hash verification.
- Optional PowerShell Gallery packaging of core modules.
- Extended UI navigation (search/filter projects).
- Improved secret lifecycle & rotation helpers.
- Performance metrics logging subsystem.

## FAQ

**Q: Why portable?** To allow side-by-side versions, minimal host mutation, and safe copying across systems.

**Q: Can I install globally?** You can import modules from any location, but global installation is intentionally optional.

**Q: Linux/macOS support?** Core PowerShell modules should function cross-platform; some plugins reference Windows-specific assets. Cross-platform asset patterns are a roadmap item.

**Q: How do I add a new plugin?** Extend `PSmm.Requirements.psd1` with a new entry, implement acquisition logic or leverage existing patterns, add tests, update docs.

---

If you find issues or have feature ideas, please open an issue. Feedback accelerates maturity.

## Changelog

See the full changelog and release notes in the repository root: [CHANGELOG.md](./CHANGELOG.md)

## License

Released under the [MIT License](LICENSE). Contributions are accepted under the same terms.
