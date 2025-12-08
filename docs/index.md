# PSmediaManager Documentation

## Recent Updates

- **v0.1.0 Released** (2025-12-08): First tagged release with complete dynamic versioning system
- All modules now derive versions automatically from Git tags via GitVersion
- CI automation and pre-commit hooks ensure version synchronization
- Coverage baseline at 71.02% with comprehensive test suite (414 tests passing)
- 100% PSScriptAnalyzer compliance (0 issues)
- Complete public API documentation with all exported functions

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
