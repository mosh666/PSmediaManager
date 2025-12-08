# Development Guide

## Branching

- `main`: stable, reviewed code intended for releases.
- `dev`: active integration branch where maintainers stage upcoming changes. Base contributor work on `dev` unless coordinating directly on `main`.
- `feature/<short-desc>`: contributor branches forked from `dev` (preferred) or `main` when hotfixes are required.
- Optional `hotfix/<issue-id>` for rapid patches.

## Commits

Use Conventional Commits:

```text
feat: add multi-project validation
fix: resolve cyclic reference detection bug
docs: update configuration guide
test: add coverage for secret redaction
refactor: extract plugin version resolver
```

## Code Style

- Approved verbs (use `Get-Verb` reference).
- PascalCase for function names, camelCase for private variables.
- Avoid one-letter variable names; prefer meaningful semantic names.
- Use `Set-StrictMode -Version Latest` and avoid implicit type conversions.

## Testing

Run the exact harness that CI executes so analyzer, tests, and coverage behave identically:

```pwsh
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./tests/Invoke-Pester.ps1 -WithPSScriptAnalyzer -CodeCoverage -Quiet
```

This script dot-sources `tests/Invoke-PSScriptAnalyzer.ps1`, preloads PSmm classes (preventing `TypeNotFound` noise), enforces the coverage baseline stored in `tests/.coverage-baseline.json`, and captures diagnostics under `tests/.coverage-debug.txt` whenever coverage paths change.

Helper sourcing stays intentional: dot-source the specific support files you need (commonly `tests/Support/TestConfig.ps1`, `tests/Support/Stub-WritePSmmLog.ps1`, or filesystem/test double helpers). `tests/Support/Import-AllTestHelpers.ps1` remains available when you explicitly want every helper plus the PSmm module, but because it carries extra side effects it should only be used when that is desired—most suites keep the imports explicit so `InModuleScope` blocks stay deterministic.

Harness pauses now honor `MEDIA_MANAGER_SKIP_READKEY`. CI and any local automation that sets the variable to `1` before calling `tests/Invoke-Pester.ps1` skip the final `Read-Host` prompts, while the default local invocation still pauses so you can review output.

Add new test files under the matching `tests/Modules/<ModuleName>` path. Keep one `Describe` block per function family and narrow `Context` blocks for edge cases.

### Coverage Strategy

- **Coverage Strategy**: 70.95% baseline (Local typically achieves 71.04%; CI: 70.96% due to environment differences)
  - **Local**: 2,493 commands analyzed, 1,771 executed (71.04%)
  - **CI**: 2,493 commands analyzed, 1,769 executed (70.96%)
- **Baseline Enforcement**: The coverage baseline is stored in `tests/.coverage-baseline.json` and enforced during test runs
- **Test Determinism**: Note that Pester 5.5 does not expose test order randomization controls. Tests generally run consistently, but a small variance (±0.1%) between local and CI environments is expected and monitored.
- **Edge-Case Buffer**: A small gap remains for exception paths and external service fallbacks (e.g., `whoami` failure, DNS resolution errors, NuGet provider installation failures)
- **Rationale**: Testing these paths requires complex mocking infrastructure (external process mocking, system service stubbing) with diminishing return-on-investment. The current strategy prioritizes:
  - Direct path testing (happy path + obvious error cases)
  - Integration testing (multi-function workflows)
  - Deterministic test stability (no flaky mocks)
  - Low maintenance burden

**Updating the Baseline**:

To intentionally adjust the coverage baseline after legitimate improvements:

```pwsh
./tests/Update-CoverageBaseline.ps1
```

To lower the baseline (e.g., after removing coverage exclusions):

```pwsh
./tests/Update-CoverageBaseline.ps1 -Force
```

The script prevents accidental regressions by refusing to lower the baseline without `-Force`.

**Debugging Coverage Variance**:

If you observe differences between local and CI coverage, use the coverage comparison tool:

```pwsh
# Run tests with coverage to generate debug data
./tests/Invoke-Pester.ps1 -CodeCoverage

# Analyze coverage metrics and environment details
./tests/Compare-CoverageDebug.ps1 -Verbose
```

This tool captures:
- Precise coverage percentages (4 decimal places)
- Environment details (OS, PowerShell version, CI context)
- Test execution statistics (passed, failed, skipped, duration)
- Comparison between multiple runs to identify variance sources

