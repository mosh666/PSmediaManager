<#
.SYNOPSIS
    Interface definitions for PSmediaManager application.

.DESCRIPTION
    Provides interface contracts for dependency injection and testability.
    PowerShell doesn't have native interface support, so we use abstract base classes.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.1.0
#>

using namespace System
using namespace System.IO

#region Core Interfaces

<#
.SYNOPSIS
    Interface for path management.
#>
class IPathProvider {
    [string] GetPath([string]$pathKey) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [bool] EnsurePathExists([string]$path) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [string] CombinePath([string[]]$paths) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }
}

#endregion Core Interfaces

#region System Service Interfaces

<#
.SYNOPSIS
    Interface for file system operations.
    Provides testable abstraction over file system access.
#>
class IFileSystemService {
    [bool] TestPath([string]$path) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] NewItem([string]$path, [string]$itemType) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [string] GetContent([string]$path) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] SetContent([string]$path, [string]$content) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object[]] GetChildItem([string]$path, [string]$filter, [string]$itemType, [bool]$recurse = $false) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] RemoveItem([string]$path, [bool]$recurse) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] CopyItem([string]$source, [string]$destination) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] MoveItem([string]$source, [string]$destination) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] GetItemProperty([string]$path) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] ExtractZip([string]$zipPath, [string]$destinationPath, [bool]$overwrite) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }
}

<#
.SYNOPSIS
    Interface for environment variable operations.
    Provides testable abstraction over environment access.
#>
class IEnvironmentService {
    [string] GetVariable([string]$name) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] SetVariable([string]$name, [string]$value, [string]$scope) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [string[]] GetPathEntries() {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] AddPathEntry([string]$path, [bool]$persistUser = $false) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] RemovePathEntry([string]$path, [bool]$persistUser = $false) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] AddPathEntries([string[]]$paths, [bool]$persistUser = $false) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] RemovePathEntries([string[]]$paths, [bool]$persistUser = $false) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [string] GetCurrentDirectory() {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [string] GetUserName() {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [string] GetComputerName() {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }
}

<#
.SYNOPSIS
    Interface for HTTP/Web operations.
    Provides testable abstraction over web requests.
#>
class IHttpService {
    [object] InvokeRequest([string]$uri, [hashtable]$headers) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] InvokeWebRequest([string]$uri, [string]$method, [hashtable]$headers, [int]$timeoutSec) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] DownloadFile([string]$uri, [string]$outFile) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] InvokeRestMethod([string]$uri, [string]$method, [hashtable]$headers, [object]$body) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }
}

<#
.SYNOPSIS
    Interface for process execution.
    Provides testable abstraction over external process operations.
#>
class IProcessService {
    [object] StartProcess([string]$filePath, [string[]]$argumentList) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] StartProcessWithInput([string]$filePath, [string[]]$argumentList, [string]$standardInput) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] GetProcess([string]$name) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [bool] TestCommand([string]$command) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] InvokeCommand([string]$command, [string[]]$arguments) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }
}

<#
.SYNOPSIS
    Interface for CIM/WMI operations.
    Provides testable abstraction over CIM instance queries.
#>
class ICimService {
    [object[]] GetInstances([string]$className, [hashtable]$filter) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] GetInstance([string]$className, [hashtable]$keyProperties) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }
}

<#
.SYNOPSIS
    Interface for Git operations.
    Provides testable abstraction over Git commands.
#>
class IGitService {
    [object] GetCurrentBranch([string]$repositoryPath) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] GetLatestTag([string]$repositoryPath) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] GetCommitHash([string]$repositoryPath) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object[]] SearchForPattern([string]$pattern, [string]$filePattern) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [bool] IsRepository([string]$path) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }
}

<#
.SYNOPSIS
    Interface for cryptographic operations.
    Provides testable abstraction over encryption/decryption.
#>
class ICryptoService {
    [SecureString] ConvertToSecureString([string]$plainText) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [string] ConvertFromSecureString([SecureString]$secureString) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [string] ConvertFromSecureStringAsPlainText([SecureString]$secureString) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }
}

<#
.SYNOPSIS
    Interface for storage drive operations.
    Provides testable abstraction over physical disk and volume queries.
#>
class IStorageService {
    [object[]] GetStorageDrives() {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] FindDriveBySerial([string]$serialNumber) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object] FindDriveByLabel([string]$label) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [object[]] GetRemovableDrives() {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }
}

#endregion System Service Interfaces

#region Dependency Injection Container

<#
.SYNOPSIS
    Dependency Injection container for managing service lifecycle and dependencies.

.DESCRIPTION
    Provides centralized service registration and resolution with singleton lifetime management.
    Replaces the previous hashtable-based approach ($global:PSmmServices) with a formal
    container that enforces consistent service lifecycle patterns.

.NOTES
    All services are registered as singletons to ensure consistent state across the application.
    Breaking Change (v0.2.0): Replaced $global:PSmmServices hashtable with ServiceContainer.
#>
class ServiceContainer {
    hidden [hashtable]$_services = @{}
    hidden [hashtable]$_singletons = @{}

    <#
    .SYNOPSIS
        Registers a service with the container as a singleton.
    #>
    [void] RegisterSingleton([string]$name, [object]$instance) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Service name cannot be null or empty")
        }
        if ($null -eq $instance) {
            throw [ArgumentException]::new("Service instance cannot be null")
        }

        $this._singletons[$name] = $instance
        Write-Verbose "[ServiceContainer] Registered singleton: $name"
    }

    <#
    .SYNOPSIS
        Resolves a service by name from the container.
    #>
    [object] Resolve([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new("Service name cannot be null or empty")
        }

        if ($this._singletons.ContainsKey($name)) {
            return $this._singletons[$name]
        }

        throw [InvalidOperationException]::new("Service '$name' is not registered in the container")
    }

    <#
    .SYNOPSIS
        Checks if a service is registered in the container.
    #>
    [bool] Has([string]$name) {
        if ([string]::IsNullOrWhiteSpace($name)) {
            return $false
        }
        return $this._singletons.ContainsKey($name)
    }

    <#
    .SYNOPSIS
        Gets all registered service names.
    #>
    [string[]] GetServiceNames() {
        return @($this._singletons.Keys)
    }

    <#
    .SYNOPSIS
        Gets the count of registered services.
    #>
    [int] Count() {
        return $this._singletons.Count
    }

    <#
    .SYNOPSIS
        Clears all registered services (use with caution).
    #>
    [void] Clear() {
        $this._singletons.Clear()
        Write-Verbose "[ServiceContainer] Cleared all services"
    }
}

#endregion Dependency Injection Container

#region UI / Application Termination Services

<#{
.SYNOPSIS
    Interface for handling fatal errors.

.DESCRIPTION
    This service is the only component allowed to:
    - emit final, user-facing fatal output
    - decide whether to throw (test-safe) or exit (runtime)

    Implementations should be idempotent (only act once).
#>
class IFatalErrorUiService {
    [void] InvokeFatal(
        [string]$Context,
        [string]$Message,
        [object]$ErrorObject,
        [int]$ExitCode,
        [bool]$NonInteractive
    ) {
        throw [NotImplementedException]::new('Method must be implemented by derived class')
    }
}

#endregion UI / Application Termination Services
