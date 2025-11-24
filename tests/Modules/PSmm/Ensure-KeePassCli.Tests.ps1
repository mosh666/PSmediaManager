#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Ensure-KeePassCliAvailability' {
    BeforeAll {
        $script:repoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $script:psmmManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/PSmm.psd1'
        $script:psmmLoggingManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        $script:psmmPluginsManifest = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.Plugins/PSmm.Plugins.psd1'
        $script:testConfigPath = Join-Path -Path $repoRoot -ChildPath 'tests/Support/TestConfig.ps1'

        . $testConfigPath
        $helperFunctions = @('New-TestRepositoryRoot','New-TestAppConfiguration','New-TestStorageDrive','Add-TestStorageGroup')
        foreach ($helper in $helperFunctions) {
            $command = Get-Command -Name $helper -CommandType Function -ErrorAction Stop
            Set-Item -Path "function:\global:$helper" -Value $command.ScriptBlock -Force
        }

        Get-Module -Name PSmm, PSmm.Logging, PSmm.Plugins -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Module -Name $_.Name -Force -ErrorAction SilentlyContinue
        }

        Import-Module -Name $psmmManifest -Force -ErrorAction Stop
        Import-Module -Name $psmmLoggingManifest -Force -ErrorAction Stop
        Import-Module -Name $psmmPluginsManifest -Force -ErrorAction Stop

        $global:PSmmPluginsManifestPath = $psmmPluginsManifest
        InModuleScope PSmm {
            Import-Module -Name $global:PSmmPluginsManifestPath -Force -ErrorAction Stop
            if (-not (Get-Command -Name Install-KeePassXC -ErrorAction SilentlyContinue)) {
                function Install-KeePassXC {
                    [CmdletBinding()]
                    param(
                        [Parameter(Mandatory)][AppConfiguration]$Config,
                        [Parameter(Mandatory)]$Http,
                        [Parameter(Mandatory)]$Crypto,
                        [Parameter(Mandatory)]$FileSystem,
                        [Parameter(Mandatory)]$Process
                    )

                    $target = Get-Command -Name 'Install-KeePassXC' -Module 'PSmm.Plugins' -ErrorAction Stop
                    return & $target @PSBoundParameters
                }
            }
        }
    }

    Context 'CLI resolution outcomes' {
        It 'returns existing CLI without invoking installer' {
            InModuleScope PSmm {
                $config = New-TestAppConfiguration
                $fakeCommand = [pscustomobject]@{ Path = 'C:\\Plugins\\keepassxc-cli.exe' }

                Mock Resolve-KeePassCliCommand { [pscustomobject]@{ Command = $fakeCommand; CandidatePaths = @(); ResolvedExecutable = $fakeCommand.Path } } -ModuleName PSmm
                Mock Write-PSmmLog {} -ModuleName PSmm

                $originalEnsure = Get-Command -Name Install-KeePassXC -ErrorAction SilentlyContinue
                $script:ensureCallCount = 0
                function Install-KeePassXC { param($Config,$Http,$Crypto,$FileSystem,$Process) $script:ensureCallCount++ }

                try {
                    $result = Ensure-KeePassCliAvailability -Config $config -Http ([pscustomobject]@{}) -Crypto ([pscustomobject]@{}) -FileSystem ([pscustomobject]@{}) -Process ([pscustomobject]@{})
                    $result | Should -Be $fakeCommand
                    $script:ensureCallCount | Should -Be 0
                }
                finally {
                    if ($originalEnsure) {
                        Set-Item -Path function:Install-KeePassXC -Value $originalEnsure.ScriptBlock -Force
                    }
                    else {
                        Remove-Item -Path function:Install-KeePassXC -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        It 'installs KeePassXC when CLI is missing and retry succeeds' {
            InModuleScope PSmm {
                $config = New-TestAppConfiguration
                $fakeCommand = [pscustomobject]@{ Path = 'D:\\Plugins\\KeePassXC\\keepassxc-cli.exe' }
                Set-Variable -Name mockResolveCallCount -Scope Script -Value 0

                Mock Resolve-KeePassCliCommand {
                    $script:mockResolveCallCount++
                    if ($script:mockResolveCallCount -eq 1) {
                        return [pscustomobject]@{ Command = $null; CandidatePaths = @('D:\\Plugins'); ResolvedExecutable = $null }
                    }
                    return [pscustomobject]@{ Command = $fakeCommand; CandidatePaths = @('D:\\Plugins'); ResolvedExecutable = $fakeCommand.Path }
                } -ModuleName PSmm

                Mock Write-PSmmLog {} -ModuleName PSmm

                $originalEnsure = Get-Command -Name Install-KeePassXC -ErrorAction SilentlyContinue
                $script:ensureCallCount = 0
                function Install-KeePassXC { param($Config,$Http,$Crypto,$FileSystem,$Process) $script:ensureCallCount++; @{ CurrentVersion = '2.7.10'; CurrentInstaller = 'KeePassXC.zip' } }

                try {
                    $result = Ensure-KeePassCliAvailability -Config $config -Http ([pscustomobject]@{}) -Crypto ([pscustomobject]@{}) -FileSystem ([pscustomobject]@{}) -Process ([pscustomobject]@{})
                    $result | Should -Be $fakeCommand
                    $script:ensureCallCount | Should -Be 1
                }
                finally {
                    if ($originalEnsure) {
                        Set-Item -Path function:Install-KeePassXC -Value $originalEnsure.ScriptBlock -Force
                    }
                    else {
                        Remove-Item -Path function:Install-KeePassXC -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        It 'throws when installation completes but CLI is still missing' {
            InModuleScope PSmm {
                $config = New-TestAppConfiguration
                Set-Variable -Name unresolvedCount -Scope Script -Value 0

                Mock Resolve-KeePassCliCommand {
                    $script:unresolvedCount++
                    return [pscustomobject]@{ Command = $null; CandidatePaths = @('X:\\Missing'); ResolvedExecutable = $null }
                } -ModuleName PSmm

                Mock Write-PSmmLog {} -ModuleName PSmm

                $originalEnsure = Get-Command -Name Install-KeePassXC -ErrorAction SilentlyContinue
                $script:ensureCallCount = 0
                function Install-KeePassXC { param($Config,$Http,$Crypto,$FileSystem,$Process) $script:ensureCallCount++; @{ CurrentVersion = ''; CurrentInstaller = '' } }

                try {
                    $threw = $false
                    try {
                        Ensure-KeePassCliAvailability -Config $config -Http ([pscustomobject]@{}) -Crypto ([pscustomobject]@{}) -FileSystem ([pscustomobject]@{}) -Process ([pscustomobject]@{})
                    }
                    catch {
                        $threw = $true
                        $_.Exception.Message | Should -Match 'keepassxc-cli.exe is still missing'
                    }

                    $threw | Should -BeTrue
                    $script:ensureCallCount | Should -Be 1
                }
                finally {
                    if ($originalEnsure) {
                        Set-Item -Path function:Install-KeePassXC -Value $originalEnsure.ScriptBlock -Force
                    }
                    else {
                        Remove-Item -Path function:Install-KeePassXC -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}
