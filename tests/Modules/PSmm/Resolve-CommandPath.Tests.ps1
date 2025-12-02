# Requires -Version 7.0
Set-StrictMode -Version Latest

<#
 Consolidated suite for command path resolution.
 Option B: Merge plugin and tool command path tests under one Describe.
 This file replaces per-domain duplicates while keeping shared setup.
#>

$repoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path
$importAllHelpers = Resolve-Path -Path (Join-Path -Path $repoRoot -ChildPath 'tests/Support/Import-AllTestHelpers.ps1')
. $importAllHelpers.Path -RepositoryRoot $repoRoot

$psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
$loggingManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
$pluginsManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
foreach ($manifest in @($psmmManifest, $loggingManifest, $pluginsManifest)) {
    if (Test-Path -Path $manifest) {
        Import-Module -Name $manifest -Force -ErrorAction Stop | Out-Null
    }
}

Describe "Resolve-CommandPath" {
    BeforeAll {
        # Shared environment setup for both Plugin and Tool contexts
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:pluginsManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
        $script:psmmManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:loggingManifest = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:importClassesScript = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $script:testConfigPath = Join-Path -Path $script:repoRoot -ChildPath 'tests/Support/TestConfig.ps1'

        . $script:testConfigPath
        & $script:importClassesScript -RepositoryRoot $script:repoRoot

        foreach ($module in 'PSmm.Plugins', 'PSmm', 'PSmm.Logging') {
            if (Get-Module -Name $module -ErrorAction SilentlyContinue) {
                Remove-Module -Name $module -Force
            }
        }

        foreach ($manifest in @($script:psmmManifest, $script:loggingManifest, $script:pluginsManifest)) {
            Import-Module -Name $manifest -Force -ErrorAction Stop
        }

        $script:testScratch = Join-Path -Path $script:repoRoot -ChildPath 'tests/_tmp/ResolveCommandPath'
        if (Test-Path $script:testScratch) {
            Remove-Item -Path $script:testScratch -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $script:testScratch -ItemType Directory | Out-Null

        $global:ResolveCommandPathTestData = [pscustomobject]@{
            RepoRoot = $script:repoRoot
            Scratch = $script:testScratch
        }
    }

    AfterAll {
        if (Test-Path $script:testScratch) {
            Remove-Item -Path $script:testScratch -Recurse -Force -ErrorAction SilentlyContinue
        }

        $testDataVar = Get-Variable -Name ResolveCommandPathTestData -Scope Global -ErrorAction SilentlyContinue
        if ($testDataVar) {
            Remove-Variable -Name ResolveCommandPathTestData -Scope Global -ErrorAction SilentlyContinue
        }
    }

    Context "Plugin" {
        InModuleScope 'PSmm.Plugins' {
        BeforeAll {
            $testData = $global:ResolveCommandPathTestData
            if (-not $testData) { throw 'Resolve-CommandPath test data not initialized.' }
            $script:repoRoot = $testData.RepoRoot
            $script:testScratch = $testData.Scratch

            $confirmPluginsScript = Join-Path -Path $script:repoRoot -ChildPath 'src/Modules/PSmm.Plugins/Private/Confirm-Plugins.ps1'
            . $confirmPluginsScript

            $script:pluginsRoot = Join-Path -Path $script:testScratch -ChildPath 'PluginsRoot'
            New-Item -Path $script:pluginsRoot -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $script:pluginsRoot '_Downloads') -ItemType Directory | Out-Null
            New-Item -Path (Join-Path $script:pluginsRoot '_Temp') -ItemType Directory | Out-Null
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
                Commands = @{}
            }

            $process = New-Object PSObject
            $process | Add-Member -MemberType ScriptMethod -Name TestCommand -Value { param($command) $false }

            $resolved = Resolve-PluginCommandPath -Paths $paths -CommandName '7z' -DefaultCommand '7z' -Process $process

            $resolved | Should -Be $candidateExe
            $paths.Commands['7z'] | Should -Be $candidateExe
        }

        It 'returns the cached path before checking the file system' {
            $emptyDir = Join-Path -Path $script:pluginsRoot -ChildPath 'empty'
            New-Item -Path $emptyDir -ItemType Directory | Out-Null
            $cachedExe = Join-Path -Path $script:testScratch -ChildPath 'cached\7z.exe'
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

            $resolved = Resolve-PluginCommandPath -Paths $paths -CommandName '7z' -DefaultCommand '7z' -Process $process

            $resolved | Should -Be $cachedExe
        }
        }
    }

    Context "Tool" {
        InModuleScope 'PSmm' {
        BeforeAll {
            $testData = $global:ResolveCommandPathTestData
            if (-not $testData) { throw 'Resolve-CommandPath test data not initialized.' }
            $script:testScratch = $testData.Scratch
            if (-not (Get-Command -Name Resolve-ToolCommandPath -ErrorAction SilentlyContinue)) {
                throw 'Resolve-ToolCommandPath helper not available in PSmm module.'
            }
        }

        It 'resolves tool command on PATH' {
            $process = New-Object PSObject
            $process | Add-Member -MemberType ScriptMethod -Name TestCommand -Value { param($command) $true }

            $paths = @{ Root = $script:testScratch }
            $resolved = Resolve-ToolCommandPath -Paths $paths -CommandName 'pwsh' -DefaultCommand 'pwsh' -Process $process

            $resolved | Should -Not -BeNullOrEmpty
            [System.IO.Path]::GetFileNameWithoutExtension($resolved) | Should -Be 'pwsh'
        }

        It 'returns absolute path when provided' {
            $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
            if ($null -eq $cmd) {
                Set-ItResult -Skipped -Because 'pwsh not found on PATH'
                return
            }
            $abs = $cmd.Source
            $process = New-Object PSObject
            $process | Add-Member -MemberType ScriptMethod -Name TestCommand -Value { param($command) $true }
            $paths = @{ Root = $script:testScratch }

            $resolved = Resolve-ToolCommandPath -Paths $paths -CommandName $abs -DefaultCommand 'pwsh' -Process $process
            $resolved | Should -Be $abs
        }

        It 'throws when tool not found' {
            $process = New-Object PSObject
            $process | Add-Member -MemberType ScriptMethod -Name TestCommand -Value { param($command) $false }
            $paths = @{ Root = $script:testScratch }

            { Resolve-ToolCommandPath -Paths $paths -CommandName 'definitely-not-a-real-cmd-xyz' -DefaultCommand 'xyz' -Process $process } | Should -Throw
        }
        }
    }
}
