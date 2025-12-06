#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Resolve-PluginCommandPath helper' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:pluginsManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
        $script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:loggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:importClassesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $script:testConfigPath = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/TestConfig.ps1'

        . $testConfigPath
        & $importClassesScript -RepositoryRoot $script:repoRoot

        foreach ($module in 'PSmm.Plugins', 'PSmm', 'PSmm.Logging') {
            if (Get-Module -Name $module -ErrorAction SilentlyContinue) {
                Remove-Module -Name $module -Force
            }
        }

        foreach ($manifest in @($script:psmmManifest, $script:loggingManifest, $script:pluginsManifest)) {
            Import-Module -Name $manifest -Force -ErrorAction Stop
        }

        $confirmPluginsScript = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Plugins/Private/Confirm-Plugins.ps1'
        . $confirmPluginsScript

        $script:testPluginsScratch = Join-Path -Path $script:repoRoot -ChildPath 'tests/_tmp/ResolvePluginCommandPath'
        if (Test-Path $script:testPluginsScratch) {
            Remove-Item -Path $script:testPluginsScratch -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $script:testPluginsScratch -ItemType Directory | Out-Null
        $script:pluginsRoot = Join-Path -Path $script:testPluginsScratch -ChildPath 'PluginsRoot'
        New-Item -Path $script:pluginsRoot -ItemType Directory | Out-Null
        New-Item -Path (Join-Path $script:pluginsRoot '_Downloads') -ItemType Directory | Out-Null
        New-Item -Path (Join-Path $script:pluginsRoot '_Temp') -ItemType Directory | Out-Null
    }

    AfterAll {
        if (Test-Path $script:testPluginsScratch) {
            Remove-Item -Path $script:testPluginsScratch -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'resolves 7z from the Plugins root when PATH lacks the command' {
        $candidateDir = Join-Path -Path $script:pluginsRoot -ChildPath 'bin'
        New-Item -Path $candidateDir -ItemType Directory | Out-Null
        $candidateExe = Join-Path -Path $candidateDir -ChildPath '7z.exe'
        New-Item -Path $candidateExe -ItemType File | Out-Null

        $paths = @{
            Root = $script:pluginsRoot
            _Downloads = Join-Path -Path $script:pluginsRoot -ChildPath '_Downloads'
            _Temp = Join-Path -Path $script:pluginsRoot -ChildPath '_Temp'
        }

        $process = New-Object PSObject
        $process | Add-Member -MemberType ScriptMethod -Name TestCommand -Value { param($command) $false }

        $fileSystem = [FileSystemService]::new()

        $resolved = Resolve-PluginCommandPath -Paths $paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $fileSystem -Process $process

        $resolved | Should -Be $candidateExe
        $paths.Commands['7z'] | Should -Be $candidateExe
    }

    It 'returns the cached path before checking the file system' {
        $emptyDir = Join-Path -Path $script:pluginsRoot -ChildPath 'empty'
        New-Item -Path $emptyDir -ItemType Directory | Out-Null
        $cachedExe = Join-Path -Path $script:testPluginsScratch -ChildPath 'cached\7z.exe'
        New-Item -Path (Split-Path -Path $cachedExe -Parent) -ItemType Directory -Force | Out-Null
        New-Item -Path $cachedExe -ItemType File | Out-Null

        $paths = @{
            Root = $emptyDir
            _Downloads = Join-Path -Path $emptyDir -ChildPath '_Downloads'
            _Temp = Join-Path -Path $emptyDir -ChildPath '_Temp'
            Commands = @{ '7z' = $cachedExe }
        }

        $process = New-Object PSObject
        $process | Add-Member -MemberType ScriptMethod -Name TestCommand -Value { param($command) $false }

        $fileSystem = [FileSystemService]::new()

        $resolved = Resolve-PluginCommandPath -Paths $paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $fileSystem -Process $process

        $resolved | Should -Be $cachedExe
    }
}
