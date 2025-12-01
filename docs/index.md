# PSmediaManager Documentation

Welcome to the PSmediaManager documentation portal. This site expands on the high-level README by providing deep dives into architecture, configuration, development workflow, and module responsibilities.

## Sections

- [Installation](install.md)
- [Configuration](configuration.md)
- [Modules](modules.md)
- [Development](development.md)
- [Architecture](architecture.md)

## What’s New (0.9.0)

- Added `Get-PSmmHealth` for quick environment diagnostics (PowerShell version, modules, plugins, storage, vault). Supports `-Format` output.
- Introduced early bootstrap services (`src/Core/BootstrapServices.ps1`) so core path/filesystem/environment/process helpers are available before module import.
- Added Codacy and markdown lint configuration files (`.codacy.yml`, `.markdownlint.yml`) and documented upstream base image CVE suppressions in `.trivyignore`.

## Design Goals

- Portable: zero mandatory global installs; side-by-side versioning.
- Deterministic: asset patterns & explicit paths (no PATH pollution).
- Inspectable: configuration export & redaction tooling.
- Testable: comprehensive Pester coverage for core behaviors.
- Extensible: plugin shell for external tooling & future integrations.
- Secure: repository-first workflows with automated analyzers, SARIF uploads, and enforced coverage baselines.

## Quality & Security Automation

- `tests/Invoke-Pester.ps1 -WithPSScriptAnalyzer -CodeCoverage` mirrors the GitHub Actions job, enforces the coverage baseline, and emits artifacts consumed by release tooling.
- `tests/Invoke-PSScriptAnalyzer.ps1` preloads PSmm types to keep PSScriptAnalyzer deterministic across Windows/Linux runners.
- `.github/workflows/ci.yml` runs analyzer + tests on every push/PR to `main` and `dev`.
- `.github/workflows/codacy.yml` uploads Codacy SARIF findings via `github/codeql-action/upload-sarif@v4`, complementing CodeQL scans in GitHub Advanced Security.

## High-Level Architecture

```text
Start-PSmediaManager.ps1
 └─ Loads core module (PSmm) & supporting modules
    ├─ PSmm (bootstrap, storage, secrets, config builder)
    ├─ PSmm.Logging (structured logging abstraction)
    ├─ PSmm.Plugins (external tool acquisition & lifecycle)
    ├─ PSmm.Projects (per-project registry & initialization)
    └─ PSmm.UI (interactive console interface)
```

Core services (classes) live under `src/Modules/PSmm/Classes/Services` providing file system, process, HTTP, crypto, git, and environment utilities consumed by public functions.

## Getting Help

If something is unclear:

1. Check the relevant module section.
2. Search existing issues.
3. Open a new issue with a minimal reproduction and (optionally) a safe configuration export.

## Next Steps

Begin with [Installation](install.md) to prepare your environment.
