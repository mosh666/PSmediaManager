<#
.SYNOPSIS
    Configuration validation and security hardening for PSmediaManager.

.DESCRIPTION
    Provides comprehensive validation capabilities:
    - Type checking and range validation
    - Path existence and accessibility validation
    - Schema validation for PSD1 configuration files
    - Config drift detection (runtime vs. disk comparison)
    - Security checks for sensitive data

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
    Phase: 10 - Configuration Validation & Security Hardening
#>

using namespace System
using namespace System.IO
using namespace System.Collections.Generic

#Requires -Version 7.5.4

<#
.SYNOPSIS
    Validation result entry containing issue details.
#>
class ValidationIssue {
    [string]$Severity      # 'Error', 'Warning', 'Info'
    [string]$Category      # 'Type', 'Range', 'Path', 'Schema', 'Security'
    [string]$Property      # Property path (e.g., 'Storage.Groups.1.Master.Serial')
    [string]$Message       # Human-readable description
    [object]$ActualValue   # Current value that failed validation
    [object]$ExpectedValue # Expected value or constraint

    ValidationIssue([string]$severity, [string]$category, [string]$property, [string]$message) {
        $this.Severity = $severity
        $this.Category = $category
        $this.Property = $property
        $this.Message = $message
    }
}

<#
.SYNOPSIS
    Schema definition for configuration validation.
#>
class ConfigSchema {
    [string]$PropertyPath
    [string]$ExpectedType  # 'String', 'Int', 'Boolean', 'Hashtable', 'Array', etc.
    [bool]$Required
    [object]$MinValue      # For numeric types
    [object]$MaxValue      # For numeric types
    [string]$Pattern       # Regex pattern for string validation
    [scriptblock]$CustomValidator  # Custom validation logic

    ConfigSchema([string]$path, [string]$type, [bool]$required) {
        $this.PropertyPath = $path
        $this.ExpectedType = $type
        $this.Required = $required
    }
}

<#
.SYNOPSIS
    Configuration drift comparison result.
#>
class ConfigDrift {
    [string]$PropertyPath
    [object]$RuntimeValue
    [object]$DiskValue
    [bool]$IsDifferent
    [string]$DriftType     # 'Modified', 'Added', 'Removed'

    ConfigDrift([string]$path, [object]$runtime, [object]$disk, [bool]$different, [string]$type) {
        $this.PropertyPath = $path
        $this.RuntimeValue = $runtime
        $this.DiskValue = $disk
        $this.IsDifferent = $different
        $this.DriftType = $type
    }
}

<#
.SYNOPSIS
    Main configuration validator class.
#>
class ConfigValidator {
    hidden [List[ConfigSchema]]$_schemas
    hidden [List[ValidationIssue]]$_issues
    hidden [object]$_fileSystem
    hidden [bool]$_useDefaultSchemas

    ConfigValidator() {
        $this._schemas = [List[ConfigSchema]]::new()
        $this._issues = [List[ValidationIssue]]::new()
        $this._useDefaultSchemas = $true
        $this.InitializeDefaultSchemas()
    }

    ConfigValidator([object]$fileSystem) {
        $this._schemas = [List[ConfigSchema]]::new()
        $this._issues = [List[ValidationIssue]]::new()
        $this._fileSystem = $fileSystem
        $this._useDefaultSchemas = $true
        $this.InitializeDefaultSchemas()
    }

    ConfigValidator([bool]$useDefaultSchemas) {
        $this._schemas = [List[ConfigSchema]]::new()
        $this._issues = [List[ValidationIssue]]::new()
        $this._useDefaultSchemas = $useDefaultSchemas
        if ($useDefaultSchemas) {
            $this.InitializeDefaultSchemas()
        }
    }

    ConfigValidator([object]$fileSystem, [bool]$useDefaultSchemas) {
        $this._schemas = [List[ConfigSchema]]::new()
        $this._issues = [List[ValidationIssue]]::new()
        $this._fileSystem = $fileSystem
        $this._useDefaultSchemas = $useDefaultSchemas
        if ($useDefaultSchemas) {
            $this.InitializeDefaultSchemas()
        }
    }

