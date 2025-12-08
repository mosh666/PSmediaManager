@{
    RootModule = 'PSmm.Plugins.psm1'
    # Version number of this module (updated by Update-ModuleVersions.ps1 from Git)
    ModuleVersion = '0.1.0'
    GUID = 'b413c6f2-0d0a-4c7c-9f2a-e6321c72b8e3'
    Author = 'Der Mosh'
    CompanyName = ''
    Copyright = '(c) 2025 Der Mosh. All rights reserved.'
    Description = 'Plugin orchestration module for PSmediaManager. Handles external plugin acquisition and digiKam/MariaDB coordination using explicit install paths (no temporary PATH helpers).'
    PowerShellVersion = '7.5.4'
    CompatiblePSEditions = @('Core')
    RequiredModules = @(
        'PSmm'
        'PSmm.Logging'
    )
    FunctionsToExport = @(
        'Install-KeePassXC'
        'Confirm-Plugins'
        'Get-PSmmAvailablePort'
        'Get-PSmmProjectPorts'
        'Initialize-PSmmProjectDigiKamConfig'
        'Start-PSmmdigiKam'
        'Stop-PSmmdigiKam'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Plugins', 'MediaManager', 'Automation')
            Prerelease = ''
            ReleaseNotes = 'Initial extraction of external plugin orchestration into dedicated module.'
        }
    }
}
