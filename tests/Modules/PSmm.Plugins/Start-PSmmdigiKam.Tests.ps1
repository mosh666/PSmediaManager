#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Start-PSmmdigiKam' {
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

        $script:MediaManagerExceptionType = [MediaManagerException]

        $script:testRoot = $TestDrive
        $script:srcRoot = Join-Path -Path $script:testRoot -ChildPath 'src'
        $null = New-Item -Path $script:srcRoot -ItemType Directory -Force

        $script:cfg = [AppConfiguration]::new()
        $script:cfg.Paths = [AppPaths]::new()
        $script:cfg.Paths.RepositoryRoot = $script:testRoot
        $script:cfg.Paths.App = [AppSubPaths]::new()
        $script:cfg.Paths.App.Root = $script:srcRoot
        $script:cfg.Paths.App.Config = Join-Path $script:srcRoot 'Config/PSmm'
        $script:cfg.Paths.App.ConfigDigiKam = Join-Path $script:srcRoot 'Config/digiKam'
        $script:cfg.Paths.App.Plugins = [PluginsPaths]::new()
        $script:cfg.Paths.App.Plugins.Root = Join-Path $script:testRoot 'Plugins'

        $null = New-Item -Path $script:cfg.Paths.App.Config -ItemType Directory -Force
        $null = New-Item -Path $script:cfg.Paths.App.ConfigDigiKam -ItemType Directory -Force
        $null = New-Item -Path $script:cfg.Paths.App.Plugins.Root -ItemType Directory -Force

        Set-Content -Path (Join-Path $script:cfg.Paths.App.ConfigDigiKam 'digiKam-rc-template') -Value @"
[General]
AppDir=%%ProjectPath%%/Config/digiKam
[Database]
Port=%%DatabasePort%%
"@ -Encoding UTF8
        Set-Content -Path (Join-Path $script:cfg.Paths.App.ConfigDigiKam 'digiKam-metadataProfile.dkamp') -Value 'profile' -Encoding UTF8

        $digiKamDir = Join-Path $script:cfg.Paths.App.Plugins.Root 'digiKam-8.8.0'
        $mariaDir = Join-Path $script:cfg.Paths.App.Plugins.Root 'mariadb-11.5.2'
        $null = New-Item -Path $digiKamDir -ItemType Directory -Force
        $null = New-Item -Path $mariaDir -ItemType Directory -Force
        Set-Content -Path (Join-Path $digiKamDir 'digikam.exe') -Value '' -Encoding UTF8

        $script:cfg.Projects = @{ Current = @{ Name = 'Demo'; Path = (Join-Path $script:testRoot 'Demo') } }
        $null = New-Item -Path $script:cfg.Projects.Current.Path -ItemType Directory -Force
    }

    It 'launches digiKam using project config and sets DIGIKAM_APPDIR' {
        $projectPath = $script:cfg.Projects.Current.Path
        $expectedAppDir = Join-Path (Join-Path $projectPath 'Config') 'digiKam'

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Start-Process { [pscustomobject]@{ Id = 42 } } -ModuleName PSmm.Plugins

        { PSmm.Plugins\Start-PSmmdigiKam -Config $script:cfg -Verbose } | Should -Not -Throw
        $env:DIGIKAM_APPDIR | Should -Be $expectedAppDir
    }

    It 'warns and exits early for template projects' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = '_Template_'; Path = (Join-Path $TestDrive 'TemplateProj') } }

        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Mock Write-Warning {} -ModuleName PSmm.Plugins
        Mock Read-Host { '' } -ModuleName PSmm.Plugins
        Mock Initialize-PSmmProjectDigiKamConfig { throw 'Should not be invoked' } -ModuleName PSmm.Plugins

        { PSmm.Plugins\Start-PSmmdigiKam -Config $cfg -Verbose } | Should -Not -Throw
        Should -Invoke Write-Warning -ModuleName PSmm.Plugins -ParameterFilter { $Message -like 'digiKam cannot be started*' } -Times 1
        Should -Invoke Initialize-PSmmProjectDigiKamConfig -ModuleName PSmm.Plugins -Times 0
    }

    It 'logs error details when project setup fails' {
        $cfg = [AppConfiguration]::new()
        $cfg.Projects = @{ Current = @{ Name = 'Alpha'; Path = (Join-Path $TestDrive 'Alpha') } }

        $global:StartPSmmDigiKamErrorLogs = @()

        Mock Initialize-PSmmProjectDigiKamConfig { throw ([MediaManagerException]::new('Simulated failure', 'digiKamRC')) } -ModuleName PSmm.Plugins
        Mock Write-PSmmLog {
            param($Level, $Message, $Context, $ErrorRecord, [switch]$Console, [switch]$File)
            if ($Level -eq 'ERROR') { $global:StartPSmmDigiKamErrorLogs += $Message }
        } -ModuleName PSmm.Plugins

        $caughtError = $null
        try {
            PSmm.Plugins\Start-PSmmdigiKam -Config $cfg | Out-Null
        }
        catch {
            $caughtError = $_
        }

        $caughtError | Should -Not -BeNullOrEmpty
        # In this test we focus on ensuring an ERROR log is written containing the simulated failure text
        @($global:StartPSmmDigiKamErrorLogs | Where-Object { $_ -like '*Simulated failure*' }).Count | Should -Be 1
        Should -Invoke Write-PSmmLog -ModuleName PSmm.Plugins -ParameterFilter { $Level -eq 'ERROR' -and $Context -eq 'digiKam' } -Times 1
        Remove-Variable -Name StartPSmmDigiKamErrorLogs -Scope Global -ErrorAction SilentlyContinue
    }
}
