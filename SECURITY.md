# Security Policy

## Supported Versions

Version `1.0.0` is the current focus. Older revisions should be updated to latest `main` before reporting issues to ensure fixes are not already applied.

## Reporting a Vulnerability

1. DO NOT open a public issue with exploit details.
2. Instead, create a minimal reproduction (sanitized) and email the maintainer (contact to be defined) or open a private security advisory if enabled.
3. Provide environment details (PowerShell version, OS) and affected functions.
4. Include a safe configuration export (via `Export-SafeConfiguration`) if relevant.

## Scope

- Secret leakage.
- Privilege escalation.
- Arbitrary code execution via plugin acquisition or path handling.
- Sensitive data in logs.

## Exclusions

- Misconfiguration due to manual edits of generated artifacts.
- Outdated external tooling vulnerabilities (coordinate with upstream maintainers).

## Remediation Process

1. Triage within a reasonable window.
2. Draft patch & add regression tests.
3. Issue security advisory & release tagged fix.

## Hardening Recommendations

- Keep repository on trusted storage.
- Regularly rotate secrets in KeePassXC vault.
- Run plugins from non-system drive when possible.

## Disclosure

Public disclosure follows release of a patched version unless coordinated otherwise.
