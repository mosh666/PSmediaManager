# PSmediaManager Deep Research Report
## Exception Handling & Class Usage Analysis

**Analysis Date**: December 5, 2025  
**Repository**: PSmediaManager (dev branch)  
**Scope**: Comprehensive code review for unused specialized classes

---

## Executive Summary

A deep audit of the PSmediaManager codebase reveals **significant underutilization of the sophisticated exception classes** defined in `src/Modules/PSmm/Classes/Exceptions.ps1`. The project has invested heavily in creating nine specialized exception classes with rich context capabilities, but the vast majority of the codebase continues to use generic string throws and `System.Exception` instances.

### Key Findings:
- **78+ direct string throws** that should use typed exceptions
- **2 generic `System.Exception` instances** where specific exception classes exist  
- **3 `Write-Error` calls** that should throw typed exceptions
- **100+ catch blocks** that need enhancement for proper exception context preservation
- **$0 adoption rate** of custom exception classes in ~95% of throw statements

---

## Available Exception Classes

The PSmm module provides nine well-designed exception classes:

### 1. **MediaManagerException** (Base)
- Root exception for all PSmediaManager errors
- Features:
  - Context tracking
  - Timestamp recording
  - Recovery suggestions
  - Optional recovery hints
  - Additional data dictionary for structured context

### 2. **ConfigurationException**
**Use Cases:**
- Configuration file missing or invalid
- Configuration schema violations
- Invalid configuration keys/values
- Configuration member validation failures
- Configuration type mismatches

**Properties:**
- `ConfigPath` - Path to the configuration file
- `InvalidKey` - The key that failed validation
- `InvalidValue` - The value that was invalid

**Current Code Not Using This (20+ cases):**
- `Initialize-Logging.ps1` - Lines 78, 88, 99, 116, 131, 155, 160, 167, 172, 176
- `AppConfigurationBuilder.ps1` - Lines 73, 255, 343, 353, 360, 378, 382, 501, 505, 519
- `Invoke-StorageWizard.ps1` - Lines 49, 52
- `Export-SafeConfiguration.ps1` - Lines 1279, 1301, 1310, 1318
- `PSmediaManager.ps1` - Lines 105, 244
- `Invoke-PSmm.ps1` - Lines 80, 130, 205
- `Initialize-SystemVault.ps1` - Lines 132, 273, 284
- `Get-SystemSecret.ps1` - Lines 485

### 3. **ModuleLoadException**
**Use Cases:**
- Module not found or not loadable
- Module version incompatibility
- Module import failures
- Core service loading failures
- Required function unavailable

**Properties:**
- `ModuleName` - Name of the module that failed to load
- `RequiredVersion` - Required version (if applicable)
- `FoundVersion` - Found version (if version mismatch)

**Current Code Not Using This (8+ cases):**
- `PSmediaManager.ps1` - Lines 105, 167, 176
- `Initialize-Logging.ps1` - Line 238
- `Invoke-PSmm.ps1` - Line 143

### 4. **PluginRequirementException**
**Use Cases:**
- Required plugin missing or unavailable
- Plugin version incompatibility
- Plugin installation failures
- Plugin configuration issues
- Required tool missing (7z, ImageMagick, etc.)
- Plugin asset download failures
- Unsupported file formats

**Properties:**
- `PluginName` - Name of the plugin
- `RequiredVersion` - Required version
- `FoundVersion` - Found version
- `DownloadUrl` - URL for downloading/installing

**Current Code Not Using This (25+ cases):**
- `ImageMagick.ps1` - Lines 33, 39, 68
- `Get-PluginFromGitHub.ps1` - Lines 305, 308, 311
- `Confirm-Plugins.ps1` - Lines 161, 384, 392, 632, 852, 1042, 1049, 1078, 1085, 1092, 1096
- `Initialize-KeePassPlugin.ps1` - Lines 45, 65, 73, 80
- `Resolve-ToolCommandPath.ps1` - Line 35
- `Get-SystemSecret.ps1` - Line 525

