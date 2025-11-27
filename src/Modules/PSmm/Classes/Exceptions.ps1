<#
.SYNOPSIS
    Custom exception classes for PSmediaManager application.

.DESCRIPTION
    Provides strongly-typed exception classes for better error handling and debugging.
    Each exception type represents a specific error category with rich context information.

    All exceptions inherit from MediaManagerException base class and provide:
    - Detailed error context
    - Stack trace preservation
    - Structured logging support
    - Optional recovery suggestions

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.1.0
#>

using namespace System
using namespace System.Management.Automation
using namespace System.Collections.Generic

#region Exception Classes

<#
.SYNOPSIS
    Base exception for all PSmediaManager exceptions.

.DESCRIPTION
    Provides common functionality for all application exceptions including:
    - Context tracking
    - Timestamp recording
    - Recovery suggestions
    - Error categorization
    - Original error preservation
#>
class MediaManagerException : Exception {
    [string]$Context
    [ErrorRecord]$OriginalError
    [DateTime]$Timestamp
    [string]$RecoverySuggestion
    [Dictionary[string, object]]$AdditionalData

    MediaManagerException([string]$message) : base($message) {
        $this.Context = 'General'
        $this.Timestamp = [DateTime]::Now
        $this.AdditionalData = [Dictionary[string, object]]::new()
    }

    MediaManagerException([string]$message, [string]$context) : base($message) {
        $this.Context = $context
        $this.Timestamp = [DateTime]::Now
        $this.AdditionalData = [Dictionary[string, object]]::new()
    }

    MediaManagerException([string]$message, [Exception]$innerException) : base($message, $innerException) {
        $this.Context = 'General'
        $this.Timestamp = [DateTime]::Now
        $this.AdditionalData = [Dictionary[string, object]]::new()
        if ($innerException -is [ErrorRecord]) {
            $this.OriginalError = $innerException
        }
    }

    MediaManagerException([string]$message, [string]$context, [Exception]$innerException) : base($message, $innerException) {
        $this.Context = $context
        $this.Timestamp = [DateTime]::Now
        $this.AdditionalData = [Dictionary[string, object]]::new()
        if ($innerException -is [ErrorRecord]) {
            $this.OriginalError = $innerException
        }
    }

    [string] GetFullMessage() {
        $msg = "[$($this.Context)] $($this.Message)"
        if ($this.RecoverySuggestion) {
            $msg += "`n  Recovery: $($this.RecoverySuggestion)"
        }
        return $msg
    }

    [void] AddData([string]$key, [object]$value) {
        $this.AdditionalData[$key] = $value
    }

    [object] GetData([string]$key) {
        if ($this.AdditionalData.ContainsKey($key)) {
            return $this.AdditionalData[$key]
        }
        return $null
    }
}

<#
.SYNOPSIS
    Exception thrown when configuration is invalid or cannot be loaded.

.DESCRIPTION
    Provides detailed information about configuration errors including:
    - Configuration file path
    - Invalid keys or values
    - Schema validation errors
#>
class ConfigurationException : MediaManagerException {
    [string]$ConfigPath
    [string]$InvalidKey
    [object]$InvalidValue

    ConfigurationException([string]$message) : base($message, 'Configuration') {
        $this.RecoverySuggestion = 'Check configuration file syntax and ensure all required keys are present.'
    }

    ConfigurationException([string]$message, [string]$configPath) : base($message, 'Configuration') {
        $this.ConfigPath = $configPath
        $this.RecoverySuggestion = "Verify configuration file exists and is readable at: $configPath"
    }

    ConfigurationException([string]$message, [string]$configPath, [Exception]$innerException) : base($message, 'Configuration', $innerException) {
        $this.ConfigPath = $configPath
        $this.RecoverySuggestion = "Check configuration file format and permissions at: $configPath"
    }

    ConfigurationException([string]$message, [string]$configPath, [string]$invalidKey, [object]$invalidValue) : base($message, 'Configuration') {
        $this.ConfigPath = $configPath
        $this.InvalidKey = $invalidKey
        $this.InvalidValue = $invalidValue
        $this.RecoverySuggestion = "Update configuration key '$invalidKey' with a valid value."
    }
}

<#
.SYNOPSIS
    Exception thrown when a required module cannot be loaded.

