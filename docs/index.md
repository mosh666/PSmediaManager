# PSmediaManager Documentation

Welcome to the PSmediaManager documentation portal. This site expands on the high-level README by providing deep dives into architecture, configuration, development workflow, and module responsibilities.

## Sections

- [Installation](install.md)
- [Configuration](configuration.md)
- [Modules](modules.md)
- [Development](development.md)
- [Architecture](architecture.md)

## Design Goals

- Portable: zero mandatory global installs; side-by-side versioning.
- Deterministic: asset patterns & explicit paths (no PATH pollution).
- Inspectable: configuration export & redaction tooling.
- Testable: comprehensive Pester coverage for core behaviors.
- Extensible: plugin shell for external tooling & future integrations.

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
