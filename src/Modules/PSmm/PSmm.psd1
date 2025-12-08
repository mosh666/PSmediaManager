@{
    # Script module or binary module file associated with this manifest
    RootModule = 'PSmm.psm1'

    # Version number of this module (updated by Update-ModuleVersions.ps1 from Git)
    ModuleVersion = '0.1.1'

    # ID used to uniquely identify this module
    GUID = '0c513322-1f25-46c8-b8b5-e9115ec18f07'

    # Author of this module
    Author = 'Der Mosh'

    # Company or vendor of this module
    CompanyName = ''

    # Copyright statement for this module
    Copyright = '(c) 2025 Der Mosh. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Core module for bootstrapping and managing the PSmediaManager application. Provides essential functionality for application initialization, directory management, environment configuration, and storage management.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.5.4'

    # Supported PowerShell editions
    CompatiblePSEditions = @('Core')

    # Scripts that are run in the caller's environment prior to importing this module
    ScriptsToProcess = @(
        'Classes\Interfaces.ps1'
        'Classes\Exceptions.ps1'
        'Classes\Services\FileSystemService.ps1'
        'Classes\Services\EnvironmentService.ps1'
        'Classes\Services\HttpService.ps1'
        'Classes\Services\CimService.ps1'
        'Classes\Services\GitService.ps1'
        'Classes\Services\ProcessService.ps1'
        'Classes\Services\CryptoService.ps1'
        'Classes\Services\StorageService.ps1'
        'Classes\AppConfiguration.ps1'
        'Classes\ConfigValidator.ps1'
        'Classes\AppConfigurationBuilder.ps1'
    )

    # Functions to export from this module (modern public API only)
    FunctionsToExport = @(
        'Invoke-PSmm'
        'New-CustomFileName'
        'New-DirectoriesFromHashtable'
        'Confirm-Storage'
        'Get-StorageDrive'
        'Invoke-StorageWizard'
        'Invoke-ManageStorage'
        'Remove-StorageGroup'
        'Test-DuplicateSerial'
        'Show-StorageInfo'
        'Export-SafeConfiguration'
        'Get-PSmmHealth'
        # KeePassXC Secret Management Functions (Public API)
        'Get-SystemSecret'
        'Initialize-SystemVault'
        'Save-SystemSecret'
        # Drive Root Launcher
        'New-DriveRootLauncher'
        # Host output helper exported so scripts can call centralized output
        'Write-PSmmHost'
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
            Tags = @('MediaManagement', 'PowerShell', 'Automation', 'Plugins', 'Configuration')

            # Prerelease string (empty for stable releases)
            Prerelease = ''

            # License URI for this module
            LicenseUri = ''

            # Project site URI for this module
            ProjectUri = ''

            # Icon URI for this module
            IconUri = ''

            # Release notes of this module
            ReleaseNotes = @'
## 1.0.0
- Initial release of PSmediaManager core module
- Application bootstrapping and initialization
- Directory structure management
- Custom filename generation
- Storage management functionality
- Environment path management
'@
        }
    }
}