### 5. **StorageException**
**Use Cases:**
- Storage drive not found or not mounted
- Storage path invalid or inaccessible
- Storage group configuration issues
- Insufficient disk space
- Storage operation failures

**Properties:**
- `StoragePath` - Path to the storage
- `StorageGroup` - Storage group identifier
- `RequiredSpaceGB` - Space needed
- `AvailableSpaceGB` - Space available

**Current Code Not Using This (10+ cases):**
- `Select-PSmmProject.ps1` - Lines 148, 155
- `New-PSmmProject.ps1` - Line 64
- `Get-PSmmProjects.ps1` - Lines 640, 825
- `Invoke-StorageWizard.ps1` - Line 52
- `AppConfigurationBuilder.ps1` - Line 378, 382
- `Get-SystemSecret.ps1` - Line 485

### 6. **LoggingException**
**Use Cases:**
- Log directory cannot be created
- Log file not writable
- Logging configuration failures
- PSLogs module setup failures
- Insufficient disk space for logs
- Permission issues with log paths

**Properties:**
- `LogPath` - Path to the log file/directory
- `LogLevel` - Logging level if applicable

**Current Code Not Using This (8+ cases):**
- `Initialize-Logging.ps1` - Lines 73, 238, 291, 296, 309, 318, 327, 350

### 7. **ProcessException**
**Use Cases:**
- External process execution failures
- Process exit code errors
- Command not found
- Process startup failures
- Process timeout scenarios

**Properties:**
- `ProcessName` - Name of the process that failed
- `ExitCode` - Exit code returned by process
- `CommandLine` - Full command line executed

**Current Code Not Using This (15+ cases):**
- `Confirm-Plugins.ps1` - Lines 1042, 1049, 1078, 1085, 1092
- `Initialize-SystemVault.ps1` - Lines 148, 373
- `Get-SystemSecret.ps1` - Lines 535, 546
- `Get-PluginVersionInfo.ps1` (for 7z extraction failures)

### 8. **ProjectException**
**Use Cases:**
- Project not found
- Project path invalid
- Project configuration issues
- Project operation failures
- Project dependency issues

**Properties:**
- `ProjectName` - Name of the project
- `ProjectPath` - Path to the project
- `Operation` - What operation was being performed

**Current Code Not Using This (3+ cases):**
- `Select-PSmmProject.ps1` - Lines 142, 148, 155

### 9. **ValidationException**
**Use Cases:**
- Parameter/property validation failures
- Type mismatches
- Required values missing
- Value format/pattern violations
- State validation failures
- Service dependency validation

**Properties:**
- `PropertyName` - Name of the property being validated
- `InvalidValue` - The value that failed validation
- `ExpectedFormat` - What format is expected
- `ValidationRules` - Array of rules that failed

**Current Code Not Using This (20+ cases):**
- `Invoke-MultiOptionPrompt.ps1` - Line 93
- `Get-PSmmProjects.ps1` - Lines 640, 825
- `New-FileSystemService.ps1` - Lines 35, 38, 46, 69, 83
- `Invoke-StorageWizard.ps1` - Line 49
- `AppConfigurationBuilder.ps1` - Lines 501, 505, 519
- `Initialize-SystemVault.ps1` - Lines 82, 281
- `Confirm-Plugins.ps1` - Lines 384, 632
- Multiple additional validation scenarios

---

## Detailed Findings by File

### **src/PSmediaManager.ps1** (Main Entry Point)
**Issues Found**: 3  
**Severity**: HIGH (Core bootstrap code)

