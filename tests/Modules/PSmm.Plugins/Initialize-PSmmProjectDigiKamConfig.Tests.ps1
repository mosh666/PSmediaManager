#Requires -Version 7.5.4
Set-StrictMode -Version Latest

# Preload PSmm types before Describe block
$script:preloadRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
. (Join-Path -Path $script:preloadRepoRoot -ChildPath 'tests/Preload-PSmmTypes.ps1')

Describe 'Initialize-PSmmProjectDigiKamConfig' {
    BeforeAll {
        $script:moduleRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:pluginsManifest = Join-Path -Path $script:moduleRepoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
        $script:psmmManifest = Join-Path -Path $script:moduleRepoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:loggingManifest = Join-Path -Path $script:moduleRepoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:importClassesScript = Join-Path -Path $script:moduleRepoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'

        . $script:importClassesScript -RepositoryRoot $script:moduleRepoRoot
        foreach ($module in 'PSmm.Plugins', 'PSmm', 'PSmm.Logging') {
            if (Get-Module -Name $module -ErrorAction SilentlyContinue) {
                Remove-Module -Name $module -Force
            }
        }
        foreach ($manifest in @($script:psmmManifest, $script:loggingManifest, $script:pluginsManifest)) {
            Import-Module -Name $manifest -Force -ErrorAction Stop
        }
    }

    BeforeEach {
        $script:repoRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString())
        $null = New-Item -Path $script:repoRoot -ItemType Directory -Force

        $script:srcRoot = Join-Path -Path $script:repoRoot -ChildPath 'src'
        $null = New-Item -Path $script:srcRoot -ItemType Directory -Force

        $script:cfg = [AppConfiguration]::new()
        $script:cfg.Paths = [AppPaths]::new()
        $script:cfg.Paths.RepositoryRoot = $script:repoRoot
        $script:cfg.Paths.App = [AppSubPaths]::new()
        $script:cfg.Paths.App.Root = $script:srcRoot
        $script:cfg.Paths.App.Config = Join-Path $script:srcRoot 'Config/PSmm'
        $script:cfg.Paths.App.ConfigDigiKam = Join-Path $script:srcRoot 'Config/digiKam'
        $script:cfg.Paths.App.Plugins = [PluginsPaths]::new()
        $script:cfg.Paths.App.Plugins.Root = Join-Path $script:repoRoot 'Plugins'

        foreach ($path in @($script:cfg.Paths.App.Config, $script:cfg.Paths.App.ConfigDigiKam, $script:cfg.Paths.App.Plugins.Root)) {
            $null = New-Item -Path $path -ItemType Directory -Force
        }

        Set-Content -Path (Join-Path $script:cfg.Paths.App.ConfigDigiKam 'digiKam-rc-template') -Value @"
[General]
AppDir=%%ProjectPath%%/Config/digiKam
[Database]
Port=%%DatabasePort%%
"@ -Encoding UTF8

        Set-Content -Path (Join-Path $script:cfg.Paths.App.ConfigDigiKam 'digiKam-metadataProfile.dkamp') -Value 'profile' -Encoding UTF8

        $null = New-Item -Path (Join-Path $script:cfg.Paths.App.Plugins.Root 'digiKam-8.8.0') -ItemType Directory -Force
        $null = New-Item -Path (Join-Path $script:cfg.Paths.App.Plugins.Root 'mariadb-11.5.2') -ItemType Directory -Force

        $script:projectRoot = Join-Path -Path $script:repoRoot -ChildPath 'ProjectA'
        $null = New-Item -Path $script:projectRoot -ItemType Directory -Force
        $script:cfg.Projects = @{ Current = @{ Name = 'ProjectA'; Path = $script:projectRoot } }

        # Mock FileSystemService and PathProvider
        $script:mockFS = [PSCustomObject]@{ PSTypeName = 'FileSystemService' }
        $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'TestPath' -Value { param($path) Test-Path $path }
        $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'NewDirectory' -Value { param($path) New-Item -Path $path -ItemType Directory -Force }
        $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'CopyItem' -Value { param($src, $dest) Copy-Item -Path $src -Destination $dest -Force }
        $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'GetChildItem' -Value { param($path, $filter, $pattern) Get-ChildItem -Path $path -Directory -Filter $pattern -ErrorAction SilentlyContinue }
        $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'GetContent' -Value { param($path) Get-Content -Path $path -Raw }
        $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'SetContent' -Value { param($path, $content) Set-Content -Path $path -Value $content -Force }

        $script:mockPath = [PSCustomObject]@{ PSTypeName = 'PathProvider' }
        $script:mockPath | Add-Member -MemberType ScriptMethod -Name 'Join' -Value {
            $parts = if ($args.Count -eq 1 -and $args[0] -is [System.Array]) { @($args[0]) } else { @($args) }
            [IO.Path]::Combine([string[]]$parts)
        } -Force
        $script:mockPath | Add-Member -MemberType ScriptMethod -Name 'CombinePath' -Value {
            $parts = if ($args.Count -eq 1 -and $args[0] -is [System.Array]) { @($args[0]) } else { @($args) }
            [IO.Path]::Combine([string[]]$parts)
        } -Force
        $script:mockPath | Add-Member -MemberType ScriptMethod -Name 'GetDirectoryName' -Value { param($path) Split-Path -Path $path -Parent }
        $script:mockPath | Add-Member -MemberType ScriptMethod -Name 'GetFileName' -Value { param($path) Split-Path -Path $path -Leaf }
    }

    It 'creates project directories and writes digiKam rc' {
        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        $result = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA' -FileSystem $script:mockFS -PathProvider $script:mockPath -Verbose

        $result | Should -Not -BeNullOrEmpty
        Test-Path -Path $result.DigiKamRcPath | Should -BeTrue
        Test-Path -Path $result.AppDir | Should -BeTrue
        Test-Path -Path $result.DatabasePath | Should -BeTrue
        $result.DatabasePort | Should -BeGreaterOrEqual 3310
    }

    It 'reuses existing config when not forced' {
        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        $first = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA' -FileSystem $script:mockFS -PathProvider $script:mockPath
        $second = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA' -FileSystem $script:mockFS -PathProvider $script:mockPath
        $second.DigiKamRcPath | Should -Be $first.DigiKamRcPath
    }

    It 'skips work when WhatIf is used' {
        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        $result = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA' -FileSystem $script:mockFS -PathProvider $script:mockPath -WhatIf

        $result | Should -BeOfType hashtable
        $result.Count | Should -Be 0
        Test-Path -Path (Join-Path $script:projectRoot 'Config/digiKam-rc') | Should -BeFalse
    }

    It 'throws when project is not selected' {
        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        $script:cfg.Projects = @{ Current = @{ Name = 'OtherProject'; Path = $script:projectRoot } }

        { PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA' -FileSystem $script:mockFS -PathProvider $script:mockPath } |
            Should -Throw -ExpectedMessage '*not currently selected*'
    }

    It 'throws when project path does not exist' {
        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Remove-Item -Path $script:projectRoot -Recurse -Force

        { PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA' -FileSystem $script:mockFS -PathProvider $script:mockPath } |
            Should -Throw -ExpectedMessage '*path not found*'
    }

    It 'throws when digiKam installation is missing' {
        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Remove-Item -Path (Join-Path $script:cfg.Paths.App.Plugins.Root 'digiKam-8.8.0') -Recurse -Force

        { PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA' -FileSystem $script:mockFS -PathProvider $script:mockPath } |
            Should -Throw -ExpectedMessage '*digiKam installation not found*'
    }

    It 'throws when MariaDB installation is missing' {
        Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
        Remove-Item -Path (Join-Path $script:cfg.Paths.App.Plugins.Root 'mariadb-11.5.2') -Recurse -Force

        { PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectA' -FileSystem $script:mockFS -PathProvider $script:mockPath } |
            Should -Throw -ExpectedMessage '*MariaDB installation not found*'
    }
}
