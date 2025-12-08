Set-StrictMode -Version Latest

Describe 'Initialize-PSmmProjectDigiKamConfig (additional cases)' {
        BeforeAll {
Set-StrictMode -Version Latest

$script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path

# Preload PSmm types
. (Join-Path -Path $script:repoRoot -ChildPath 'tests/Preload-PSmmTypes.ps1')
                $script:pluginsManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
                $script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
                $script:loggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
                $script:importClasses = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'

                . (Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/TestConfig.ps1')
                . $script:importClasses -RepositoryRoot $script:repoRoot

                foreach ($module in 'PSmm.Plugins', 'PSmm', 'PSmm.Logging') {
                        if (Get-Module -Name $module -ErrorAction SilentlyContinue) { Remove-Module -Name $module -Force }
                }
                foreach ($manifest in @($script:psmmManifest, $script:loggingManifest, $script:pluginsManifest)) {
                        Import-Module -Name $manifest -Force -ErrorAction Stop
                }
        }

    BeforeEach {
            $script:repoRoot = $TestDrive
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

            $null = New-Item -Path $script:cfg.Paths.App.Config -ItemType Directory -Force
            $null = New-Item -Path $script:cfg.Paths.App.ConfigDigiKam -ItemType Directory -Force
            $null = New-Item -Path $script:cfg.Paths.App.Plugins.Root -ItemType Directory -Force

            # Mock FileSystemService
            $script:mockFS = [PSCustomObject]@{
                PSTypeName = 'FileSystemService'
            }
            $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'TestPath' -Value { param($path) Test-Path $path }
            $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'NewDirectory' -Value { param($path) New-Item -Path $path -ItemType Directory -Force }
            $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'CopyItem' -Value { param($src, $dest) Copy-Item -Path $src -Destination $dest -Force }
            $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'GetChildItem' -Value {
                param($path, $filter, $itemType)
                $params = @{ Path = $path; ErrorAction = 'SilentlyContinue' }
                if ($filter) { $params['Filter'] = $filter }
                if ($itemType -eq 'Directory') { $params['Directory'] = $true }
                Get-ChildItem @params
            }
            $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'GetContent' -Value { param($path) Get-Content -Path $path -Raw }
            $script:mockFS | Add-Member -MemberType ScriptMethod -Name 'SetContent' -Value { param($path, $content) Set-Content -Path $path -Value $content -Force }

            # Mock PathProvider
            $script:mockPath = [PSCustomObject]@{
                PSTypeName = 'PathProvider'
            }
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

            Set-Content -Path (Join-Path $script:cfg.Paths.App.ConfigDigiKam 'digiKam-rc-template') -Value @"
[General]
AppDir=%%ProjectPath%%/Config/digiKam
[Database]
Port=%%DatabasePort%%
"@ -Encoding UTF8

            Set-Content -Path (Join-Path $script:cfg.Paths.App.ConfigDigiKam 'digiKam-metadataProfile.dkamp') -Value 'profile' -Encoding UTF8

            $null = New-Item -Path (Join-Path $script:cfg.Paths.App.Plugins.Root 'digiKam-8.8.0') -ItemType Directory -Force
            $null = New-Item -Path (Join-Path $script:cfg.Paths.App.Plugins.Root 'mariadb-11.5.2') -ItemType Directory -Force

            $script:projectRoot = Join-Path -Path $TestDrive -ChildPath 'ProjectB'
            $null = New-Item -Path $script:projectRoot -ItemType Directory -Force
            $script:cfg.Projects = @{ Current = @{ Name = 'ProjectB'; Path = $script:projectRoot } }
    }

        It 'respects WhatIf and returns empty result' {
            Mock Write-PSmmLog {} -ModuleName PSmm.Plugins

            $result = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectB' -FileSystem $script:mockFS -PathProvider $script:mockPath -WhatIf

            # WhatIf should not create files
            Test-Path -Path (Join-Path $script:projectRoot 'Config/digiKam-rc') | Should -BeFalse
    }

        It 'throws when project is not currently selected' {
            Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
            $script:cfg.Projects = @{}

            { PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'Missing' -FileSystem $script:mockFS -PathProvider $script:mockPath } | Should -Throw '*Project*not currently selected*'
    }

        It 'throws when digiKam plugins are missing' {
            Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
            $script:cfg.Paths.App.Plugins.Root = Join-Path $script:repoRoot 'EmptyPlugins'
            $null = New-Item -Path $script:cfg.Paths.App.Plugins.Root -ItemType Directory -Force

            { PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectB' -FileSystem $script:mockFS -PathProvider $script:mockPath } | Should -Throw '*digiKam installation not found*'
    }

        It 'throws when MariaDB plugins are missing' {
            Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
            # Create only digiKam, remove MariaDB
            $null = New-Item -Path (Join-Path $script:cfg.Paths.App.Plugins.Root 'digiKam-9.0.0') -ItemType Directory -Force
            Get-ChildItem -Path $script:cfg.Paths.App.Plugins.Root -Directory -Filter 'mariadb-*' | Remove-Item -Recurse -Force

            { PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectB' -FileSystem $script:mockFS -PathProvider $script:mockPath } | Should -Throw '*MariaDB installation not found*'
    }

        It 'throws when the template file is missing' {
            Mock Write-PSmmLog {} -ModuleName PSmm.Plugins
            # Remove template
            Remove-Item -Path (Join-Path $script:cfg.Paths.App.ConfigDigiKam 'digiKam-rc-template') -Force

            { PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectB' -FileSystem $script:mockFS -PathProvider $script:mockPath -Force } | Should -Throw '*template*not found*'
    }

        It 'copies metadata profile on -Force even if target exists' {
            Mock Write-PSmmLog {} -ModuleName PSmm.Plugins

            $appDir = Join-Path -Path $script:projectRoot -ChildPath 'Config/digiKam'
            $null = New-Item -Path $appDir -ItemType Directory -Force
            $targetProfile = Join-Path -Path $appDir -ChildPath 'digiKam-metadataProfile.dkamp'
            Set-Content -Path $targetProfile -Value 'old' -Encoding UTF8

            # First run without -Force should keep existing profile
            $null = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectB' -FileSystem $script:mockFS -PathProvider $script:mockPath
            (Get-Content -Path $targetProfile -Raw).Trim() | Should -Be 'old'

            # Now with -Force should overwrite
            $null = PSmm.Plugins\Initialize-PSmmProjectDigiKamConfig -Config $script:cfg -ProjectName 'ProjectB' -FileSystem $script:mockFS -PathProvider $script:mockPath -Force
            (Get-Content -Path $targetProfile -Raw).Trim() | Should -Be 'profile'
    }
}