.DESCRIPTION
    Provides detailed information about module loading failures including:
    - Module name
    - Required version
    - Found version (if applicable)
    - Installation suggestions
#>
class ModuleLoadException : MediaManagerException {
    [string]$ModuleName
    [version]$RequiredVersion
    [version]$FoundVersion

    ModuleLoadException([string]$message, [string]$moduleName) : base($message, 'Module Loading') {
        $this.ModuleName = $moduleName
        $this.RecoverySuggestion = "Install module using: Install-Module -Name $moduleName -Scope CurrentUser"
    }

    ModuleLoadException([string]$message, [string]$moduleName, [version]$requiredVersion) : base($message, 'Module Loading') {
        $this.ModuleName = $moduleName
        $this.RequiredVersion = $requiredVersion
        $this.RecoverySuggestion = "Install required version using: Install-Module -Name $moduleName -MinimumVersion $requiredVersion -Scope CurrentUser"
    }

    ModuleLoadException([string]$message, [string]$moduleName, [Exception]$innerException) : base($message, 'Module Loading', $innerException) {
        $this.ModuleName = $moduleName
        $this.RecoverySuggestion = "Check module is installed and accessible. Use: Get-Module -ListAvailable $moduleName"
    }

    ModuleLoadException([string]$message, [string]$moduleName, [version]$requiredVersion, [version]$foundVersion) : base($message, 'Module Loading') {
        $this.ModuleName = $moduleName
        $this.RequiredVersion = $requiredVersion
        $this.FoundVersion = $foundVersion
        $this.RecoverySuggestion = "Update module to version $requiredVersion or higher using: Update-Module -Name $moduleName"
    }
}

<#
.SYNOPSIS
    Exception thrown when a required plugin is not available or invalid.

.DESCRIPTION
    Provides detailed information about plugin requirement failures including:
    - Plugin name
    - Required version
    - Found version
    - Download/installation instructions
#>
class PluginRequirementException : MediaManagerException {
    [string]$PluginName
    [version]$RequiredVersion
    [version]$FoundVersion
    [string]$DownloadUrl

    PluginRequirementException([string]$message, [string]$pluginName) : base($message, 'Plugin Requirement') {
        $this.PluginName = $pluginName
        $this.RecoverySuggestion = "Install $pluginName and ensure it's in the PATH or Plugins directory."
    }

    PluginRequirementException([string]$message, [string]$pluginName, [version]$requiredVersion) : base($message, 'Plugin Requirement') {
        $this.PluginName = $pluginName
        $this.RequiredVersion = $requiredVersion
        $this.RecoverySuggestion = "Install $pluginName version $requiredVersion or higher."
    }

    PluginRequirementException([string]$message, [string]$pluginName, [version]$requiredVersion, [version]$foundVersion) : base($message, 'Plugin Requirement') {
        $this.PluginName = $pluginName
        $this.RequiredVersion = $requiredVersion
        $this.FoundVersion = $foundVersion
        $this.RecoverySuggestion = "Upgrade $pluginName from version $foundVersion to $requiredVersion or higher."
    }

    [void] SetDownloadUrl([string]$url) {
        $this.DownloadUrl = $url
        $this.RecoverySuggestion = "Download $($this.PluginName) from: $url"
    }
}

<#
.SYNOPSIS
    Exception thrown when storage operations fail.

.DESCRIPTION
    Provides detailed information about storage errors including:
    - Storage path
    - Storage group
    - Space information
    - Availability status
#>
class StorageException : MediaManagerException {
    [string]$StoragePath
    [string]$StorageGroup
    [long]$RequiredSpaceGB
    [long]$AvailableSpaceGB

    StorageException([string]$message) : base($message, 'Storage') {
        $this.RecoverySuggestion = 'Check storage configuration and drive availability.'
    }

    StorageException([string]$message, [string]$storagePath) : base($message, 'Storage') {
        $this.StoragePath = $storagePath
        $this.RecoverySuggestion = "Verify storage path exists and is accessible: $storagePath"
    }

    StorageException([string]$message, [string]$storagePath, [string]$storageGroup) : base($message, 'Storage') {
        $this.StoragePath = $storagePath
        $this.StorageGroup = $storageGroup
        $this.RecoverySuggestion = "Check storage group '$storageGroup' configuration and mount status."
    }

