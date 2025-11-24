#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Initialize-PSmmProjectDigiKamConfig' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:pluginsManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
        $script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:loggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:importClassesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'

        . $script:importClassesScript -RepositoryRoot $script:repoRoot
        foreach ($module in 'PSmm.Plugins', 'PSmm', 'PSmm.Logging') {
            if (Get-Module -Name $module -ErrorAction SilentlyContinue) {
                Remove-Module -Name $module -Force
            }
        }
        foreach ($manifest in @($script:psmmManifest, $script:loggingManifest, $script:pluginsManifest)) {
            Import-Module -Name $manifest -Force -ErrorAction Stop
        }

        $script:repoRoot = $TestDrive
        $script:srcRoot = Join-Path -Path $script:repoRoot -ChildPath 'src'
        $null = New-Item -Path $script:srcRoot -ItemType Directory -Force

        # Build minimal AppConfiguration
        $script:cfg = [AppConfiguration]::new()
        $script:cfg.Paths = [AppPaths]::new()
        $script:cfg.Paths.RepositoryRoot = $script:repoRoot
        $script:cfg.Paths.App = [AppSubPaths]::new()
        $script:cfg.Paths.App.Root = $script:srcRoot
        $script:cfg.Paths.App.Config = Join-Path $script:srcRoot 'Config/PSmm'
        $script:cfg.Paths.App.ConfigDigiKam = Join-Path $script:srcRoot 'Config/digiKam'
        $script:cfg.Paths.App.Plugins = [PluginsPaths]::new()
        $script:cfg.Paths.App.Plugins.Root = Join-Path $script:repoRoot 'Plugins'

        # Ensure folders exist
        $null = New-Item -Path $script:cfg.Paths.App.Config -ItemType Directory -Force
        $null = New-Item -Path $script:cfg.Paths.App.ConfigDigiKam -ItemType Directory -Force
        $null = New-Item -Path $script:cfg.Paths.App.Plugins.Root -ItemType Directory -Force

        # Provide required templates in Config\digiKam
        Set-Content -Path (Join-Path $script:cfg.Paths.App.ConfigDigiKam 'digiKam-rc-template') -Value @"
[General]
AppDir=%%ProjectPath%%/Config/digiKam
[Database]
Port=%%DatabasePort%%
"@ -Encoding UTF8

        Set-Content -Path (Join-Path $script:cfg.Paths.App.ConfigDigiKam 'digiKam-metadataProfile.dkamp') -Value 'profile' -Encoding UTF8

        # Create plugin directories
        $null = New-Item -Path (Join-Path $script:cfg.Paths.App.Plugins.Root 'digiKam-8.8.0') -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $script:cfg.Paths.App.Plugins.Root 'mariadb-11.5.2') -ItemType Directory -Force

        # Project selection
        $script:projectRoot = Join-Path -Path $TestDrive -ChildPath 'ProjectA'
        $null = New-Item -Path $script:projectRoot -ItemType Directory -Force
        $script:cfg.Projects = @{ Current = @{ Name = 'ProjectA'; Path = $script:projectRoot } }
    }

    It 'creates project directories and writes digiKam rc' {
        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        $result = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA' -Verbose

        $result | Should -Not -BeNullOrEmpty
        Test-Path -Path $result.DigiKamRcPath | Should -BeTrue
        Test-Path -Path $result.AppDir | Should -BeTrue
        Test-Path -Path $result.DatabasePath | Should -BeTrue
        $result.DatabasePort | Should -BeGreaterOrEqual 3310
    }

    It 'reuses existing config when not forced' {
        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        $first = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA'
        $second = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA'
        $second.DigiKamRcPath | Should -Be $first.DigiKamRcPath
    }
}
