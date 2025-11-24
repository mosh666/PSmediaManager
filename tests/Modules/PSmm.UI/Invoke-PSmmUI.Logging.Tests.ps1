#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Invoke-PSmmUI logging' {

    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:testHelperPath = Join-Path -Path $script:repoRoot -ChildPath 'tests/Helpers/TestConfig.ps1'
        $script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:projectsManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Projects/PSmm.Projects.psd1'
        $script:uiManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.UI/PSmm.UI.psd1'

        . $script:testHelperPath

        foreach ($moduleName in 'PSmm','PSmm.Projects') {
            if (Get-Module -Name $moduleName -ErrorAction SilentlyContinue) {
                Remove-Module -Name $moduleName -Force
            }
        }
        Import-Module -Name $script:psmmManifest -Force -ErrorAction Stop
        Import-Module -Name $script:projectsManifest -Force -ErrorAction Stop

        if (Get-Module -Name 'PSmm.UI' -ErrorAction SilentlyContinue) {
            Remove-Module -Name 'PSmm.UI' -Force
        }
        Import-Module -Name $script:uiManifest -Force -ErrorAction Stop
    }

    BeforeEach {
        . $script:testHelperPath
        $script:recorder = New-TestAppLogsRecorder
        Register-TestWritePSmmLogMock -Recorder $script:recorder -ModuleName 'PSmm.UI'

        $script:config = New-TestAppConfiguration

        Mock Clear-Host {}
        Mock Start-Sleep {}
        Mock Show-InvalidSelection -ModuleName 'PSmm.UI' {}
        Mock Read-Host -ModuleName 'PSmm.UI' { 'Q' }

        Mock Confirm-Storage -ModuleName 'PSmm' { throw 'Simulated storage validation failure' }
        Mock Get-PSmmProjects -ModuleName 'PSmm.Projects' {
            @{ Master = @{ 'MASTER-DRIVE' = @() }; Backup = @{} }
        }
        Mock Show-Header -ModuleName 'PSmm.UI' { param($Config,$ShowProject,$StorageGroupFilter) }
        Mock Show-MenuMain -ModuleName 'PSmm.UI' { param($Config,$StorageGroup,$Projects) }
        Mock Show-Footer -ModuleName 'PSmm.UI' { param($Config) }
    }

    It 'records a warning when storage validation fails' {
        { Invoke-PSmmUI -Config $script:config } | Should -Not -Throw
        $script:recorder.'Assert-Warning'('Storage validation encountered issues')
    }

    It 'records the UI startup notice' {
        { Invoke-PSmmUI -Config $script:config } | Should -Not -Throw
        $script:recorder.'Assert-LogLevel'('NOTICE', 'UI interactive session starting')
    }
}
