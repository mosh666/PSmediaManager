# Configuration

PSmediaManager employs layered configuration objects and safe export capabilities for debugging and sharing.

## Components

- `AppConfiguration`: runtime effective configuration instance.
- `AppConfigurationBuilder`: fluent builder aggregating sources.
- Secret abstraction: retrieval via KeePassXC CLI wrappers (not in plain text config).

## Layering Model

1. Internal defaults.
2. Environment-derived values (paths, OS specifics).
3. User overrides (future: persisted user config file or project-scoped settings).

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