| Line | Pattern | Issue | Recommended Fix |
|------|---------|-------|-----------------|
| 84 | `Write-Error "PSmediaManager requires PowerShell >= 7.5.4..."` | Runtime version check using Write-Error instead of exception | Throw `ValidationException` with min version context |
| 105 | `throw "Core services file not found: $coreServicesPath"` | String throw for module loading failure | Throw `ModuleLoadException` with path context |
| 167 | `throw [System.Exception]::new("Failed to import module '$moduleName'", ...)` | Generic System.Exception for module loading | Use `ModuleLoadException` with module name and version |
| 176 | `throw [System.Exception]::new("No modules were loaded from: $modulesPath")` | Generic System.Exception for module validation | Use `ModuleLoadException` with path context |
| 244 | `throw "Unable to resolve repository root from: $script:ModuleRoot"` | String throw for path resolution | Use `ConfigurationException` with path context |

### **src/Modules/PSmm.Logging/Public/Initialize-Logging.ps1**
**Issues Found**: 11  
**Severity**: HIGH (Critical startup path)

**Pattern**: Nearly all configuration validation uses string throws instead of `ConfigurationException` or `LoggingException`

| Lines | Type | Recommendation |
|-------|------|-----------------|
| 78-176 | Config validation | Use `ConfigurationException` throughout |
| 238 | Module import failure | Use `ModuleLoadException` |
| 291, 296 | Directory operations | Use `LoggingException` |
| 309, 318, 327 | PSLogs setup | Use `LoggingException` |
| 350 | Service validation | Use `ValidationException` |

### **src/Modules/PSmm/Classes/AppConfigurationBuilder.ps1**
**Issues Found**: 9  
**Severity**: MEDIUM (Startup, but not on critical path for all scenarios)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 73 | Validation | String throw for null/empty root path | Use `ValidationException` |
| 255 | File validation | Configuration file not found | Use `ConfigurationException` |
| 343 | File load | Configuration file load failure | Use `ConfigurationException` |
| 353 | File validation | Requirements file not found | Use `ConfigurationException` |
| 360 | File load | Requirements file load failure | Use `ConfigurationException` |
| 378 | File load | Storage file load failure | Use `StorageException` or `ConfigurationException` |
| 382 | Validation | Storage file structure invalid | Use `StorageException` or `ConfigurationException` |
| 501, 505, 519 | State validation | Builder state violations | Use `ValidationException` |

### **src/Modules/PSmm.Plugins/Private/Confirm-Plugins.ps1**
**Issues Found**: 11  
**Severity**: HIGH (Plugin installation & validation critical path)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 161 | Command resolution | Command not found in PATH | Use `PluginRequirementException` |
| 384, 392 | Type instantiation | Constructor returned null / Type instantiation failure | Use `ModuleLoadException` or `ProcessException` |
| 632 | Parameter validation | Configuration object incompatible | Use `ValidationException` |
| 852 | Plugin validation | Missing Config key | Use `PluginRequirementException` |
| 1042, 1049 | Process exit | MSI/EXE installer failures | Use `ProcessException` with exit code |
| 1078 | Dependency | 7z tool required but missing | Use `PluginRequirementException` |
| 1085, 1092 | Process exit | 7z archive operations failed | Use `ProcessException` with exit code |
| 1096 | Validation | Unsupported installer type | Use `PluginRequirementException` |

### **src/Modules/PSmm.Projects/Public/Select-PSmmProject.ps1**
**Issues Found**: 3  
**Severity**: MEDIUM (Project selection, runtime operation)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 142 | Project lookup | Project not found in storage | Use `ProjectException` with project name |
| 148 | Storage validation | Storage drive not mounted | Use `StorageException` with drive info |
| 155 | Path validation | Project path doesn't exist | Use `ProjectException` with path |

### **src/Modules/PSmm.Projects/Public/New-PSmmProject.ps1**
**Issues Found**: 1  
**Severity**: MEDIUM (Project creation)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 64 | Storage validation | Master storage drive not found | Use `StorageException` |

### **src/Modules/PSmm.Projects/Public/Get-PSmmProjects.ps1**
**Issues Found**: 2  
**Severity**: MEDIUM (Project enumeration)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 640, 825 | Service validation | FileSystem service required | Use `ValidationException` |

