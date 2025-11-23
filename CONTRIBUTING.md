# Contributing to PSmediaManager

Thank you for considering a contribution! This guide outlines how to propose changes effectively.

## Ground Rules

- Keep changes focused; avoid unrelated refactors.
- Add tests for all new public functions and bug fixes.
- Maintain portability (no hard-coded machine-specific paths).
- Avoid introducing global state or modifying user profiles silently.

## Workflow

1. Search existing issues to avoid duplicates.
2. Open a descriptive issue if feature/bug not tracked.
3. Create a branch: `git switch -c feature/<short-desc>`.
4. Implement changes with tests & docs.
5. Run: `Invoke-ScriptAnalyzer` and full Pester suite.
6. Submit PR referencing issue number and summarizing changes.

## Commit Convention

Use Conventional Commits for clarity:

`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `perf:`, `chore:`.

## Testing Expectations

- High-risk logic (configuration export, secret handling, plugin acquisition) must have coverage.
- Use Support helpers for consistent mocking.
- Add regression tests for every fixed bug.

## PowerShell Practices

- Use approved verbs.
- Prefer structured objects over formatted strings until final output.
- Guard external calls (process/network) with error handling.

## Adding Plugins

1. Extend `PSmm.Requirements.psd1` with new entry.
2. Include reliable `AssetPattern`.
3. Write tests for pattern resolution and command path derivation.
4. Update docs.

## Code Review Focus

- Clarity of public API.
- Absence of side effects (no silent environment pollution).
- Test completeness.
- Security (no plaintext secrets, proper redaction).

## Releasing (Maintainers)

- Bump module versions in manifests when public surface changes.
- Update release notes.
- Tag & draft release.

## Questions

Open an issue labelled `question` or start a discussion.

---

Your contributions help shape a reliable, extensible media management ecosystem. Thank you!