    <#
    .SYNOPSIS
        Initialize default validation schemas for known config properties.
    #>
    hidden [void] InitializeDefaultSchemas() {
        # App metadata
        $this.AddSchema([ConfigSchema]::new('DisplayName', 'String', $true))
        $this.AddSchema([ConfigSchema]::new('InternalName', 'String', $true))
        $this.AddSchema([ConfigSchema]::new('AppVersion', 'String', $false))

        # Paths
        $this.AddSchema([ConfigSchema]::new('Paths.Root', 'String', $true))
        $this.AddSchema([ConfigSchema]::new('Paths.RepositoryRoot', 'String', $true))
        $this.AddSchema([ConfigSchema]::new('Paths.Log', 'String', $true))

        # UI configuration
        $schema = [ConfigSchema]::new('UI.Width', 'Int', $false)
        $schema.MinValue = 80
        $schema.MaxValue = 300
        $this.AddSchema($schema)

        # Storage groups
        $this.AddSchema([ConfigSchema]::new('Storage', 'Dictionary', $false))
    }

    <#
    .SYNOPSIS
        Add a schema definition for validation.
    #>
    [void] AddSchema([ConfigSchema]$schema) {
        if ($null -eq $schema) {
            throw [ArgumentNullException]::new('schema')
        }
        $this._schemas.Add($schema)
    }

    <#
    .SYNOPSIS
        Validate an AppConfiguration object.
    #>
    [ValidationIssue[]] ValidateConfiguration([object]$config) {
        if ($null -eq $config) {
            throw [ArgumentNullException]::new('config')
        }

        $this._issues.Clear()

        # Validate against schemas
        foreach ($schema in $this._schemas) {
            $this.ValidateProperty($config, $schema)
        }

        # Additional validations
        $this.ValidatePaths($config)
        $this.ValidateSecuritySettings($config)
        $this.ValidateStorageConfiguration($config)

        return $this._issues.ToArray()
    }

    <#
    .SYNOPSIS
        Validate a single property against its schema.
    #>
    hidden [void] ValidateProperty([object]$config, [ConfigSchema]$schema) {
        $pathParts = $schema.PropertyPath -split '\.'
        $current = $config
        $found = $true

        foreach ($part in $pathParts) {
            if ($null -eq $current) {
                $found = $false
                break
            }

            if ($current -is [System.Collections.IDictionary]) {
                $hasKey = $false
                try { $hasKey = [bool]$current.ContainsKey($part) } catch { $hasKey = $false }
                if (-not $hasKey) {
                    try { $hasKey = [bool]$current.Contains($part) } catch { $hasKey = $false }
                }
                if (-not $hasKey) {
                    try {
                        foreach ($k in $current.Keys) {
                            if ($k -eq $part) { $hasKey = $true; break }
                        }
                    }
                    catch {
                        $hasKey = $false
                    }
                }

                if (-not $hasKey) {
                    $found = $false
                    break
                }

                $current = $current[$part]
            }
            else {
                $prop = $current.PSObject.Properties[$part]
                if ($null -eq $prop) {
                    $found = $false
                    break
                }
                $current = $prop.Value
            }
        }

        # Check if required property is missing
        if (-not $found) {
            if ($schema.Required) {
                $issue = [ValidationIssue]::new('Error', 'Schema', $schema.PropertyPath, "Required property is missing")
                $this._issues.Add($issue)
            }
            return
        }

        # Skip validation for null values unless required
        if ($null -eq $current) {
            if ($schema.Required) {
                $issue = [ValidationIssue]::new('Error', 'Type', $schema.PropertyPath, "Required property has null value")
                $this._issues.Add($issue)
            }
            return
        }

        # Type validation
        if (-not [string]::IsNullOrWhiteSpace($schema.ExpectedType)) {
            $valid = $this.ValidateType($current, $schema.ExpectedType)
            if (-not $valid) {
                $actualType = if ($null -eq $current) { 'null' } else { $current.GetType().Name }
                $issue = [ValidationIssue]::new('Error', 'Type', $schema.PropertyPath, "Expected type '$($schema.ExpectedType)' but got '$actualType'")
                $issue.ActualValue = $current
                $issue.ExpectedValue = $schema.ExpectedType
                $this._issues.Add($issue)
                return
            }
        }

        # Range validation for numeric types
        if ($null -ne $schema.MinValue -or $null -ne $schema.MaxValue) {
            if ($current -is [int] -or $current -is [double] -or $current -is [long]) {
                if ($null -ne $schema.MinValue -and $current -lt $schema.MinValue) {
                    $issue = [ValidationIssue]::new('Error', 'Range', $schema.PropertyPath, "Value $current is below minimum $($schema.MinValue)")
                    $issue.ActualValue = $current
                    $issue.ExpectedValue = "≥ $($schema.MinValue)"
                    $this._issues.Add($issue)
                }
                if ($null -ne $schema.MaxValue -and $current -gt $schema.MaxValue) {
                    $issue = [ValidationIssue]::new('Error', 'Range', $schema.PropertyPath, "Value $current exceeds maximum $($schema.MaxValue)")
                    $issue.ActualValue = $current
                    $issue.ExpectedValue = "≤ $($schema.MaxValue)"
                    $this._issues.Add($issue)
                }
            }
        }

        # Pattern validation for strings
        if (-not [string]::IsNullOrWhiteSpace($schema.Pattern) -and $current -is [string]) {
            if ($current -notmatch $schema.Pattern) {
                $issue = [ValidationIssue]::new('Error', 'Pattern', $schema.PropertyPath, "Value does not match required pattern: $($schema.Pattern)")
                $issue.ActualValue = $current
                $this._issues.Add($issue)
            }
        }

        # Custom validator
        if ($null -ne $schema.CustomValidator) {
            try {
                $result = & $schema.CustomValidator $current
                if ($result -is [bool] -and -not $result) {
                    $issue = [ValidationIssue]::new('Error', 'Custom', $schema.PropertyPath, "Custom validation failed")
                    $issue.ActualValue = $current
                    $this._issues.Add($issue)
                }
            }
            catch {
                $issue = [ValidationIssue]::new('Warning', 'Custom', $schema.PropertyPath, "Custom validator threw exception: $_")
                $this._issues.Add($issue)
            }
        }
    }

