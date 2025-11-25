# Installation & Portability

## Prerequisites

- PowerShell 7.5.4+ (Core). Confirm via:

```pwsh
$PSVersionTable.PSVersion
```

- Git (portable Git asset optional – will be managed by plugins if absent).
- Network access to GitHub / specified asset URLs for initial acquisition.

## Clone Repository

```pwsh
git clone https://github.com/mosh666/PSmediaManager.git
cd PSmediaManager
```

## First Launch (Portable Mode)

```pwsh
pwsh -NoProfile -File ./Start-PSmediaManager.ps1
```

This script orchestrates module loading without mutating your global profile.

## Required PowerShell Gallery Modules

Pre-install to speed up first run (optional):

```pwsh
Install-Module 7Zip4PowerShell,Pester,PSLogs,PSScriptAnalyzer,PSScriptTools -Scope CurrentUser -Repository PSGallery
```

## Portable Philosophy

| Aspect | Approach |
|--------|---------|
| External tools | Stored in managed paths, invoked via explicit absolute paths |
| Environment | Minimal transient changes; avoids persisting system-wide PATH |
| State | Centralized under a root (projects, logs, temp, config snapshots) |
| Migration | Copy folder → re-confirm plugins → continue operation |

## Updating

```pwsh
git pull origin main
```

Re-run `Confirm-Plugins` for any newly added external tool definitions.

## Post-Install Validation

Before opening a pull request or filing an issue, run the same harness that GitHub Actions executes to confirm analyzers and tests succeed locally:

```pwsh
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./tests/Invoke-Pester.ps1 -WithPSScriptAnalyzer -CodeCoverage -Quiet
```

The script preloads PSmm classes, enforces the coverage baseline stored in `tests/.coverage-baseline.json`, and writes analyzer/test artifacts under `tests/`. Matching CI behavior locally speeds up reviews and reduces failed checks.

## Optional: Shortcut Wrapper

Create a `.ps1` or OS shortcut that runs `Start-PSmediaManager.ps1` for rapid access.

## Uninstall / Removal

Simply delete the cloned directory. No residual global artifacts remain (unless you manually installed modules globally).

## Troubleshooting

- Missing module errors: ensure required gallery modules are installed.
- Asset acquisition failures: verify internet connectivity and that GitHub/URL endpoints are reachable.
- Permission issues on Windows: avoid protected locations (run from a user-writable directory).

Proceed to [Configuration](configuration.md) to customize behavior.
