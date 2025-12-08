@{
    # Script module or binary module file associated with this manifest
    RootModule = 'PSmm.UI.psm1'

    # Version number of this module (updated by Update-ModuleVersions.ps1 from Git)
    ModuleVersion = '0.0.1'

    # ID used to uniquely identify this module
    GUID = '65e7d1ea-d069-4da5-b9fc-682c3cd90016'

    # Author of this module
    Author = 'Der Mosh'

    # Company or vendor of this module
    CompanyName = ''

    # Copyright statement for this module
    Copyright = '(c) 2025 Der Mosh. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'User interface module for PSmediaManager. Provides interactive menu systems, multi-option prompts, ANSI-colored output formatting, and user input validation for a rich console experience.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.5.4'

    # Supported PowerShell editions
    CompatiblePSEditions = @('Core')

    # Functions to export from this module
    FunctionsToExport = @(
        'Invoke-PSmmUI'
        'Invoke-MultiOptionPrompt'
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
            Tags = @('UI', 'UserInterface', 'PowerShell', 'Console')

            # Prerelease string (empty for stable releases)
            Prerelease = ''

            # Release notes of this module
            ReleaseNotes = 'Initial release of PSmediaManager UI module'
        }
    }
}