Debug data is saved to `.coverage-debug.json` and analysis reports to `.coverage-comparison.txt`. CI automatically runs this analysis and uploads artifacts for inspection.

### Development Mode (-Dev)

When developing PSmediaManager, use the `-Dev` parameter to enable persistent PATH changes:

```pwsh
./Start-PSmediaManager.ps1 -Dev
```

**Development Mode Behavior**:
- Plugin directories are registered to both Process and User PATH scopes
- PATH entries persist after application exit, remaining available in new terminal sessions
- Useful for iterative development where you need plugin tools accessible without re-launching
- Eliminates the need to manually configure PATH for testing plugin integrations

**Normal Mode** (without `-Dev`):
- Plugin directories are registered to Process PATH only
- All PATH modifications are automatically cleaned up on exit
- Ensures zero pollution of the host system's environment
- Recommended for production usage and CI testing

**Testing Implications**:
- Tests always run in isolated mode with temporary PATH modifications
- Test mode (`MEDIA_MANAGER_TEST_MODE=1`) ensures PATH cleanup regardless of `-Dev`
- When testing PATH registration logic, mock the `EnvironmentService` to verify behavior without affecting the host

### Test Environment Isolation

Tests run in an isolated environment with the `MEDIA_MANAGER_TEST_MODE` environment variable set to `'1'`. This ensures:

- Runtime folders (`PSmm.Log`, `PSmm.Plugins`, `PSmm.Vault`) are created within the test directory instead of the system drive root
- Storage configuration files (`PSmm.Storage.psd1`) are written to temporary test directories via Pester's `$TestDrive` instead of actual drive roots
- Test artifacts remain contained and don't pollute the system
- Tests can run in parallel without conflicting with production installations

The `AppConfigurationBuilder` detects test mode and adjusts path resolution accordingly, keeping all test data within temporary directories managed by Pester's `TestDrive`. Test functions use Pester-provided variables (e.g., `$TestDrive`) instead of hardcoded paths to ensure proper isolation.

## Static Analysis

Always prefer the repository helper so the curated settings and preload script are honored:

```pwsh
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./tests/Invoke-PSScriptAnalyzer.ps1 -TargetPath ./src -Verbose
```

Running `./tests/Invoke-Pester.ps1 -WithPSScriptAnalyzer` automatically invokes the helper. Results are normalized to arrays, filtered for intentional `TypeNotFound` entries, and written to `tests/PSScriptAnalyzerResults.json` for triage. Resolve all warnings/errors (errors fail the helper) or document well-justified suppressions in `tests/PSScriptAnalyzer.Settings.psd1`.

## Documentation Updates

- Update `README.md` for new public features or workflows.
- Expand any relevant doc section (`architecture.md`, `modules.md`, `install.md`, etc.).
- If adding configuration keys, update `configuration.md` and note how to export them safely via `Export-SafeConfiguration`.
- Mention CI/security workflow impacts (new jobs, prerequisites) so GitHub users know which checks run.
- When moving internal helpers, prefer `src/Modules/<Module>/Private/` over `Public/`. Example: `Show-InvalidSelection` moved to `PSmm.UI/Private` and is no longer a public surface.
- Tests should source helpers from `tests/Support/TestConfig.ps1` (the consolidated path), not `tests/Helpers/TestConfig.ps1`.
- Bootstrap checks rely on `Confirm-PowerShell` during startup; ensure this file remains available under `PSmm/Private/Bootstrap/Confirm-PowerShell.ps1`.

## Release Process (Proposed)

1. Merge feature branches after review & tests pass.
2. Update `ModuleVersion` in manifests if public surface changed.
3. Tag release: `git tag -a v1.x.y -m "Release notes"`.
4. Draft GitHub Release summarizing changes.
5. (Future) Publish modules to PowerShell Gallery.

## Automation & Quality Gates

