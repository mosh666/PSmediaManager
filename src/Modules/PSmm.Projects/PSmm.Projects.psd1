@{
    # Script module or binary module file associated with this manifest
    RootModule = 'PSmm.Projects.psm1'

    # Version number of this module (updated by Update-ModuleVersions.ps1 from Git)
    ModuleVersion = '0.1.1'

    # ID used to uniquely identify this module
    GUID = 'a5b9e79d-6061-4bc9-8e4c-89a9e1004062'

    # Author of this module
    Author = 'Der Mosh'

    # Company or vendor of this module
    CompanyName = ''

    # Copyright statement for this module
    Copyright = '(c) 2025 Der Mosh. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Project management module for PSmediaManager. Provides functions for creating, selecting, and managing media projects with directory structure setup, database initialization, and project configuration management.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.5.4'

    # Supported PowerShell editions
    CompatiblePSEditions = @('Core')

    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules = @()

    # Functions to export from this module
    FunctionsToExport = @(
        'Clear-PSmmProjectRegistry'
        'Get-PSmmProjects'
        'New-PSmmProject'
        'Select-PSmmProject'
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
            Tags = @('ProjectManagement', 'PowerShell', 'MediaManagement')

            # Prerelease string (empty for stable releases)
            Prerelease = ''

            # Release notes of this module
            ReleaseNotes = 'Initial release of PSmediaManager project management module'
        }
    }
}
