# Contributing to PSmediaManager

Thank you for considering a contribution! This guide outlines how to propose changes effectively. All contributors are expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ground Rules

- Keep changes focused; avoid unrelated refactors.
- Add tests for all new public functions and bug fixes.
- Maintain portability (no hard-coded machine-specific paths).
- Avoid introducing global state or modifying user profiles silently.

## Workflow

1. Search existing issues/discussions to avoid duplicates (use the GitHub templates so maintainers get reproducible context).
2. Open a descriptive issue if feature/bug not tracked.
3. Create a branch: `git switch -c feature/<short-desc>`.
4. Implement changes with tests & docs.
5. Run: `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./tests/Invoke-Pester.ps1 -WithPSScriptAnalyzer -CodeCoverage -Quiet` (matches CI) before pushing.
6. Submit PR referencing issue number and summarizing changes.

## Commit Convention

Use Conventional Commits for clarity:

`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `perf:`, `chore:`.

## Testing Expectations

- High-risk logic (configuration export, secret handling, plugin acquisition) must have coverage.
- Use Support helpers for consistent mocking.
- Add regression tests for every fixed bug.
- Update `tests/.coverage-baseline.json` via `./tests/Update-CoverageBaseline.ps1` only after demonstrable improvements so the enforced baseline in CI stays accurate.

## PowerShell Practices

- Use approved verbs.
- Prefer structured objects over formatted strings until final output.
- Guard external calls (process/network) with error handling.
- Emit interactive text via `Write-PSmmHost` so analyzer suppressions and shutdown messaging remain centralized.

## Adding Plugins

1. Extend `PSmm.Requirements.psd1` with new entry.
2. Include reliable `AssetPattern`.
3. Write tests for pattern resolution and command path derivation.
4. Update docs.

## Code Review Focus

- Clarity of public API and adherence to approved PowerShell verbs.
- Absence of side effects (no silent environment pollution).
- Test completeness plus coverage expectations.
- Security (no plaintext secrets, proper redaction, adherence to SECURITY.md reporting guidance).
- Documentation updates accompanying public-facing changes.

## Releasing (Maintainers)

- Bump module versions in manifests when public surface changes.
- Update release notes.
- Tag & draft release.

## Questions / Security Reports

- Use the `question` issue template or GitHub Discussions for general queries.
- Report vulnerabilities privately via GitHub Security Advisories (preferred) or follow [SECURITY.md](SECURITY.md) for sanitized disclosures that include `Export-SafeConfiguration` snapshots.

---

Your contributions help shape a reliable, extensible media management ecosystem. Thank you!