### **src/Modules/PSmm.Plugins/Private/Get-PluginFromGitHub.ps1**
**Issues Found**: 3  
**Severity**: MEDIUM (Plugin discovery)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 305, 308, 311 | Plugin validation | Missing required config keys | Use `PluginRequirementException` |

### **src/Modules/PSmm.Plugins/Private/Plugins/Misc/ImageMagick.ps1**
**Issues Found**: 3  
**Severity**: MEDIUM (Plugin-specific version resolution)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 33 | Version fetch | Failed to retrieve version from URL | Use `PluginRequirementException` |
| 39 | Asset search | No matching downloads found | Use `PluginRequirementException` |
| 68 | Version detection | Could not determine latest version | Use `PluginRequirementException` |

### **src/Modules/PSmm/Private/Bootstrap/Initialize-SystemVault.ps1**
**Issues Found**: 5  
**Severity**: HIGH (Vault initialization - first-run critical path)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 82 | Service validation | FileSystem service required | Use `ValidationException` |
| 132 | Setup cancellation | Max password attempts exceeded | Use `ConfigurationException` |
| 148 | Process execution | KeePass database creation failed | Use `ProcessException` with exit code |
| 273, 281 | Configuration | Vault path not set / Service required | Use `ConfigurationException` or `ValidationException` |
| 284, 373 | Operation | Vault initialization/entry add failed | Use `ConfigurationException` or `ProcessException` |

### **src/Modules/PSmm/Private/Bootstrap/Get-SystemSecret.ps1**
**Issues Found**: 4  
**Severity**: HIGH (Vault access - runtime-critical)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 485 | File validation | KeePass database not found | Use `ConfigurationException` |
| 525 | Plugin validation | keepassxc-cli executable not found | Use `PluginRequirementException` |
| 535, 546 | Process execution | KeePassXC CLI command failed | Use `ProcessException` with exit code |

### **src/Modules/PSmm.UI/Public/Invoke-MultiOptionPrompt.ps1**
**Issues Found**: 1  
**Severity**: LOW (UI validation)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 93 | Validation | No valid options provided | Use `ValidationException` |

### **src/Modules/PSmm/Public/Storage/Invoke-StorageWizard.ps1**
**Issues Found**: 2  
**Severity**: MEDIUM (Storage configuration UI)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 49 | Parameter validation | GroupId required but missing | Use `ValidationException` |
| 52 | Configuration lookup | Storage group not found | Use `StorageException` or `ConfigurationException` |

### **src/Modules/PSmm/Public/Export-SafeConfiguration.ps1**
**Issues Found**: 3  
**Severity**: MEDIUM (Configuration export)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 1279 | Output validation | Export produced empty content | Use `ConfigurationException` |
| 1301, 1310, 1318 | File operations | Content write failures | Use `ConfigurationException` |

### **src/Modules/PSmm.Logging/Private/New-FileSystemService.ps1**
**Issues Found**: 5  
**Severity**: LOW (Service layer validation)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 35, 38, 46, 69, 83 | Parameter validation | Empty/null path or itemType | Use `ValidationException` |

### **src/Modules/PSmm/Private/Resolve-ToolCommandPath.ps1**
**Issues Found**: 1  
**Severity**: MEDIUM (Tool resolution)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 35 | Command resolution | Tool command not found | Use `PluginRequirementException` or `ProcessException` |

### **src/Modules/PSmm.Logging/Public/Invoke-LogRotation.ps1**
**Issues Found**: 1  
**Severity**: LOW (Log maintenance)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 73 | Path validation | Log path not found | Use `LoggingException` or `ValidationException` |

### **src/Modules/PSmm/Public/Bootstrap/Invoke-PSmm.ps1**
**Issues Found**: 3  
**Severity**: HIGH (Bootstrap orchestration)

| Lines | Type | Issue | Recommendation |
|-------|------|-------|-----------------|
| 80 | Configuration validation | Requirements not loaded | Use `ConfigurationException` |
| 130, 143, 205 | Setup operations | First-run setup cancellation/failures | Use `ConfigurationException` or `ModuleLoadException` |