    <#
    .SYNOPSIS
        Validate type compatibility.
    #>
    hidden [bool] ValidateType([object]$value, [string]$expectedType) {
        if ($null -eq $value) {
            return $false
        }

        # PowerShell class methods require explicit return after switch
        $result = switch ($expectedType) {
            'String' { $value -is [string] }
            'Int' { $value -is [int] -or $value -is [long] }
            'Boolean' { $value -is [bool] }
            'Hashtable' { $value -is [hashtable] }
            'Dictionary' { ($value -is [System.Collections.IDictionary]) -and ($value -isnot [hashtable]) }
            'Array' { $value -is [array] }
            'Double' { $value -is [double] -or $value -is [decimal] }
            default { $true }
        }
        return $result
    }

    <#
    .SYNOPSIS
        Validate path properties exist and are accessible.
    #>
    hidden [void] ValidatePaths([object]$config) {
        # Safely check if Paths property exists
        $pathsProperty = $config.PSObject.Properties['Paths']
        if ($null -eq $pathsProperty -or $null -eq $pathsProperty.Value) {
            return
        }

        $paths = $pathsProperty.Value

        $rootValue = $null
        $repoValue = $null
        $logValue = $null

        if ($paths -is [System.Collections.IDictionary]) {
            foreach ($name in @('Root', 'RepositoryRoot', 'Log')) {
                $hasKey = $false
                try { $hasKey = [bool]$paths.ContainsKey($name) } catch { $hasKey = $false }
                if (-not $hasKey) { try { $hasKey = [bool]$paths.Contains($name) } catch { $hasKey = $false } }
                if (-not $hasKey) {
                    try {
                        foreach ($k in $paths.Keys) {
                            if ($k -eq $name) { $hasKey = $true; break }
                        }
                    }
                    catch { $hasKey = $false }
                }
                if ($hasKey) {
                    switch ($name) {
                        'Root' { $rootValue = $paths[$name] }
                        'RepositoryRoot' { $repoValue = $paths[$name] }
                        'Log' { $logValue = $paths[$name] }
                    }
                }
            }
        }
        else {
            $rootProp = $paths.PSObject.Properties['Root']
            if ($null -ne $rootProp) { $rootValue = $rootProp.Value }

            $repoProp = $paths.PSObject.Properties['RepositoryRoot']
            if ($null -ne $repoProp) { $repoValue = $repoProp.Value }

            $logProp = $paths.PSObject.Properties['Log']
            if ($null -ne $logProp) { $logValue = $logProp.Value }
        }

        $pathsToCheck = @(
            @{ Name = 'Root'; Value = $rootValue; MustExist = $false },
            @{ Name = 'RepositoryRoot'; Value = $repoValue; MustExist = $true },
            @{ Name = 'Log'; Value = $logValue; MustExist = $false }
        )

        foreach ($pathCheck in $pathsToCheck) {
            $pathValue = $pathCheck.Value

            if ([string]::IsNullOrWhiteSpace($pathValue)) {
                if ($pathCheck.MustExist) {
                    $issue = [ValidationIssue]::new('Error', 'Path', "Paths.$($pathCheck.Name)", "Path is null or empty")
                    $this._issues.Add($issue)
                }
                continue
            }

            if (-not [Path]::IsPathRooted($pathValue)) {
                $issue = [ValidationIssue]::new('Warning', 'Path', "Paths.$($pathCheck.Name)", "Path is not absolute: $pathValue")
                $issue.ActualValue = $pathValue
                $this._issues.Add($issue)
            }

            # Check existence using FileSystem service if available
            $exists = $false
            if ($null -ne $this._fileSystem -and ($this._fileSystem | Get-Member -Name 'TestPath' -ErrorAction SilentlyContinue)) {
                try {
                    $exists = $this._fileSystem.TestPath($pathValue)
                }
                catch {
                    # Fallback to Test-Path
                    $exists = Test-Path -Path $pathValue -ErrorAction SilentlyContinue
                }
            }
            else {
                $exists = Test-Path -Path $pathValue -ErrorAction SilentlyContinue
            }

            if ($pathCheck.MustExist -and -not $exists) {
                $issue = [ValidationIssue]::new('Error', 'Path', "Paths.$($pathCheck.Name)", "Required path does not exist: $pathValue")
                $issue.ActualValue = $pathValue
                $this._issues.Add($issue)
            }
        }
    }

