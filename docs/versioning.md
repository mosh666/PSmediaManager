# Versioning Guide

## Overview

PSmediaManager and all its modules use **dynamic versioning** derived completely from Git tags and commit history. This ensures version consistency across the entire codebase and follows semantic versioning best practices for GitHub repositories.

## Version Strategy

### Current Status
- **State**: First tagged release `v0.1.0` created; ongoing development on `dev`
- **Current Release**: `v0.1.0`
- **Development Branch**: `dev` produces prerelease builds like `0.1.0-alpha.N+<sha>`

### Semantic Versioning

We follow [Semantic Versioning 2.0.0](https://semver.org/):

```text
MAJOR.MINOR.PATCH[-PRERELEASE][+METADATA]
```

- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality (backward-compatible)
- **PATCH**: Bug fixes (backward-compatible)
- **PRERELEASE**: Development/testing tags (alpha, beta, rc)
- **METADATA**: Build information (branch, commit SHA)

### Branch-Based Versioning

| Branch | Version Format | Example | Purpose |
|--------|---------------|---------|---------|
| `main` | `X.Y.Z` | `1.0.0` | Production releases |
| `dev` | `X.Y.Z-alpha.N+SHA` | `0.1.0-alpha.5+abc1234` | Development builds |
| `feature/*` | `X.Y.Z-feature.N+SHA` | `0.1.0-feature.3+def5678` | Feature branches |
| `hotfix/*` | `X.Y.Z-hotfix.N+SHA` | `1.0.1-hotfix.2+ghi9012` | Hotfixes |
| `release/*` | `X.Y.Z-rc.N+SHA` | `1.0.0-rc.1+jkl3456` | Release candidates |

## GitVersion Configuration

The repository uses **GitVersion** for automated semantic versioning. Configuration is in `GitVersion.yml`:

### Key Settings

```yaml
mode: ContinuousDelivery
next-version: 0.1.0
tag-prefix: 'v'
```

### Branch Configuration

- **main**: Production releases (no prerelease tag)
- **dev**: Alpha releases with commit count
- **feature**: Feature preview builds
- **hotfix**: Hotfix preview builds
- **release**: Release candidate builds

### Commit Message Conventions

You can control version bumps via commit messages:

```bash
# Major version bump (breaking changes)
git commit -m "feat: redesign API +semver:major"

# Minor version bump (new features)
git commit -m "feat: add new command +semver:minor"

# Patch version bump (bug fixes)
git commit -m "fix: resolve crash +semver:patch"

# No version bump
git commit -m "docs: update readme +semver:none"
```

## Implementation Details

### Build-Time Version Update

Since PowerShell module manifests run in restricted language mode and cannot execute dynamic code, versions are updated at build time using a dedicated script.

**Script**: `Update-ModuleVersions.ps1`

```powershell
# Show current version
.\Update-ModuleVersions.ps1 -ShowVersion

# Update all module manifests
.\Update-ModuleVersions.ps1 -UpdateManifests
```

### CI Automation (GitHub Actions)

Run the build script automatically in CI to keep manifests in sync during pipelines. Add a step (already present in `ci.yml` after PowerShell setup) like:

```yaml
- name: Update module versions from Git
  run: |
    $pwsh = "$env:PWSH_754_PATH"
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File .\Update-ModuleVersions.ps1 -UpdateManifests
```

### Local Automation (Pre-commit Hook)

Use the provided hook to auto-update manifests before every commit:

```bash
pwsh -NoProfile -File ./tools/Enable-GitHooks.ps1
# or set manually
git config core.hooksPath .githooks
# or set during clone
git clone --config core.hooksPath=.githooks https://github.com/mosh666/PSmediaManager.git
```

Hook location: `.githooks/pre-commit.ps1`

Behavior:
- Runs `Update-ModuleVersions.ps1 -UpdateManifests`
- Stages updated `.psd1` manifests automatically
- Fails the commit if version sync fails

### Dynamic Version Helper

Location: `src/Modules/PSmm/Private/Get-PSmmDynamicVersion.ps1`

Functions:
- `Get-PSmmDynamicVersion`: Returns Major.Minor.Patch for module manifests
- `Get-PSmmFullVersion`: Returns full SemVer with prerelease and metadata

This helper is used by:
- `Update-ModuleVersions.ps1` build script
- `Invoke-PSmm.ps1` bootstrap for runtime `AppVersion`

### Module Manifests

All module manifests (`*.psd1`) contain a placeholder version that is updated at build time:

```powershell
@{
    RootModule = 'ModuleName.psm1'
    # Version updated by Update-ModuleVersions.ps1 from Git
    ModuleVersion = '0.0.1'
    # ... rest of manifest
}
```

**Important**: Do not manually edit `ModuleVersion` in manifests. Always use the build script.

### Runtime Version

The application version is set during bootstrap in `Invoke-PSmm.ps1`:

```powershell
$Config.AppVersion = Get-ApplicationVersion -GitPath $GitPath -GitVersionExecutablePath $gitVersionExecutable
```

This populates `AppConfiguration.AppVersion` with the full semantic version.

## Version Discovery Methods

The system attempts to retrieve versions in this order:

1. **GitVersion Tool** (preferred)
   - Looks for `gitversion.exe` in plugins directory
   - Falls back to PATH
   - Provides complete semantic versioning information

2. **Native Git Commands** (fallback)
   - Uses `git describe --tags`
   - Constructs version from tag + commits + SHA

3. **Default Fallback**
   - Returns `0.0.1` if Git unavailable
   - Ensures modules can still load in disconnected scenarios

## Creating Releases

### First Release (v0.1.0)

Since the repository is currently unreleased:

```bash
# Create and push the first tag
git tag -a v0.1.0 -m "Initial release"
git push origin v0.1.0

# After tagging, all modules will report version 0.1.0
```

### Subsequent Releases

```bash
# For a new minor version
git checkout main
git merge dev
git tag -a v0.2.0 -m "Release 0.2.0"
git push origin main --tags

# For a patch release
git checkout main
git cherry-pick <commit-sha>
git tag -a v0.1.2 -m "Release 0.1.2"
git push origin main --tags
```

## Module Version Synchronization

All modules share the same version as the application:

| Module | Version Source | Synchronized |
|--------|---------------|--------------|
| `PSmm` | Git (via GitVersion) | ✅ Yes |
| `PSmm.Logging` | Git (via GitVersion) | ✅ Yes |
| `PSmm.Plugins` | Git (via GitVersion) | ✅ Yes |
| `PSmm.Projects` | Git (via GitVersion) | ✅ Yes |
| `PSmm.UI` | Git (via GitVersion) | ✅ Yes |

This ensures that:
- All modules evolve together
- Version numbers are always consistent
- No manual version updates are required
- Release management is simplified

## Best Practices

### DO ✅

- Create annotated tags: `git tag -a v1.0.0 -m "Release 1.0.0"`
- Use semantic versioning for all releases
- Include `+semver:` markers in commit messages for clear intent
- Test version retrieval after creating tags
- Keep `GitVersion.yml` in sync with branching strategy

### DON'T ❌

- Manually edit version numbers in manifests (they're dynamic)
- Create lightweight tags (use `-a` for annotated tags)
- Skip tagging releases
- Hardcode versions anywhere in the codebase
- Modify `ModuleVersion` in `.psd1` files directly

## Verification

### Check Current Version

```powershell
# Get version of a module
(Get-Module PSmm -ListAvailable).Version

# Get application version (after bootstrap)
$Config.AppVersion

# Test version helper directly
. .\src\Modules\PSmm\Private\Get-PSmmDynamicVersion.ps1
Get-PSmmDynamicVersion -Verbose
Get-PSmmFullVersion -Verbose
```

### Expected Output (Before v0.1.0 Tag)

```text
Module version: 0.0.1
App version: 0.1.0-alpha.25+Branch.dev.Sha.abc1234
```

### Expected Output (After v0.1.0 Tag)

```text
Module version: 0.1.0
App version: 0.1.0-abc1234
```

## Troubleshooting

### GitVersion Not Found

**Symptom**: Versions show as `0.0.1`

**Solution**:
1. Install GitVersion plugin: `Confirm-Plugins` from PSmediaManager
2. Or install globally: `choco install gitversion.portable`
3. Verify: `gitversion.exe --version`

### Wrong Version Displayed

**Symptom**: Version doesn't match expected value

**Solution**:
1. Ensure you're in the repository directory
2. Check Git tags: `git tag -l`
3. Run GitVersion manually: `gitversion.exe /output json`
4. Verify branch: `git branch --show-current`

### Module Import Fails

**Symptom**: "Cannot bind parameter 'ModuleVersion'"

**Solution**:
1. Check that `Get-PSmmDynamicVersion.ps1` exists
2. Ensure Git repository is valid (`.git` directory exists)
3. Verify PowerShell version: `$PSVersionTable.PSVersion` (must be 7.5.4+)

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Install GitVersion
  uses: gittools/actions/gitversion/setup@v0.10.2
  with:
    versionSpec: '5.x'

- name: Determine Version
  uses: gittools/actions/gitversion/execute@v0.10.2
  with:
    useConfigFile: true
    configFilePath: GitVersion.yml

- name: Build Module
  shell: pwsh
  run: |
    Import-Module ./src/Modules/PSmm/PSmm.psd1
    $version = (Get-Module PSmm).Version
    Write-Host "Building version: $version"
```

## Future Enhancements

Planned improvements:
- [ ] Automated changelog generation from commit history
- [ ] Version badge generation for README
- [ ] Pre-commit hooks to validate version consistency
- [ ] Release notes automation
- [ ] Version comparison utilities

## References

- [Semantic Versioning 2.0.0](https://semver.org/)
- [GitVersion Documentation](https://gitversion.net/)
- [PowerShell Module Manifest](https://docs.microsoft.com/powershell/module/microsoft.powershell.core/new-modulemanifest)
- [Git Tagging](https://git-scm.com/book/en/v2/Git-Basics-Tagging)

---

**Document Version**: 1.0.0  
**Last Updated**: 2025-12-08  
**Maintainer**: Der Mosh
