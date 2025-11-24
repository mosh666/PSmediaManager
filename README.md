# PSmediaManager

Portable, modular PowerShell-based media management application. PSmediaManager orchestrates external tooling (digiKam, FFmpeg, ImageMagick, MariaDB, ExifTool, KeePassXC, MKVToolNix, Git utilities) via a plugin layer while providing a safe configuration system, structured logging, project management, and an interactive console UI.

[![Codacy Badge](https://api.codacy.com/project/badge/Grade/a41b0b4adba94c519e9c8bbfcffd5236)](https://app.codacy.com/gh/mosh666/PSmediaManager?utm_source=github.com&utm_medium=referral&utm_content=mosh666/PSmediaManager&utm_campaign=Badge_Grade)
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

Run all tests:

```pwsh
./tests/Invoke-Pester.ps1
```

Update coverage baseline (post validated changes):

```pwsh
./tests/Update-CoverageBaseline.ps1
```

Guidelines:

- Prefer focused unit tests per exported function.
- Add regression tests when fixing bugs (especially config/serialization edge cases).
- Keep mocks isolated in `tests/Support` scripts.

Static Analysis:

```pwsh
Invoke-ScriptAnalyzer -Path ./src -Recurse
```

## Development

Recommended workflow:

1. Create a feature branch: `git switch -c feature/<short-desc>`.
2. Add or adjust module functions (use approved PowerShell verbs).
3. Add Pester tests first (TDD where practical).
4. Run `Invoke-ScriptAnalyzer` & tests locally.
5. Update README / docs for new public functions.
6. Use Conventional Commits for history clarity: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`.
7. Submit PR targeting `main`.

Coding Practices:

- Strict mode everywhere (`Set-StrictMode -Version Latest`).
- Avoid global state; pass configuration objects explicitly.
- Use classes for complex services (see `Classes/Services`).
- Keep manifests (`*.psd1`) curated: only export intentional public surface.

Potential CI (GitHub Actions) suggestions:

- Lint / analyze: PSScriptAnalyzer.
- Unit tests: Pester with coverage artifact upload.
- Security scanning: script / secret scanning.
- Release tagging: auto update module version & release notes.

## Security

- Secrets stored via KeePassXC CLI integration (not plain text).
- Redaction utilities for configuration exports.
- No silent elevation or registry writes outside project registry scope.
- Report vulnerabilities via ISSUE with label `security` or follow `SECURITY.md` guidance.

## Contributing

See `CONTRIBUTING.md` for detailed guidelines. Highlights:

- Discuss large changes first via issue.
- Ensure tests + analyzer pass; include docs updates.
- Maintain modular boundaries (do not couple UI logic into core services).

## Roadmap

Planned enhancements (subject to change):

- Add GitHub Actions CI pipeline (lint, test, artifact packaging).
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