- `.github/workflows/ci.yml` (push/PR to `main` and `dev` + manual dispatch) installs PowerShell 7.5.4, trusts PSGallery for dependency installs, runs `tests/Invoke-PSScriptAnalyzer.ps1`, executes `tests/Invoke-Pester.ps1 -CodeCoverage -Quiet`, and uploads analyzer/test/coverage artifacts (`tests/TestResults.xml`, `.coverage-jacoco.xml`, `.coverage-latest.json`, `.coverage-debug.txt`). Failures block merges via required GitHub checks.
- `.github/workflows/codacy.yml` runs on the same branches plus a weekly cron. It executes Codacy CLI v2 via `./.codacy/cli.sh analyze` (using `.codacy/codacy.yaml`), emits SARIF, and uploads results via `github/codeql-action/upload-sarif@v4` so findings land in GitHub Advanced Security next to CodeQL alerts. CLI is pinned with `CODACY_CLI_V2_VERSION=v2.2.0` for deterministic output.
  - Note: Linux runners require the script to be executable; the workflow contains a `chmod +x ./.codacy/cli.sh` step to prevent `Permission denied` and ensure SARIF files are generated.
  - Reliability: SARIF upload steps are conditional using `if: ${{ hashFiles('<file>.sarif') != '' }}` so a missing file doesn’t fail the job when a tool produces no output.
  - Config schema: `.codacy/codacy.yaml` uses `version: "2"` and lists tools as objects with `name` (e.g., `- name: pmd`).
- Supply-chain: Third-party actions are pinned; `markdownlint-cli2` uses `DavidAnson/markdownlint-cli2-action@30a0e04f1870d58f8d717450cc6134995f993c63` to satisfy Semgrep/Codacy checks on unpinned actions.
- Codacy MCP instructions file (`.github/instructions/codacy.instructions.md`) documents mandatory post-edit analysis triggers. When automated edits touch source or docs, immediately run the Codacy CLI for each changed file.
- Local Codacy run (WSL wrapper script) to replicate CI:

```pwsh
pwsh -NoProfile -File .\.codacy\Invoke-CodacyWSL.ps1 -RepositoryPath . -Verbose
```

- Coverage improvements must be accompanied by an updated `tests/.coverage-baseline.json`. The harness exits non-zero if coverage falls below the baseline (currently 71.02%).
- Issue/PR templates and CODEOWNERS live under `.github/`; use them so reviewers get adequate context and the right maintainers are auto-assigned.

## Recent Bootstrap Fixes (Phase 10+)

The bootstrap process has been hardened to handle several critical scenarios:

### Configuration Validation
- **ConfigValidator Parser Error** (Phase 10): Fixed incorrect script block scoping that prevented configuration validation from completing. The issue manifested as `"if is not recognized"` parser errors.
- **Type Validation**: Enhanced ConfigValidator to support Dictionary types and null value handling for optional properties.

### Vault & Secrets
- **GitHub-Token Console Mode Error**: Fixed Win32 console mode error (0x57 "Falscher Parameter") that occurred when prompting for vault master password during bootstrap. Added try-catch wrapper around `Read-Host` with graceful fallback for optional secrets.
- **Implementation**: Located in `src/Modules/PSmm/Private/Bootstrap/Get-SystemSecret.ps1` (lines 305-330). When console input fails on optional secrets, bootstrap continues with null token instead of blocking.

### Plugin Installation
- **ExifTool Installer Error**: Fixed "file already exists" error by replacing fragile string-based path construction with dynamic directory search using wildcard patterns. The installer now handles variable directory naming conventions robustly.
- **FileSystemService Overload**: Added explicit 3-parameter overload for `GetChildItem()` method to resolve PowerShell's method overload resolution issues when default parameters exist.
- **Path Resolution**: Enhanced `Get-LocalPluginExecutablePath` to dynamically resolve plugin installation directories from the installed plugins root when `InstallPath` property is missing from config.

### Service Health Checks
- **HTTP Wrapper Availability**: Made the HTTP service health check non-critical. The check now gracefully handles missing `Invoke-HttpRestMethod` wrapper function and defaults to OK status instead of blocking bootstrap.
- **Impact**: All 11 required plugins (7z, PortableGit, git-lfs, gitversion, exiftool, ffmpeg, ImageMagick, KeePassXC, mkvtoolnix, mariadb, digiKam) now confirm successfully, and the application reaches the interactive UI phase.

## Performance Considerations

- Prefer streaming operations for large media metadata extraction.
- Defer plugin initialization until required (lazy acquire).

## Troubleshooting

| Symptom | Mitigation |
|---------|------------|
| Module import failure | Verify PowerShell version & dependencies installed |
| Plugin missing | Re-run `Confirm-Plugins` with verbose logging |
| Secret retrieval error | Ensure KeePassXC CLI installed & vault path correct |
| Test flakiness | Isolate external dependencies with mocks |

Return to [index](index.md).
