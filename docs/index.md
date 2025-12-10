# PSmediaManager Documentation

## Recent Updates

- **v0.2.0 Released** (2025-12-10): Major architectural refactoring with ServiceContainer dependency injection
  - Formal `ServiceContainer` class for singleton lifetime management
  - Breaking API changes: all public functions now require `-ServiceContainer` parameter
  - Fixed MariaDB installer null reference errors
  - Fixed plugin confirmation PATH registration issues
  - Improved digiKam installer robustness
  - Updated all tests to use ServiceContainer pattern
- **v0.1.3 Released** (2025-12-09): Code quality improvements and dependency reduction
  - Removed 7Zip4PowerShell PowerShell module dependency
  - Achieved zero PSScriptAnalyzer violations across entire codebase
- **v0.1.2 Released** (2025-12-09): Manifest-based plugin system with project-level overrides
  - New `PSmm.Plugins.psd1` manifest with `Mandatory`/`Enabled` flags
  - Project plugin manifests auto-loaded during project selection
- **v0.1.1 Released** (2025-12-08): Documentation improvements
  - Added comprehensive troubleshooting guide
  - Created complete public API reference with 35+ exported functions
- **v0.1.0 Released** (2025-12-08): First tagged release
  - Complete dynamic versioning system using GitVersion
  - Coverage baseline at 70.95% with comprehensive test suite

Welcome to the PSmediaManager documentation portal. This site expands on the high-level README by providing deep dives into architecture, configuration, development workflow, and module responsibilities.

## Sections

- [Installation](install.md)
- [Configuration](configuration.md)
- [Versioning](versioning.md) – Dynamic versioning with GitVersion
- [Modules](modules.md)
- [Development](development.md)
- [Architecture](architecture.md)
- [Deployment](deployment.md) – Container deployment, security hardening, CI/CD integration
- [Storage](storage.md) – Storage drive management and configuration
- [API Reference](api.md) – Complete public API documentation
- [Troubleshooting](troubleshooting.md) – Common issues and solutions

## Design Goals

- Portable: zero mandatory global installs; side-by-side versioning.
- Deterministic: asset patterns & explicit paths with opt-in PATH registration (RegisterToPath adds User + Process entries, cleaned unless `-Dev`).
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
