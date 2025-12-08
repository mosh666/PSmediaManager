# Troubleshooting Guide

This guide covers common issues and solutions when using PSmediaManager.

## Startup Issues

### "Module not found" or "Could not find Command"

**Symptoms:** Error message like `The term 'Invoke-PSmm' is not recognized` when launching the application.

**Causes:**

- PowerShell modules not properly imported
- Incorrect installation path
- Corrupted module manifest

**Solutions:**

1. Verify module installation:

    ```powershell
    Get-Module -ListAvailable PSmm
    ```

    Should show the module is installed in the expected path.

1. Force module reload:

    ```powershell
    Remove-Module PSmm -Force -ErrorAction SilentlyContinue
    Import-Module ./src/Modules/PSmm/PSmm.psd1 -Force
    ```

1. Check manifest syntax:

    ```powershell
    Test-ModuleManifest ./src/Modules/PSmm/PSmm.psd1
    ```

    Should return without errors.

1. Verify PowerShell version:

    ```powershell
    $PSVersionTable.PSVersion
    ```

    Requires PowerShell 7.5.4 or later. Install from [microsoft/PowerShell](https://github.com/microsoft/PowerShell/releases).

### Script execution policy blocks module loading

**Symptoms:** Error about execution policies when importing modules.

**Solution:** Set execution policy to allow local scripts:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Storage Issues

### "Storage drive not found"

**Symptoms:** `Get-StorageDrive` returns empty or storage operations fail.

**Causes:**

- Storage drives not configured
- Storage registry corrupted or missing
- Incorrect storage paths

**Solutions:**

1. Initialize storage wizard:

    ```powershell
    Invoke-StorageWizard
    ```

    Walks through storage configuration step-by-step.

1. Verify storage registry:

    ```powershell
    $storageConfig = Get-Content "$env:APPDATA\PSmediaManager\storage.json" | ConvertFrom-Json
    $storageConfig
    ```

    Check paths are valid and accessible.

1. Check drive accessibility:

    ```powershell
    Get-StorageDrive | ForEach-Object {
        Test-Path $_.Path -PathType Container
    }
    ```

    All should return `$true`.

### Storage wizard crashes or won't complete

**Symptoms:** Storage wizard hangs, crashes, or doesn't save configuration.

**Solutions:**

1. Clear corrupted configuration:

    ```powershell
    Remove-Item -Path "$env:APPDATA\PSmediaManager\storage.json" -Force
    ```

1. Run with elevated permissions:

    Right-click PowerShell and select "Run as Administrator" before launching storage wizard.

1. Check disk space:

    ```powershell
    Get-PSDrive | Where-Object {$_.Root -match 'C:\|D:\|E:\'}
    ```

    Ensure target drives have sufficient free space.

---

## Configuration Issues

### Configuration export/import fails

**Symptoms:** `Export-SafeConfiguration` or import operations fail with file I/O errors.

**Causes:**

- File permissions issues
- Path contains invalid characters
- Encoding mismatch

**Solutions:**

1. Verify export path exists and is writable:

    ```powershell
    Test-Path (Split-Path -Parent "C:\path\to\export.json")
    (Get-Acl "C:\path\to\export.json").Access | Select-Object IdentityReference, FileSystemRights
    ```

1. Use default export location:

    ```powershell
    Export-SafeConfiguration
    # Exports to default location without specifying path
    ```

1. Check file encoding:

    Configuration files should be UTF-8 without BOM. Verify with:

    ```powershell
    Get-Content "C:\path\to\config.json" -Encoding UTF8
    ```

---

## Plugin & Execution Issues

### Plugin installation fails

**Symptoms:** `Install-KeePassXC` or other plugin installation fails.

**Causes:**

- Network connectivity issues
- Insufficient disk space
- Antivirus blocking downloads
- Missing system dependencies

**Solutions:**

1. Check network connectivity:

    ```powershell
    Test-NetConnection -ComputerName github.com -Port 443
    ```

    Should show `TcpTestSucceeded: True`.

1. Verify disk space:

    ```powershell
    Get-PSDrive | Where-Object {$_.Used -and $_.Free -lt 500MB}
    ```

    Ensure at least 500MB free on installation drive.

1. Disable antivirus temporarily:

    Some antivirus software blocks PowerShell downloads. Add PSmediaManager folder to exclusions:

    - Windows Defender: Settings → Virus & threat protection → Manage settings → Add exclusions
    - Third-party antivirus: Consult documentation for your software

1. Check system dependencies:

    ```powershell
    Get-PSmmHealth
    ```

    Shows system health and missing dependencies.

### digiKam integration fails

**Symptoms:** `Start-PSmmdigiKam` fails or digiKam doesn't start properly.

**Causes:**

- digiKam not installed
- Project configuration incomplete
- Port conflicts
- Database connection issues

**Solutions:**

1. Verify digiKam installation:

    ```powershell
    where.exe digikam
    ```

    Should return path to digiKam executable.

1. Check project configuration:

    ```powershell
    Get-PSmmProjects | Select-Object Name, DigiKamConfigured
    ```

    Ensure `DigiKamConfigured` is `$true`.

1. Resolve port conflicts:

    ```powershell
    Get-PSmmProjectPorts -ProjectName "MyProject"
    # Then check if ports are free
    Get-NetTCPConnection | Where-Object {$_.LocalPort -in @(3306, 3307, 3308)}
    ```

1. Check database status:

    ```powershell
    # After starting project
    Get-Process | Where-Object {$_.Name -match 'mariadb|mysql'}
    ```

    MariaDB process should be running.

1. Review diagnostics:

    ```powershell
    # Check project logs (location varies by project)
    Get-Content "$projectPath\.psmm\debug.log" -Tail 50
    ```

---

## Performance Issues

### Application runs slowly or is unresponsive

**Symptoms:** Slow startup, sluggish UI, or operations take longer than expected.

**Causes:**

- Large storage configurations
- High disk I/O
- Logging verbosity too high
- System resource constraints

**Solutions:**

1. Reduce logging verbosity:

    ```powershell
    $env:PSMM_LOG_LEVEL = "Warning"
    # Then restart application
    ```

1. Check system resources:

    ```powershell
    Get-Process | Sort-Object -Property WS -Descending | Select-Object -First 5
    # High memory usage process?

    Get-Counter -Counter "\Processor(_Total)\% Processor Time"
    # CPU usage?
    ```

1. Optimize storage configuration:

    - Reduce number of monitored drives if possible
    - Move frequently-accessed storage to local SSD
    - Archive old storage configurations

1. Clear logs and caches:

    ```powershell
    # Clear application logs (keep 7 days)
    Get-ChildItem "$env:APPDATA\PSmediaManager\logs" -Filter "*.log" |
      Where-Object {$_.CreationTime -lt (Get-Date).AddDays(-7)} |
      Remove-Item
    ```

---

## Development & Testing Issues

### Pester tests fail during development

**Symptoms:** `Invoke-Pester.ps1` returns test failures.

**Solutions:**

1. Run tests with verbose output:

    ```powershell
    cd ./tests
    ./Invoke-Pester.ps1 -Verbose
    ```

1. Run specific test file:

    ```powershell
    ./Invoke-Pester.ps1 -Path ./Modules/PSmm
    ```

1. Check dependencies are loaded:

    ```powershell
    ./Invoke-Pester.ps1 -Verbose
    # Look for "Loaded" messages at beginning
    ```

1. Verify PSScriptAnalyzer settings:

    ```powershell
    ./Invoke-PSScriptAnalyzer.ps1
    # Should show 0 issues
    ```

1. Reset module cache:

    ```powershell
    Remove-Module PSmm*, PSmm.* -Force -ErrorAction SilentlyContinue
    ./Invoke-Pester.ps1
    ```

### PSScriptAnalyzer finds issues after changes

**Symptoms:** `Invoke-PSScriptAnalyzer.ps1` reports errors that weren't there before.

**Solutions:**

1. Review the specific error:

    ```powershell
    ./Invoke-PSScriptAnalyzer.ps1 | Where-Object {$_.RuleName -eq "YourRuleName"}
    ```

1. Check analyzer settings:

    ```powershell
    Get-Content ./tests/PSScriptAnalyzer.Settings.psd1
    ```

1. Fix common issues:

    - **PSUseApprovedVerbs:** Use only approved PowerShell verbs (Get, Set, Invoke, etc.)
    - **PSAvoidDefaultValueSwitchParameter:** Don't use default values in switch parameters
    - **PSMissingDocumentationComment:** Add comment-based help to functions

1. Apply fixes to all files:

    Manually fix reported issues in the code.

---

## Getting Help

If you're unable to resolve an issue:

1. **Check existing issues:** [GitHub Issues](https://github.com/mosh666/PSmediaManager/issues)

2. **Enable debug logging:** Set `$env:PSMM_LOG_LEVEL = "Debug"` before operations

3. **Collect diagnostics:**

    ```powershell
    Get-PSmmHealth | Export-Clixml -Path "psmm-health-$(Get-Date -Format yyyyMMdd-HHmmss).xml"
    ```

4. **Report issue with:**
    - PowerShell version (`$PSVersionTable.PSVersion`)
    - OS and version
    - Steps to reproduce
    - Error messages and stack traces
    - Diagnostics output from above

---

## FAQ

**Q: Can I use PSmediaManager on macOS or Linux?**

A: Yes, PowerShell 7.5.4+ supports macOS and Linux. However, some features like digiKam integration may require additional setup. See [Development](development.md) for platform-specific notes.

**Q: Is it safe to move storage drives while PSmediaManager is running?**

A: No. Always stop the application before moving drives, then re-scan storage configuration.

**Q: Can I run multiple projects simultaneously?**

A: Yes, but each project requires its own port allocation. Use `Get-PSmmProjectPorts` to avoid conflicts.

**Q: How do I uninstall PSmediaManager?**

A: Remove the installation folder and delete `$env:APPDATA\PSmediaManager`. Note: This also removes stored configuration and secrets.

---

## Additional Resources

- [Architecture Documentation](architecture.md) - System design and component overview
- [Configuration Guide](configuration.md) - Detailed configuration options
- [Development Guide](development.md) - Setup for contributors
- [API Reference](api.md) - Complete public function documentation