    <#
    .SYNOPSIS
        Validate security-related settings.
    #>
    hidden [void] ValidateSecuritySettings([object]$config) {
        # Check for sensitive data exposure - safely access Secrets property
        $secretsProperty = $config.PSObject.Properties['Secrets']
        if ($null -ne $secretsProperty -and $null -ne $secretsProperty.Value) {
            if ($secretsProperty.Value -is [System.Collections.IDictionary]) {
                foreach ($key in $secretsProperty.Value.Keys) {
                    $value = $secretsProperty.Value[$key]
                    if ($value -is [string] -and $value.Length -gt 0 -and $value -notmatch '^\*+$') {
                        $issue = [ValidationIssue]::new('Warning', 'Security', "Secrets.$key", "Plaintext secret detected (should be SecureString or masked)")
                        $this._issues.Add($issue)
                    }
                }
            }
        }

        # Validate KeePassXC vault configuration - safely access Vault property
        $vaultProperty = $config.PSObject.Properties['Vault']
        if ($null -ne $vaultProperty -and $null -ne $vaultProperty.Value) {
            $vault = $vaultProperty.Value

            # Get Database value from hashtable or PSObject
            $vaultPath = $null
            if ($vault -is [System.Collections.IDictionary]) {
                $hasDb = $false
                try { $hasDb = [bool]$vault.ContainsKey('Database') } catch { $hasDb = $false }
                if (-not $hasDb) { try { $hasDb = [bool]$vault.Contains('Database') } catch { $hasDb = $false } }
                if (-not $hasDb) {
                    try {
                        foreach ($k in $vault.Keys) {
                            if ($k -eq 'Database') { $hasDb = $true; break }
                        }
                    }
                    catch { $hasDb = $false }
                }
                if ($hasDb) { $vaultPath = $vault['Database'] }
            }
            else {
                $vaultDbProperty = $vault.PSObject.Properties['Database']
                $vaultPath = if ($null -ne $vaultDbProperty) { $vaultDbProperty.Value } else { $null }
            }

            if (-not [string]::IsNullOrWhiteSpace($vaultPath)) {
                $exists = Test-Path -Path $vaultPath -ErrorAction SilentlyContinue
                if (-not $exists) {
                    $issue = [ValidationIssue]::new('Warning', 'Security', 'Vault.Database', "KeePassXC database not found: $vaultPath")
                    $issue.ActualValue = $vaultPath
                    $this._issues.Add($issue)
                }
            }
        }
    }

