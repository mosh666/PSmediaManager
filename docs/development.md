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

Add new test files under the matching `tests/Modules/<ModuleName>` path. Keep one `Describe` block per function family and narrow `Context` blocks for edge cases.

### Test Environment Isolation

Tests run in an isolated environment with the `MEDIA_MANAGER_TEST_MODE` environment variable set to `'1'`. This ensures:

- Runtime folders (`PSmm.Log`, `PSmm.Plugins`, `PSmm.Vault`) are created within the test directory instead of the system drive root
- Test artifacts remain contained and don't pollute the system
- Tests can run in parallel without conflicting with production installations

The `AppConfigurationBuilder` detects test mode and adjusts path resolution accordingly, keeping all test data within temporary directories managed by Pester's `TestDrive`.

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

## Release Process (Proposed)

1. Merge feature branches after review & tests pass.
2. Update `ModuleVersion` in manifests if public surface changed.
3. Tag release: `git tag -a v1.x.y -m "Release notes"`.
4. Draft GitHub Release summarizing changes.
5. (Future) Publish modules to PowerShell Gallery.

## Automation & Quality Gates

- `.github/workflows/ci.yml` (push/PR to `main` and `dev` + manual dispatch) installs PowerShell 7.5.4, trusts PSGallery for dependency installs, runs `tests/Invoke-PSScriptAnalyzer.ps1`, executes `tests/Invoke-Pester.ps1 -CodeCoverage -Quiet`, and uploads analyzer/test/coverage artifacts (`tests/TestResults.xml`, `.coverage-jacoco.xml`, `.coverage-latest.json`, `.coverage-debug.txt`). Failures block merges via required GitHub checks.
- `.github/workflows/codacy.yml` runs on the same branches plus a weekly cron. It executes Codacy Analysis CLI, emits SARIF, and uploads results via `github/codeql-action/upload-sarif@v4` so findings land in GitHub Advanced Security next to CodeQL alerts.
- Coverage improvements must be accompanied by an updated `tests/.coverage-baseline.json`. The harness exits non-zero if coverage falls below the baseline (currently 65.43%).
- Issue/PR templates and CODEOWNERS live under `.github/`; use them so reviewers get adequate context and the right maintainers are auto-assigned.

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
