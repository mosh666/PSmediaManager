# Changelog

All notable changes to this project will be documented in this file.

This project adheres to "Keep a Changelog" ([Keep a Changelog](https://keepachangelog.com/en/1.0.0/)) and uses Semantic Versioning ([SemVer](https://semver.org/)).

The format below is designed for clear GitHub Releases and PowerShell module maintenance.

## [Unreleased]

Use this section for in-progress changes that will be included in the next release.

When preparing a release, move the items into a new versioned section and update the date.

### Added

- New features.

### Changed

- Backwards-compatible changes to existing functionality.

#### Current edits (2025-11-24)

- Documentation: added changelog link to `README.md`.
- Repository metadata: tidied `.github/CODEOWNERS` comment line.

- Chore (2025-11-24): Documentation & metadata tidy — added changelog link to `README.md` and cleaned `.github/CODEOWNERS` comment.

- Startup script: recalculated `Start-PSmediaManager.ps1`'s path to `src/PSmediaManager.ps1` with nested `Join-Path` calls to avoid analyzer complaints and edge-case path concatenation errors.
- Tooling: wrapped the `TypeNotFound` filter in `tests/Invoke-PSScriptAnalyzer.ps1` so the analyzer results stay in an array even when PowerShell returns a single object.

These are small documentation/metadata updates; move to a versioned release entry when shipping.

### Deprecated

- Once-proposed features scheduled for removal.

### Removed

- Breaking API removals.
- Tests: retired `tests/Modules/PSmm/Exit-Order.Tests.ps1` now that `Write-PSmmHost` export coverage is handled via module tests and integration smoke runs.

### Fixed

- Bug fixes.

#### 2025-11-24

- Fix: Constructed `SecureString` safely in `src/Modules/PSmm.Plugins/Private/Confirm-Plugins.ps1` to avoid using `ConvertTo-SecureString -AsPlainText -Force`. (commit `c148f77`)
- Fix: Normalize analyzer runner outputs in `tests/Invoke-PSScriptAnalyzer.ps1` (`$results` and `$errors` coerced to arrays) to prevent `.Count` property errors when a single object is returned. (commit `c148f77`)
- Chore: Add `Write-PSmmHost` wrapper and replace scattered `Write-Host` calls across interactive scripts to centralize host output and improve static analysis compliance. (2025-11-24)
- Fix: Allow empty messages in `Write-PSmmHost` to prevent parameter binding errors when emitting blank lines during interactive setup. (2025-11-24)
- Fix: Harden `Write-PSmmHost` with comment-based help, `[OutputType]` and an analyzer suppression attribute for intentional `Write-Host` usage in interactive path. (2025-11-24)
- Perf/Quality: Reduced PSScriptAnalyzer issues from 216 → 72 by replacing `Write-Host` usages and improving wrapper behavior; results saved to `tests/PSScriptAnalyzerResults.json`. (2025-11-24)
- Tooling: Dot-source `tests/Preload-PSmmTypes.ps1` within `tests/Invoke-PSScriptAnalyzer.ps1` so CI runs preload PSmm classes/interfaces and no longer spam `TypeNotFound` parse noise.
- Tooling: Made `tests/Preload-PSmmTypes.ps1` path calculations platform-agnostic (no Windows-only separators) so CI on Linux can preload PSmm classes and avoid `TypeNotFound` spam.
- CI: Updated `.github/workflows/ci.yml` to run the repository's `tests/Invoke-PSScriptAnalyzer.ps1` wrapper (with preload and filtering) instead of a raw `Invoke-ScriptAnalyzer` call so GitHub Actions respects the same analyzer setup as local devs.
- Tests: Hardened `tests/Invoke-Pester.ps1` shutdown logic by forcing `Environment.Exit` on GitHub Actions while defaulting to `exit` locally; added `-PassThru` to keep the result object in scripts without auto-exiting. Prevents CI hangs without trapping interactive shells.

- Fix (2025-11-24): Export `Write-PSmmHost` from the `PSmm` module and ensure exit messaging is written before modules are unloaded.
  - Symptom: `The term 'Write-PSmmHost' is not recognized` during application shutdown in some sessions.
  - Impact: Fixes missing-symbol error and preserves final exit message output.
  - Files: `src/Modules/PSmm/PSmm.psm1`, `src/Modules/PSmm/PSmm.psd1`, `src/PSmediaManager.ps1`.

### Security

- Vulnerability fixes and notes.

## [v1.0.0] - YYYY-MM-DD

- Initial public scaffold and core modules.

---

## How to use this changelog (recommended workflow)

- Keep entries under `Unreleased` as you work (use the category headings above).
- When ready to ship:

  1. Create a release branch or tag (e.g. `vX.Y.Z`).
  2. Move `Unreleased` entries into a new header `## [vX.Y.Z] - YYYY-MM-DD` and fill the date.
  3. Create a GitHub Release with the same notes (you can paste the section body into the release description).
  4. Tag the commit: `git tag -a vX.Y.Z -m "Release vX.Y.Z"` and `git push --tags`.

## PowerShell-specific recommendations

- If this repo publishes PowerShell modules (PSD1 manifests), update module `Version` in the appropriate `*.psd1` files to match the release tag.

  - Example: update `ModuleVersion` or `Version` fields inside `src/Modules/PSmm/PSmm.psd1`.

- Add a short compatibility note when changing minimum PowerShell requirement (e.g. `PowerShell 7.5.4+`).

- When changes affect public cmdlet names/signatures, list the impacted functions (module and function names).

## Automating releases (optional)

- Use GitHub Actions or Release Drafter to generate draft release notes automatically.

- Example: configure an Action to use `git log --format=%B` or `github-release-notes` to combine Conventional Commit messages into release notes.

## Tips

- Use Conventional Commits for clear automated release note generation (e.g., `feat:`, `fix:`, `chore:`).
- Keep `Unreleased` concise. Move entries to a versioned section at release time.
- Link to issues/PRs for context when relevant (e.g., `(#123)`).

## References

- [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
- [Semantic Versioning](https://semver.org/)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