    StorageException([string]$message, [Exception]$innerException) : base($message, 'Storage', $innerException) {
        $this.RecoverySuggestion = 'Check storage permissions and network connectivity.'
    }

    [void] SetSpaceInfo([long]$requiredGB, [long]$availableGB) {
        $this.RequiredSpaceGB = $requiredGB
        $this.AvailableSpaceGB = $availableGB
        $this.RecoverySuggestion = "Free up space. Required: $($requiredGB)GB, Available: $($availableGB)GB"
    }
}

<#
.SYNOPSIS
    Exception thrown when logging operations fail.

.DESCRIPTION
    Provides detailed information about logging errors including:
    - Log file path
    - Permission issues
    - Disk space problems
#>
class LoggingException : MediaManagerException {
    [string]$LogPath
    [string]$LogLevel

    LoggingException([string]$message) : base($message, 'Logging') {
        $this.RecoverySuggestion = 'Check log directory permissions and disk space.'
    }

    LoggingException([string]$message, [string]$logPath) : base($message, 'Logging') {
        $this.LogPath = $logPath
        $this.RecoverySuggestion = "Verify log path is writable: $logPath"
    }

    LoggingException([string]$message, [Exception]$innerException) : base($message, 'Logging', $innerException) {
        $this.RecoverySuggestion = 'Check logging configuration and file system permissions.'
    }
}

<#
.SYNOPSIS
    Exception thrown when external process execution fails.

.DESCRIPTION
    Provides additional context for process failures including:
    - Process name
    - Exit code
    - Command line arguments
    - Recovery suggestions tailored for process launch issues
#>
class ProcessException : MediaManagerException {
    [string]$ProcessName
    [int]$ExitCode
    [string]$CommandLine

    ProcessException([string]$message) : base($message, 'Process') {
        $this.RecoverySuggestion = 'Verify executable path, permissions, and required dependencies.'
    }

    ProcessException([string]$message, [string]$processName) : base($message, 'Process') {
        $this.ProcessName = $processName
        $this.RecoverySuggestion = "Check process '$processName' exists and is accessible."
    }

    ProcessException([string]$message, [string]$processName, [Exception]$innerException) : base($message, 'Process', $innerException) {
        $this.ProcessName = $processName
        $this.RecoverySuggestion = "Inspect inner exception details for process '$processName'."
    }

    [void] SetExitCode([int]$exitCode) {
        $this.ExitCode = $exitCode
        $this.AddData('ExitCode', $exitCode)
        $this.RecoverySuggestion = "Process exited with code $exitCode. Review logs or enable verbose output."
    }

    [void] SetCommandLine([string]$commandLine) {
        $this.CommandLine = $commandLine
        $this.AddData('CommandLine', $commandLine)
    }
}

<#
.SYNOPSIS
    Exception thrown when project operations fail.

.DESCRIPTION
    Provides detailed information about project errors including:
    - Project name
    - Project path
    - Operation type
    - Dependencies
#>
class ProjectException : MediaManagerException {
    [string]$ProjectName
    [string]$ProjectPath
    [string]$Operation

    ProjectException([string]$message) : base($message, 'Project') {
        $this.RecoverySuggestion = 'Verify project configuration and directory structure.'
    }

    ProjectException([string]$message, [string]$projectName) : base($message, 'Project') {
        $this.ProjectName = $projectName
        $this.RecoverySuggestion = "Check project '$projectName' exists and is configured correctly."
    }

    ProjectException([string]$message, [string]$projectName, [string]$projectPath) : base($message, 'Project') {
        $this.ProjectName = $projectName
        $this.ProjectPath = $projectPath
        $this.RecoverySuggestion = "Verify project path: $projectPath"
    }

    [void] SetOperation([string]$operation) {
        $this.Operation = $operation
        $this.AddData('Operation', $operation)
    }
}

<#
.SYNOPSIS
    Exception thrown when validation fails.

.DESCRIPTION
    Provides detailed information about validation errors including:
    - Property name
    - Invalid value
    - Expected format
    - Validation rules
#>
class ValidationException : MediaManagerException {
    [string]$PropertyName
    [object]$InvalidValue
    [string]$ExpectedFormat
    [string[]]$ValidationRules

    ValidationException([string]$message) : base($message, 'Validation') {
        $this.RecoverySuggestion = 'Provide a valid value according to validation rules.'
    }

