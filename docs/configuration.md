# Configuration

PSmediaManager employs layered configuration objects and safe export capabilities for debugging and sharing.

## Components

- `AppConfiguration`: runtime effective configuration instance.
- `AppConfigurationBuilder`: fluent builder aggregating sources.
- Secret abstraction: retrieval via KeePassXC CLI wrappers (not in plain text config).

## Configuration Files

PSmediaManager uses several configuration files located in `src/Config/PSmm/`:

- **PSmm.App.psd1**: Application-level settings (paths, logging, UI preferences)
- **PSmm.Requirements.psd1**: PowerShell version and required PSGallery modules
- **PSmm.Plugins.psd1**: Global plugin manifest with definitions for all external tools
- **PSmm.Storage.psd1**: Storage group configuration (created on-drive during first-run setup)

Additionally, projects can provide:
- **[ProjectRoot]/Config/PSmm/PSmm.Plugins.psd1**: Project-specific plugin overrides (optional)

## Layering Model

1. Internal defaults.
2. Environment-derived values (paths, OS specifics).
3. Global configuration files (App, Requirements, Plugins).
4. Project-specific overrides (when a project is selected).
5. Runtime state and resolved values.

## Safe Export

Use `Export-SafeConfiguration` to serialize the configuration omitting / redacting secrets or sensitive paths.

```pwsh
Export-SafeConfiguration -Path ./config-safe.ps1
```

Automatic handling includes:

- Scalar quoting for clarity.
- Cyclic reference detection to prevent infinite traversal.
- Redaction for known secret placeholders.

> **GitHub best practice:** When opening a bug report, attach the sanitized output from `Export-SafeConfiguration` so maintainers can reproduce issues without exposing secrets. Security vulnerabilities should follow [SECURITY.md](../SECURITY.md) and leverage GitHub Security Advisories when possible.

## Plugin Configuration

PSmediaManager uses a manifest-based plugin system with global defaults and optional project-level overrides.

### Global Plugin Manifest

Located at `src/Config/PSmm/PSmm.Plugins.psd1`, this file defines all available external tools with their properties:

- **Mandatory**: Core plugins required by all projects (`$true`) vs optional tools (`$false`)
- **Enabled**: Default activation state (can be overridden per-project for optional plugins)
- **Source**: Acquisition method (`GitHub`, `Url`)
- **AssetPattern**: Regex pattern for deterministic asset selection
- **Command**: Executable filename
- **CommandPath**: Relative path within plugin directory
- **RegisterToPath**: Whether to add to Process PATH during session

Example:

```powershell
@{
    Plugins = @{
        c_Misc = @{
            FFmpeg = @{
                Mandatory = $false
                Enabled   = $false
                Source = 'Url'
                BaseUri = 'https://www.gyan.dev'
                VersionUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full.7z'
                CommandPath = 'bin'
                Command = 'ffmpeg.exe'
                Name = 'ffmpeg'
                RegisterToPath = $true
            }
        }
    }
}
```

### Project-Level Plugin Overrides

Projects can enable optional plugins by creating `[ProjectRoot]/Config/PSmm/PSmm.Plugins.psd1`:

```powershell
@{
    Plugins = @{
        c_Misc = @{
            FFmpeg = @{ Enabled = $true }
            ImageMagick = @{ Enabled = $true }
        }
    }
}
```

**Rules:**
- Project manifests can only override the `Enabled` flag for optional plugins
- Mandatory plugins cannot be disabled
- All other properties must match the global manifest (conflicts trigger validation errors)
- Project manifests are automatically loaded when selecting a project via `Select-PSmmProject`

### Plugin Resolution

The `Resolve-PluginsConfig` function merges global and project configurations:

1. Loads global manifest from `PSmm.Plugins.psd1`
2. Loads project manifest if available (and if a project is selected)
3. Validates no conflicting property definitions (except `Enabled`)
4. Enforces that mandatory plugins remain enabled
5. Preserves plugin state (CurrentVersion, LatestVersion) across reloads
6. Stores resolved configuration in `Config.Plugins.Resolved`

Access pattern:

```powershell
# After Invoke-PSmm or Select-PSmmProject:
$resolvedPlugins = $Config.Plugins.Resolved

# Check if a plugin is enabled for current scope:
$isFFmpegEnabled = $Config.Plugins.Resolved.c_Misc.FFmpeg.Enabled

# Plugin paths are tracked separately:
$globalManifestPath = $Config.Plugins.Paths.Global
$projectManifestPath = $Config.Plugins.Paths.Project  # null if no project manifest
```

### Adding New Plugins

1. Add definition to `src/Config/PSmm/PSmm.Plugins.psd1` under appropriate group
2. Set `Mandatory = $true` for core tools, `$false` for optional tools
3. Set `Enabled = $true` for mandatory plugins or default-enabled optional tools
4. Provide accurate `AssetPattern` and `Command` details
5. Set `RegisterToPath = $true` if the tool should be available in PATH
6. Document any special acquisition logic if needed
7. Run `Confirm-Plugins` to test acquisition