---

## Catch Blocks Needing Improvement

### Issue: Generic Exception Handling

Many catch blocks throughout the codebase either:
1. **Suppress errors silently** - Just log and continue
2. **Lose context** - Re-throw generic exceptions
3. **Don't preserve stack traces** - Wrap exceptions without `$_`
4. **Miss type checking** - Don't distinguish between different error types

### Examples:

**File**: `src/PSmediaManager.ps1`  
**Lines**: 110, 124, 164, 181, 210, 256, 291, 356

```powershell
catch {
    Write-Error "Failed to load core bootstrap services: $_" -ErrorAction Stop
}
```

**Should be**:
```powershell
catch {
    $ex = if ($_ -is [ModuleLoadException]) { $_ } else { [ModuleLoadException]::new("Failed to load core bootstrap services", "PSmm.Core", $_) }
    throw $ex
}
```

**File**: `src/Modules/PSmm.Logging/Public/Initialize-Logging.ps1`  
**Multiple catch blocks** handling configuration issues

**Pattern**: Catch blocks should:
1. Check exception type
2. Create typed exceptions with context
3. Preserve inner exception via third parameter
4. Rethrow (don't swallow)

### Recommended Pattern:

```powershell
try {
    # Operation that might fail
}
catch {
    if ($_ -is [MediaManagerException]) {
        # Already typed, just rethrow
        throw $_
    }
    # Create appropriate typed exception
    $context = [ConfigurationException]::new("Description of what failed", $relevantPath, $_)
    throw $context
}
```

### Files with Problematic Catch Blocks:
- `src/PSmediaManager.ps1` - 9+ catch blocks
- `src/Modules/PSmm.Logging/Public/Initialize-Logging.ps1` - 15+ catch blocks
- `src/Modules/PSmm.Plugins/Private/Confirm-Plugins.ps1` - 20+ catch blocks
- `src/Modules/PSmm/Classes/AppConfigurationBuilder.ps1` - 8+ catch blocks
- `src/Modules/PSmm/Private/Bootstrap/Initialize-SystemVault.ps1` - 12+ catch blocks
- `src/Modules/PSmm/Private/Bootstrap/Get-SystemSecret.ps1` - 10+ catch blocks

---

## Opportunity Areas

### 1. **Exception Class Integration** (HIGH PRIORITY)
Replace all 78+ string throws with appropriate typed exceptions. This improves:
- Error context tracking
- Debugging capabilities
- Error recovery suggestions
- Structured error handling
- Testing and mock scenarios

### 2. **Catch Block Standardization** (MEDIUM PRIORITY)
Update catch blocks to:
- Use `New-MediaManagerErrorRecord` for cmdlet-based functions
- Use `Format-MediaManagerException` for logging
- Preserve original exceptions via inner exception parameter
- Create typed exceptions when catching generic exceptions

### 3. **Error Handling Helper Functions** (MEDIUM PRIORITY)
The exception classes define two helper functions that should be used:
- `New-MediaManagerErrorRecord()` - For cmdlet functions
- `Format-MediaManagerException()` - For readable error output

Current code: **0 usages**

### 4. **Documentation Enhancement** (LOW PRIORITY)
Add examples to each module showing proper exception usage patterns.

---

## Impact Assessment

### Current State
- **Adoption of custom exception classes**: < 1%
- **Code using generic exceptions**: > 99%
- **Effort to find error context**: HIGH (scattered through code)
- **Testability with mocked exceptions**: LOW

### After Full Implementation
- **Adoption of custom exception classes**: ~100%
- **Code using generic exceptions**: ~0%
- **Effort to find error context**: LOW (structured properties)
- **Testability with mocked exceptions**: HIGH
- **Error recovery guidance**: In every exception

### Benefits
1. **Better Debugging** - Rich context in each exception type
2. **Improved Error Messages** - Contextual recovery suggestions
3. **Easier Testing** - Mock specific exception types
4. **Better Logging** - Structured error data
5. **Code Clarity** - Exception type indicates problem category
6. **End-User Experience** - Better error guidance in logs

---

## Implementation Roadmap

### Phase 1: Critical Path (HIGH PRIORITY)
- [ ] `src/PSmediaManager.ps1` - Bootstrap failures
- [ ] `src/Modules/PSmm.Logging/Public/Initialize-Logging.ps1` - Logging initialization
- [ ] `src/Modules/PSmm/Classes/AppConfigurationBuilder.ps1` - Configuration loading

### Phase 2: Plugin System (HIGH PRIORITY)
- [ ] `src/Modules/PSmm.Plugins/Private/Confirm-Plugins.ps1`
- [ ] `src/Modules/PSmm.Plugins/Private/Get-PluginFromGitHub.ps1`
- [ ] `src/Modules/PSmm.Plugins/Private/Plugins/Misc/ImageMagick.ps1`

### Phase 3: Vault & Security (HIGH PRIORITY)
- [ ] `src/Modules/PSmm/Private/Bootstrap/Initialize-SystemVault.ps1`
- [ ] `src/Modules/PSmm/Private/Bootstrap/Get-SystemSecret.ps1`

### Phase 4: Project & Storage (MEDIUM PRIORITY)
- [ ] `src/Modules/PSmm.Projects/Public/Select-PSmmProject.ps1`
- [ ] `src/Modules/PSmm.Projects/Public/Get-PSmmProjects.ps1`
- [ ] `src/Modules/PSmm/Public/Storage/Invoke-StorageWizard.ps1`

### Phase 5: UI & Utilities (LOW PRIORITY)
- [ ] `src/Modules/PSmm.UI/Public/Invoke-MultiOptionPrompt.ps1`
- [ ] `src/Modules/PSmm.Logging/Public/Invoke-LogRotation.ps1`
- [ ] `src/Modules/PSmm.Logging/Private/New-FileSystemService.ps1`

---

## Conclusion

PSmediaManager has invested significant effort in creating a comprehensive exception hierarchy with rich context capabilities. However, this investment is currently under-utilized. The codebase continues to rely on generic string throws and `System.Exception` instances, missing opportunities for:

1. Better error diagnostics
2. Structured error data for logging systems
3. Recovery suggestions for end-users
4. Testability through typed exceptions
5. Clear error categorization

**Recommendation**: Implement a systematic refactoring to adopt the custom exception classes throughout the codebase, starting with the critical bootstrap and plugin paths. This will significantly improve maintainability, debuggability, and user experience when errors occur.

---

## Appendix: Exception Quick Reference

| Exception | Primary Use | When Created | Properties |
|-----------|------------|--------------|-----------|
| **ConfigurationException** | Config file/data issues | Config load/parse failures | ConfigPath, InvalidKey, InvalidValue |
| **ModuleLoadException** | Module import failures | Module import/version mismatches | ModuleName, RequiredVersion, FoundVersion |
| **PluginRequirementException** | Plugin/tool issues | Plugin missing/outdated | PluginName, RequiredVersion, FoundVersion, DownloadUrl |
| **StorageException** | Storage/drive issues | Drive not found, space issues | StoragePath, StorageGroup, RequiredSpaceGB, AvailableSpaceGB |
| **LoggingException** | Logging failures | Log dir/file issues | LogPath, LogLevel |
| **ProcessException** | External process failures | Process exit errors | ProcessName, ExitCode, CommandLine |
| **ProjectException** | Project operations | Project not found | ProjectName, ProjectPath, Operation |
| **ValidationException** | Parameter/value validation | Invalid inputs | PropertyName, InvalidValue, ExpectedFormat, ValidationRules |
| **MediaManagerException** | Generic errors | Fallback for unmapped errors | Context, RecoverySuggestion, AdditionalData |