    ValidationException([string]$message, [string]$propertyName) : base($message, 'Validation') {
        $this.PropertyName = $propertyName
        $this.RecoverySuggestion = "Check value for property '$propertyName' meets validation requirements."
    }

    ValidationException([string]$message, [string]$propertyName, [object]$invalidValue) : base($message, 'Validation') {
        $this.PropertyName = $propertyName
        $this.InvalidValue = $invalidValue
        $this.RecoverySuggestion = "Property '$propertyName' has invalid value: $invalidValue"
    }

    [void] SetExpectedFormat([string]$format) {
        $this.ExpectedFormat = $format
        $this.RecoverySuggestion = "Property '$($this.PropertyName)' must match format: $format"
    }

    [void] AddValidationRule([string]$rule) {
        if ($null -eq $this.ValidationRules) {
            $this.ValidationRules = @()
        }
        $this.ValidationRules += $rule
    }
}

#endregion Exception Classes

#endregion Exception Classes

#region Error Handling Helpers

<#
.SYNOPSIS
    Creates a properly formatted ErrorRecord for PowerShell cmdlets.

.DESCRIPTION
    Helper function to create well-formed ErrorRecord objects with proper categorization
    and context. Can be used with $PSCmdlet.ThrowTerminatingError() or $PSCmdlet.WriteError().

.PARAMETER Exception
    The exception object to wrap in the ErrorRecord.

.PARAMETER ErrorId
    A unique identifier for the error.

.PARAMETER Category
    The ErrorCategory that best describes the error.

.PARAMETER TargetObject
    The object that was being processed when the error occurred.

.EXAMPLE
    $errorRecord = New-MediaManagerErrorRecord -Exception $ex -ErrorId 'ConfigNotFound' -Category ObjectNotFound
    $PSCmdlet.ThrowTerminatingError($errorRecord)

.EXAMPLE
    $ex = [ConfigurationException]::new("Invalid configuration", $configPath)
    $errorRecord = New-MediaManagerErrorRecord -Exception $ex -ErrorId 'InvalidConfig' -Category InvalidData
    $PSCmdlet.WriteError($errorRecord)
#>
function New-MediaManagerErrorRecord {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This function creates and returns an ErrorRecord object without modifying system state')]
    [CmdletBinding()]
    [OutputType([ErrorRecord])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [Exception]$Exception,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ErrorId,

        [Parameter()]
        [ValidateNotNull()]
        [ErrorCategory]$Category = [ErrorCategory]::NotSpecified,

        [Parameter()]
        [AllowNull()]
        [object]$TargetObject = $null
    )

    process {
        return [ErrorRecord]::new(
            $Exception,
            $ErrorId,
            $Category,
            $TargetObject
        )
    }
}

<#
.SYNOPSIS
    Converts a MediaManagerException to a formatted error message.

.DESCRIPTION
    Generates a user-friendly error message from a MediaManagerException,
    including context, recovery suggestions, and additional data.

.PARAMETER Exception
    The MediaManagerException to format.

.PARAMETER IncludeStackTrace
    Include the stack trace in the output.

.PARAMETER IncludeAdditionalData
    Include additional data dictionary in the output.

.EXAMPLE
    $message = Format-MediaManagerException -Exception $ex
    Write-Error $message
#>
function Format-MediaManagerException {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [MediaManagerException]$Exception,

        [Parameter()]
        [switch]$IncludeStackTrace,

        [Parameter()]
        [switch]$IncludeAdditionalData
    )

    process {
        $lines = [List[string]]::new()

        # Main error message
        $lines.Add("[$($Exception.Context)] $($Exception.Message)")

        # Recovery suggestion
        if ($Exception.RecoverySuggestion) {
            $lines.Add("  Recovery: $($Exception.RecoverySuggestion)")
        }

        # Additional data
        if ($IncludeAdditionalData -and $Exception.AdditionalData.Count -gt 0) {
            $lines.Add("  Additional Data:")
            foreach ($key in $Exception.AdditionalData.Keys) {
                $lines.Add("    $key = $($Exception.AdditionalData[$key])")
            }
        }

        # Stack trace
        if ($IncludeStackTrace -and $Exception.StackTrace) {
            $lines.Add("  Stack Trace:")
            $lines.Add("    $($Exception.StackTrace)")
        }

        return $lines -join "`n"
    }
}

#endregion Error Handling Helpers
