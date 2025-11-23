@{
    # Script module or binary module file associated with this manifest
    RootModule = 'PSmm.Logging.psm1'
    
    # Version number of this module
    ModuleVersion = '1.0.0'
    
    # ID used to uniquely identify this module
    GUID = '8fa9f51c-486c-4e02-8366-ec338b5b073a'
    
    # Author of this module
    Author = 'Der Mosh'
    
    # Company or vendor of this module
    CompanyName = ''
    
    # Copyright statement for this module
    Copyright = '(c) 2025 Der Mosh. All rights reserved.'
    
    # Description of the functionality provided by this module
    Description = 'Centralized logging module for PSmediaManager. Provides structured logging with multiple targets (console and file), configurable levels, context-based logging, and log rotation support using the PSLogs framework.'
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.5.4'
    
    # Supported PowerShell editions
    CompatiblePSEditions = @('Core')
    
    # Modules that must be imported into the global environment prior to importing this module
    # PSLogs is loaded dynamically during Initialize-Logging to avoid forcing online installs during module import
    RequiredModules = @()
    
    # Functions to export from this module
    FunctionsToExport = @(
        'Initialize-Logging'
        'Write-PSmmLog'
        'Set-LogContext'
        'Invoke-LogRotation'
    )
    
    # Cmdlets to export from this module
    CmdletsToExport = @()
    
    # Variables to export from this module
    VariablesToExport = @()
    
    # Aliases to export from this module
    AliasesToExport = @()
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for online galleries
            Tags = @('Logging', 'PowerShell', 'Management')
            
            # Prerelease string (empty for stable releases)
            Prerelease = ''
            
            # A URL to an external web site providing more information about this module
            ExternalModuleDependencies = @('PSLogs')
            
            # Release notes of this module
            ReleaseNotes = 'Initial release of PSmediaManager logging module'
        }
    }
}
