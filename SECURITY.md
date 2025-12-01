# Security Policy

## Supported Versions

Version `1.0.0` is the current focus. Older revisions should be updated to latest `main` before reporting issues to ensure fixes are not already applied.

## Reporting a Vulnerability

1. **Do not** open a public issue with exploit details.
2. Use GitHub's *Report a vulnerability* flow (Security ➜ Advisories) so maintainers and CODEOWNERS receive a private notification. If that is unavailable, email the maintainer listed in CODEOWNERS via their GitHub profile.
3. Provide environment details (PowerShell version, OS) and affected functions.
4. Include a safe configuration export (via `Export-SafeConfiguration`) and any relevant logs with secrets redacted.

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

## Upstream Base Image / WSL Package CVEs

The vulnerability scan surfaced CVE entries originating from the underlying WSL/Ubuntu base packages, not from project source code:

- `CVE-2024-56406` (curl / library dependency chain)
- `CVE-2025-40909` (perl threads working directory race)
- `CVE-2025-45582` (tar path traversal)

### Suppression Rationale

These components are OS-level packages in the WSL environment used for scanning and are not bundled, redistributed, or directly invoked by PSmediaManager functions. The application logic (PowerShell modules, scripts) does not execute `tar` or rely on Perl threads. Exposure surface is limited to local developer environment; exploitation would require separate privilege footholds.

### Policy

1. CVEs above are temporarily suppressed via `.trivyignore` to reduce false-positive noise while focusing on application layer issues.
2. Review suppression list every 30 days or upon Ubuntu base image updates.
3. Remove an entry once the upstream package version is patched in the base image you use for scanning.
4. Never suppress project-internal dependency CVEs (only upstream OS packages with no direct code path).

### Developer Actions

Run periodic update of WSL base image: `wsl --shutdown` then update the distribution (`sudo apt update && sudo apt upgrade -y`) inside the WSL environment used for scans. After updates, re-run the Codacy/Trivy analysis and prune resolved CVEs from `.trivyignore`.

### Audit Trail

Each suppression requires justification in this section. Adding new IDs without context is prohibited.

If future tooling integrates container scanning, ensure multi-stage builds pin minimal base layers and re-assess all ignores.

## Disclosure

Public disclosure follows release of a patched version unless coordinated otherwise.
