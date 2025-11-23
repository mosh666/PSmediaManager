# Development Guide

## Branching

- `main`: stable, reviewed code.
- `feature/<short-desc>`: new work.
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

Run entire suite:

```pwsh
./tests/Invoke-Pester.ps1
```

Add new test file under matching module path. Keep one `Describe` block per function family.

## Static Analysis

```pwsh
Invoke-ScriptAnalyzer -Path ./src -Recurse
```

Resolve all warnings before PR submission (or justify exclusions).

## Documentation Updates

- Update `README.md` for new public features.
- Expand relevant doc section.
- If adding configuration keys, update `configuration.md`.

## Release Process (Proposed)

1. Merge feature branches after review & tests pass.
2. Update `ModuleVersion` in manifests if public surface changed.
3. Tag release: `git tag -a v1.x.y -m "Release notes"`.
4. Draft GitHub Release summarizing changes.
5. (Future) Publish modules to PowerShell Gallery.

## CI Suggestions (Future)

- Workflow: lint + test matrix (Windows, Linux).
- Cache: PowerShell modules & plugin archives.
- Artifacts: coverage report, safe config snapshot.

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
