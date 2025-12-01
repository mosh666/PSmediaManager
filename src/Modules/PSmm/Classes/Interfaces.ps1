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

    [object[]] GetChildItem([string]$path, [string]$filter, [string]$itemType) {
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

    [void] AddPathEntry([string]$path) {
        throw [NotImplementedException]::new("Method must be implemented by derived class")
    }

    [void] RemovePathEntry([string]$path) {
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
