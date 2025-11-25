# Configuration

PSmediaManager employs layered configuration objects and safe export capabilities for debugging and sharing.

## Components

- `AppConfiguration`: runtime effective configuration instance.
- `AppConfigurationBuilder`: fluent builder aggregating sources.
- Secret abstraction: retrieval via KeePassXC CLI wrappers (not in plain text config).

## Layering Model

1. Internal defaults.
2. Environment-derived values (paths, OS specifics).
3. User overrides (future: persisted user config file or project-scoped settings).

## Safe Export

Use `Export-SafeConfiguration` to serialize the configuration omitting / redacting secrets or sensitive paths.

```pwsh
Export-SafeConfiguration -Path ./config-safe.ps1
```

Automatic handling includes:

- Scalar quoting for clarity.
- Cyclic reference detection to prevent infinite traversal.
- Redaction for known secret placeholders.

> **GitHub best practice:** When opening a bug report, attach the sanitized output from `Export-SafeConfiguration` so maintainers can reproduce issues without exposing secrets. Security vulnerabilities should follow [SECURITY.md](../SECURITY.md) and leverage GitHub Security Advisories when possible.

## Secrets Management

KeePassXC CLI is leveraged for secure secret storage.

```pwsh
Initialize-SystemVault -Path ./vault/database.kdbx
Save-SystemSecret -Key 'DbPassword' -Value (Read-Host -AsSecureString 'Password')
$secret = Get-SystemSecret -Key 'DbPassword'
```

Guidelines:

- Never embed raw credentials in scripts committed to the repo.
- Use descriptive keys; avoid overloading single secrets with multi-purpose values.

## Environment & Paths

The configuration builder resolves storage roots, plugin directories, and log locations. Ensure target drives have sufficient space for media operations.

## Extending Configuration

When adding new config entries:

1. Define defaults in builder logic.
2. Update safe export filters if sensitive.
3. Add tests covering serialization & redaction.
4. Document new keys here.

## Debugging

```pwsh
$cfg = Invoke-PSmm
$cfg | Format-List *
Export-SafeConfiguration -Path ./debug-config.ps1
```

Compare exported vs runtime for discrepancies.

Return to [Modules](modules.md) for functional surfaces.