## Secrets Management

KeePassXC CLI is leveraged for secure secret storage.

```pwsh
Initialize-SystemVault -Path ./vault/database.kdbx
Save-SystemSecret -Key 'DbPassword' -Value (Read-Host -AsSecureString 'Password')
$secret = Get-SystemSecret -Key 'DbPassword'
```

Guidelines:

- Never embed raw credentials in scripts committed to the repo.
- Use descriptive keys; avoid overloading single secrets with multi-purpose values.

## Environment & Paths

The configuration builder resolves storage roots, plugin directories, and log locations. Ensure target drives have sufficient space for media operations.

## Storage Configuration

### Initial Setup

- **First-run wizard**: Storage is configured interactively on first start. Only USB/removable drives are supported for selection.
- **On-drive config**: The resulting configuration is saved to `\\PSmm.Config\\PSmm.Storage.psd1` on the same drive the app runs from. This file is the sole source of truth for storage.
- **Repo config**: `src/Config/PSmm/PSmm.App.psd1` intentionally ships with `Storage = @{}` and serves only as an example for other app settings.
- **Schema** (PSmm.Storage.psd1):

  ```pwsh
    @{ 
        Storage = @{ 
            '1' = @{ 
                DisplayName = 'My Media'
                Master      = @{ Label = 'Media-1'; SerialNumber = 'R381505X0SNNM7S' }
                Backup      = @{ 
                    '1' = @{ Label = 'Media-1-Backup-1'; SerialNumber = '2204EQ403864' }
                    '2' = @{ Label = 'Media-1-Backup-2'; SerialNumber = '2204GS402792' }
                }
            }
        }
    }
  ```

- **Runtime-derived**: `DriveLetter`, `Path`, and space metrics are detected on each launch via serial-number matching.

### Managing Storage Groups

Use the UI option `[R] Reconfigure Storage` to open the **Manage Storage** menu with the following operations:

#### [E] Edit Existing Group

- Lists all configured storage groups (even if drives are missing).
- Select a group by number to modify its DisplayName, Master drive, or Backup drives.
- Pre-fills current values for easy editing.
- Duplicate serial validation (see below) excludes the group being edited.

#### [A] Add New Group

- Runs the storage wizard to configure an additional group.
- Assigns the next available group ID automatically.
- All existing groups are preserved during this operation.

#### [R] Remove Group

- Select one or more groups to delete from configuration.
- After removal, remaining groups are **renumbered sequentially** (1, 2, 3…) to maintain a clean structure.
- Drive cache and storage status are safely reloaded after renumbering.
- If all groups are removed, the configuration becomes `Storage = @{}` and the first-run wizard will trigger on next launch.

#### [B] Back

- Returns to the main menu without changes.

### Duplicate Serial Number Handling

When configuring or editing a group, PSmediaManager checks if any selected drive serial number already exists in another storage group:

- **Interactive mode**: Displays a warning with the conflicting group number and prompts for confirmation:

  ```text
  Warning: Serial 'R381505X0SNNM7S' is already used in Storage Group 2.
  Continue anyway? (Y/N):
  ```

  User can choose to proceed (Y) or cancel (N). This allows intentional sharing of drives across groups if needed.

- **NonInteractive mode** (`-NonInteractive` flag): Fails immediately with a clear error message and exits. No prompts are shown.

**Note**: Duplicate serials within the same group (e.g., Master = Backup) are always blocked and cannot be overridden.

### Group Renumbering Behavior

- **On load**: Existing `PSmm.Storage.psd1` files are loaded unchanged. Groups retain their original numeric keys (e.g., '1', '3', '5' if '2' and '4' were previously removed).
- **On write**: Renumbering occurs **only during manage operations** (Edit/Add/Remove) when the configuration is written back to disk. This ensures a clean, sequential structure (1, 2, 3…) for human readability.
- **Safety**: After renumbering, the system reloads the storage file and refreshes drive cache via `LoadStorageFile` → `UpdateStorageStatus` → `Confirm-Storage`, ensuring in-memory state matches the new on-disk structure.

### Empty Storage Handling

If all storage groups are removed, the configuration file will contain:

```pwsh
@{ Storage = @{} }
```

On the next launch of `Start-PSmediaManager.ps1`, the first-run wizard will automatically trigger to guide you through configuring at least one storage group.

### Missing Drive Tolerance

Storage groups can be edited or removed even when their associated drives are not currently connected. Metadata operations (DisplayName, serial numbers) do not require physical drive presence, providing flexibility for offline management.

## Extending Configuration

When adding new config entries:

1. Define defaults in builder logic.
2. Update safe export filters if sensitive.
3. Add tests covering serialization & redaction.
4. Document new keys here.

## Debugging

```pwsh
$cfg = Invoke-PSmm
$cfg | Format-List *
Export-SafeConfiguration -Path ./debug-config.ps1
```

Compare exported vs runtime for discrepancies.

Return to [Modules](modules.md) for functional surfaces.