    <#
    .SYNOPSIS
        Validate storage configuration.
    #>
    hidden [void] ValidateStorageConfiguration([object]$config) {
        # Safely access Storage property
        $storageProperty = $config.PSObject.Properties['Storage']
        if ($null -eq $storageProperty -or $null -eq $storageProperty.Value -or $storageProperty.Value.Count -eq 0) {
            return
        }

        foreach ($groupKey in $storageProperty.Value.Keys) {
            $group = $storageProperty.Value[$groupKey]

            if ($null -eq $group) {
                continue
            }

            # Validate Master configuration
            $master = $null
            if ($group -is [System.Collections.IDictionary]) {
                $hasMaster = $false
                try { $hasMaster = [bool]$group.ContainsKey('Master') } catch { $hasMaster = $false }
                if (-not $hasMaster) { try { $hasMaster = [bool]$group.Contains('Master') } catch { $hasMaster = $false } }
                if (-not $hasMaster) {
                    try {
                        foreach ($k in $group.Keys) {
                            if ($k -eq 'Master') { $hasMaster = $true; break }
                        }
                    }
                    catch { $hasMaster = $false }
                }
                if ($hasMaster) { $master = $group['Master'] }
            }
            else {
                $masterProperty = $group.PSObject.Properties['Master']
                if ($null -ne $masterProperty) { $master = $masterProperty.Value }
            }

            if ($null -ne $master) {
                $serialValue = $null
                if ($master -is [System.Collections.IDictionary]) {
                    $hasSerial = $false
                    try { $hasSerial = [bool]$master.ContainsKey('Serial') } catch { $hasSerial = $false }
                    if (-not $hasSerial) { try { $hasSerial = [bool]$master.Contains('Serial') } catch { $hasSerial = $false } }
                    if (-not $hasSerial) {
                        try {
                            foreach ($k in $master.Keys) {
                                if ($k -eq 'Serial') { $hasSerial = $true; break }
                            }
                        }
                        catch { $hasSerial = $false }
                    }
                    if ($hasSerial) { $serialValue = $master['Serial'] }
                }
                else {
                    $serialProperty = $master.PSObject.Properties['Serial']
                    if ($null -ne $serialProperty) { $serialValue = $serialProperty.Value }
                }

                if ([string]::IsNullOrWhiteSpace([string]$serialValue)) {
                    $issue = [ValidationIssue]::new('Warning', 'Storage', "Storage.$groupKey.Master.Serial", "Master drive serial is empty")
                    $this._issues.Add($issue)
                }
            }

            # Validate Backup configuration
            $backup = $null
            if ($group -is [System.Collections.IDictionary]) {
                $hasBackup = $false
                try { $hasBackup = [bool]$group.ContainsKey('Backup') } catch { $hasBackup = $false }
                if (-not $hasBackup) { try { $hasBackup = [bool]$group.Contains('Backup') } catch { $hasBackup = $false } }
                if (-not $hasBackup) {
                    try {
                        foreach ($k in $group.Keys) {
                            if ($k -eq 'Backup') { $hasBackup = $true; break }
                        }
                    }
                    catch { $hasBackup = $false }
                }
                if ($hasBackup) { $backup = $group['Backup'] }
            }
            else {
                $backupProperty = $group.PSObject.Properties['Backup']
                if ($null -ne $backupProperty) { $backup = $backupProperty.Value }
            }

            if ($null -ne $backup) {
                $serialValue = $null
                if ($backup -is [System.Collections.IDictionary]) {
                    $hasSerial = $false
                    try { $hasSerial = [bool]$backup.ContainsKey('Serial') } catch { $hasSerial = $false }
                    if (-not $hasSerial) { try { $hasSerial = [bool]$backup.Contains('Serial') } catch { $hasSerial = $false } }
                    if (-not $hasSerial) {
                        try {
                            foreach ($k in $backup.Keys) {
                                if ($k -eq 'Serial') { $hasSerial = $true; break }
                            }
                        }
                        catch { $hasSerial = $false }
                    }
                    if ($hasSerial) { $serialValue = $backup['Serial'] }
                }
                else {
                    $serialProperty = $backup.PSObject.Properties['Serial']
                    if ($null -ne $serialProperty) { $serialValue = $serialProperty.Value }
                }

                if ([string]::IsNullOrWhiteSpace([string]$serialValue)) {
                    $issue = [ValidationIssue]::new('Warning', 'Storage', "Storage.$groupKey.Backup.Serial", "Backup drive serial is empty")
                    $this._issues.Add($issue)
                }
            }
        }
    }

