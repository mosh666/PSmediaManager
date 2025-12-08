# Dynamic Versioning - Quick Reference

## For Module Developers

### When creating a new module

Add your module path to `Update-ModuleVersions.ps1`:

```powershell
$manifestPaths = @(
    'src\Modules\PSmm\PSmm.psd1'
    'src\Modules\YourModule\YourModule.psd1'  # Add here
)
```

In your `.psd1` manifest, use:

```powershell
@{
    RootModule = 'YourModule.psm1'
    # Version updated by Update-ModuleVersions.ps1 from Git
    ModuleVersion = '0.0.1'
    # ... rest of manifest
}
```

### Never do this ❌

```powershell
ModuleVersion = '1.2.3'  # ❌ MANUALLY SET VERSION
```

### Always do this ✅

```powershell
# Run the build script to update versions
.\Update-ModuleVersions.ps1 -UpdateManifests

# Then commit the updated manifests
git add src/Modules/**/*.psd1
git commit -m "build: update module versions"
```

## Before Testing or Deployment

```powershell
# Update all manifests with current Git version
.\Update-ModuleVersions.ps1 -UpdateManifests

# Verify manifests are valid
Test-ModuleManifest -Path .\src\Modules\PSmm\PSmm.psd1
```

## For Contributors

### Commit Message Format

```bash
# Feature (minor bump)
git commit -m "feat: add new command +semver:minor"

# Bug fix (patch bump)
git commit -m "fix: resolve crash +semver:patch"

# Breaking change (major bump)
git commit -m "feat: redesign API +semver:major"

# No version change
git commit -m "docs: update readme +semver:none"
```

### Creating a Release

```bash
# 1. Merge to main
git checkout main
git merge dev

# 2. Tag with annotated tag
git tag -a v0.1.0 -m "Release 0.1.0"

# 3. Push to GitHub
git push origin v0.1.0
```

## For CI/CD

### GitHub Actions

```yaml
- name: Get Version
  id: version
  shell: pwsh
  run: |
    Import-Module ./src/Modules/PSmm/PSmm.psd1
    $version = (Get-Module PSmm).Version
    Write-Output "version=$version" >> $env:GITHUB_OUTPUT

- name: Use Version
  run: echo "Building version ${{ steps.version.outputs.version }}"
```

## Quick Checks

### Check current version

```powershell
# Module version
Import-Module .\src\Modules\PSmm\PSmm.psd1
(Get-Module PSmm).Version

# App version (after bootstrap)
$Config.AppVersion

# GitVersion directly
gitversion.exe /output json | ConvertFrom-Json | Select-Object SemVer, InformationalVersion
```

### Verify GitVersion config

```bash
gitversion.exe /showconfig
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Version shows `0.0.1` | Install GitVersion or ensure git tags exist |
| Wrong version displayed | Check current branch and tags: `git describe --tags` |
| Module won't load | Verify `Get-PSmmDynamicVersion.ps1` exists |

## See Also

- [Full Documentation](../docs/versioning.md)
- [GitVersion Docs](https://gitversion.net/)
- [Semantic Versioning](https://semver.org/)