    <#
    .SYNOPSIS
        Detect configuration drift between runtime and disk.
    #>
    [ConfigDrift[]] DetectDrift([object]$runtimeConfig, [string]$diskConfigPath) {
        if ($null -eq $runtimeConfig) {
            throw [ArgumentNullException]::new('runtimeConfig')
        }

        if ([string]::IsNullOrWhiteSpace($diskConfigPath)) {
            throw [ArgumentException]::new('Disk config path cannot be null or empty', 'diskConfigPath')
        }

        $exists = if ($null -ne $this._fileSystem) {
            $this._fileSystem.TestPath($diskConfigPath)
        } else {
            Test-Path -Path $diskConfigPath
        }

        if (-not $exists) {
            throw [FileNotFoundException]::new("Configuration file not found: $diskConfigPath")
        }

        # Load disk config
        $diskConfig = $null
        try {
            $diskConfig = Import-PowerShellDataFile -Path $diskConfigPath -ErrorAction Stop
        }
        catch {
            throw [InvalidOperationException]::new("Failed to load configuration from disk: $_", $_.Exception)
        }

        # Compare configurations
        $drifts = [List[ConfigDrift]]::new()
        $this.CompareObjects($runtimeConfig, $diskConfig, '', $drifts)

        return $drifts.ToArray()
    }

    <#
    .SYNOPSIS
        Recursively compare two configuration objects.
    #>
    hidden [void] CompareObjects([object]$runtime, [object]$disk, [string]$path, [List[ConfigDrift]]$drifts) {
        # Handle null cases
        if ($null -eq $runtime -and $null -eq $disk) {
            return
        }

        if ($null -eq $runtime) {
            $drift = [ConfigDrift]::new($path, $null, $disk, $true, 'Removed')
            $drifts.Add($drift)
            return
        }

        if ($null -eq $disk) {
            $drift = [ConfigDrift]::new($path, $runtime, $null, $true, 'Added')
            $drifts.Add($drift)
            return
        }

        # Compare based on type
        if ($runtime -is [hashtable] -and $disk -is [hashtable]) {
            $allKeys = @($runtime.Keys) + @($disk.Keys) | Select-Object -Unique
            foreach ($key in $allKeys) {
                $newPath = if ([string]::IsNullOrWhiteSpace($path)) { $key } else { "$path.$key" }
                $runtimeValue = if ($runtime.ContainsKey($key)) { $runtime[$key] } else { $null }
                $diskValue = if ($disk.ContainsKey($key)) { $disk[$key] } else { $null }
                $this.CompareObjects($runtimeValue, $diskValue, $newPath, $drifts)
            }
        }
        elseif ($runtime -is [AppConfiguration] -and $disk -is [hashtable]) {
            # Compare AppConfiguration properties with hashtable
            foreach ($prop in $runtime.PSObject.Properties) {
                $key = $prop.Name
                $newPath = if ([string]::IsNullOrWhiteSpace($path)) { $key } else { "$path.$key" }
                $runtimeValue = $prop.Value
                $diskValue = if ($disk.ContainsKey($key)) { $disk[$key] } else { $null }
                $this.CompareObjects($runtimeValue, $diskValue, $newPath, $drifts)
            }
        }
        else {
            # Scalar comparison
            $different = $false
            if ($runtime -is [string] -and $disk -is [string]) {
                $different = $runtime -cne $disk
            }
            elseif ($runtime -is [int] -or $runtime -is [double] -or $runtime -is [long]) {
                $different = $runtime -ne $disk
            }
            elseif ($runtime -is [bool] -and $disk -is [bool]) {
                $different = $runtime -ne $disk
            }
            else {
                # Generic comparison
                $different = $runtime -ne $disk
            }

            if ($different) {
                $drift = [ConfigDrift]::new($path, $runtime, $disk, $true, 'Modified')
                $drifts.Add($drift)
            }
        }
    }

    <#
    .SYNOPSIS
        Get all validation issues.
    #>
    [ValidationIssue[]] GetIssues() {
        return $this._issues.ToArray()
    }

    <#
    .SYNOPSIS
        Get issues filtered by severity.
    #>
    [ValidationIssue[]] GetIssuesBySeverity([string]$severity) {
        $filtered = @($this._issues | Where-Object { $_.Severity -eq $severity })
        return $filtered
    }

    <#
    .SYNOPSIS
        Check if validation has any errors.
    #>
    [bool] HasErrors() {
        $errors = @($this._issues | Where-Object { $_.Severity -eq 'Error' })
        return $errors.Count -gt 0
    }

    <#
    .SYNOPSIS
        Clear all validation issues.
    #>
    [void] Clear() {
        $this._issues.Clear()
    }
}
