#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'PSmm.Logging module' {
    BeforeAll {
        $localRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $importClassesPath = Join-Path -Path $localRepoRoot -ChildPath 'tests/Support/Import-PSmmClasses.ps1'
        $testConfigPath = Join-Path -Path $localRepoRoot -ChildPath 'tests/Support/TestConfig.ps1'

        . $testConfigPath
        $helperFunctions = @(
            'New-TestAppConfiguration'
            'New-TestRepositoryRoot'
            'New-TestStorageDrive'
            'Add-TestStorageGroup'
        )
        foreach ($helper in $helperFunctions) {
            $command = Get-Command -Name $helper -CommandType Function -ErrorAction Stop
            Set-Item -Path "function:\global:$helper" -Value $command.ScriptBlock -Force
        }

        Set-Item -Path 'function:\global:New-LoggingFileSystemStub' -Value {
            [CmdletBinding()]
            param(
                [string[]]$Directories = @(),
                [hashtable]$Files = @{}
            )

            $directorySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($dir in $Directories) {
                if (-not [string]::IsNullOrWhiteSpace($dir)) {
                    $null = $directorySet.Add($dir)
                }
            }

            $fileMap = [System.Collections.Generic.Dictionary[string, System.DateTime]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($filePath in $Files.Keys) {
                $timestamp = [datetime]$Files[$filePath]
                $fileMap[$filePath] = $timestamp

                $parent = Split-Path -Path $filePath -Parent
                if (-not [string]::IsNullOrWhiteSpace($parent)) {
                    $null = $directorySet.Add($parent)
                }
            }

            $deleted = [System.Collections.Generic.List[string]]::new()
            $created = [System.Collections.Generic.List[string]]::new()
            $cleared = [System.Collections.Generic.List[string]]::new()

            $fs = [pscustomobject]@{
                Directories = $directorySet
                Files = $fileMap
                Deleted = $deleted
                Created = $created
                Cleared = $cleared
            }

            $fs | Add-Member -MemberType ScriptMethod -Name TestPath -Value {
                param([string]$Path)
                if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
                return $this.Directories.Contains($Path) -or $this.Files.ContainsKey($Path)
            }

            $fs | Add-Member -MemberType ScriptMethod -Name GetChildItem -Value {
                param(
                    [string]$Path,
                    [string]$Filter,
                    [string]$ItemType
                )

                $pattern = [System.Management.Automation.WildcardPattern]::new($Filter, 'IgnoreCase')
                $results = @()
                foreach ($entry in $this.Files.GetEnumerator()) {
                    $parent = Split-Path -Path $entry.Key -Parent
                    if ($parent -ne $Path) { continue }
                    $leaf = Split-Path -Path $entry.Key -Leaf
                    if (-not $pattern.IsMatch($leaf)) { continue }
                    $results += [pscustomobject]@{
                        Name = $leaf
                        FullName = $entry.Key
                        LastWriteTime = $entry.Value
                    }
                }
                return $results
            }

            $fs | Add-Member -MemberType ScriptMethod -Name RemoveItem -Value {
                param(
                    [string]$Path,
                    [bool]$Recurse
                )
                if ($this.Files.ContainsKey($Path)) {
                    $null = $this.Files.Remove($Path)
                }
                $null = $this.Deleted.Add($Path)
            }

            $fs | Add-Member -MemberType ScriptMethod -Name NewItem -Value {
                param(
                    [string]$Path,
                    [string]$ItemType
                )
                $null = $this.Directories.Add($Path)
                $null = $this.Created.Add($Path)
                return [pscustomobject]@{ FullName = $Path }
            }

            $fs | Add-Member -MemberType ScriptMethod -Name SetContent -Value {
                param(
                    [string]$Path,
                    [string]$Content
                )
                $null = $this.Cleared.Add($Path)
            }

            return $fs
        } -Force

        . $importClassesPath -RepositoryRoot $localRepoRoot

        $manifestPath = Join-Path -Path $localRepoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'
        if (Get-Module -Name 'PSmm.Logging' -ErrorAction SilentlyContinue) {
            Remove-Module -Name 'PSmm.Logging' -Force
        }
        Import-Module -Name $manifestPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module -Name 'PSmm.Logging' -Force -ErrorAction SilentlyContinue
    }

    Context 'Set-LogContext' {
        BeforeEach {
            InModuleScope 'PSmm.Logging' {
                $script:Context = @{ Context = $null }
            }
        }

        It 'pads the context to 27 characters and stores it for later log entries' {
            Set-LogContext -Context 'Worker#2'

            InModuleScope 'PSmm.Logging' {
                $expected = '[' + 'Worker#2'.PadRight(27) + ']'
                $script:Context.Context | Should -Be $expected
            }
        }

        It 'respects WhatIf and leaves the context unchanged' {
            Set-LogContext -Context 'Worker#2' -WhatIf

            InModuleScope 'PSmm.Logging' {
                $script:Context.Context | Should -Be $null
            }
        }
    }

    Context 'Invoke-LogRotation' {
        It 'deletes files that exceed age and quantity limits' {
            $logRoot = Join-Path -Path $TestDrive -ChildPath 'Logs'
            $files = @{
                (Join-Path -Path $logRoot -ChildPath '2025-01-01.log') = (Get-Date).AddDays(-45)
                (Join-Path -Path $logRoot -ChildPath '2025-02-01.log') = (Get-Date).AddDays(-25)
                (Join-Path -Path $logRoot -ChildPath '2025-02-15.log') = (Get-Date).AddDays(-5)
                (Join-Path -Path $logRoot -ChildPath '2025-03-01.log') = (Get-Date).AddDays(-1)
            }
            $fs = New-LoggingFileSystemStub -Directories @($logRoot) -Files $files

            Invoke-LogRotation -Path $logRoot -MaxAgeDays 30 -MaxFiles 2 -FileSystem $fs -Confirm:$false

            $fs.Deleted | Should -Contain (Join-Path -Path $logRoot -ChildPath '2025-01-01.log')
            $fs.Deleted | Should -Contain (Join-Path -Path $logRoot -ChildPath '2025-02-01.log')
            $fs.Deleted.Count | Should -Be 2
        }

        It 'returns without deleting when no files match criteria' {
            $logRoot = Join-Path -Path $TestDrive -ChildPath 'Logs'
            $fs = New-LoggingFileSystemStub -Directories @($logRoot)

            Invoke-LogRotation -Path $logRoot -MaxAgeDays 1 -MaxFiles 1 -FileSystem $fs -Confirm:$false

            $fs.Deleted.Count | Should -Be 0
        }

        It 'throws when the directory does not exist' {
            $missingPath = Join-Path -Path $TestDrive -ChildPath 'MissingLogs'
            $fs = New-LoggingFileSystemStub

            { Invoke-LogRotation -Path $missingPath -FileSystem $fs -Confirm:$false } | Should -Throw -ExpectedMessage "Log rotation failed: Path not found: $missingPath"
        }
    }

    Context 'Initialize-Logging' {
        BeforeEach {
            InModuleScope 'PSmm.Logging' {
                $script:CallerScopeInvocations = @()
                $script:DefaultLevelInvocations = @()
                $script:DefaultFormatInvocations = @()
                $script:DevLogCalls = @()
            }

            Mock -CommandName Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'PSLogs' } -MockWith { @( [pscustomobject]@{ Name = 'PSLogs' } ) }
            Mock -CommandName Import-Module -ParameterFilter { $Name -eq 'PSLogs' } -MockWith { }
            # Mock the PSLogs functions as they're called from within PSmm.Logging module
            Mock -CommandName Set-LoggingCallerScope -ModuleName 'PSmm.Logging' -MockWith {
                param([int]$CallerScope, [int]$Scope)
                $value = $null
                if ($PSBoundParameters.ContainsKey('CallerScope')) { $value = $CallerScope }
                elseif ($PSBoundParameters.ContainsKey('Scope')) { $value = $Scope }
                elseif ($args.Count -gt 0 -and $args[0] -is [int]) { $value = [int]$args[0] }
                elseif ($args.Count -gt 1 -and $args[1] -is [int]) { $value = [int]$args[1] }
                $global:PSMM_LOG_Scope = $value
                InModuleScope 'PSmm.Logging' {
                    $script:CallerScopeInvocations += $global:PSMM_LOG_Scope
                }
            }
            Mock -CommandName Set-LoggingDefaultLevel -ModuleName 'PSmm.Logging' -MockWith {
                param([string]$Level)
                $global:PSMM_LOG_Level = $Level
                InModuleScope 'PSmm.Logging' {
                    $script:DefaultLevelInvocations += $global:PSMM_LOG_Level
                }
            }
            Mock -CommandName Set-LoggingDefaultFormat -ModuleName 'PSmm.Logging' -MockWith {
                param([string]$Format)
                $global:PSMM_LOG_Format = $Format
                InModuleScope 'PSmm.Logging' {
                    $script:DefaultFormatInvocations += $global:PSMM_LOG_Format
                }
            }
            Mock -CommandName Write-PSmmLog -ModuleName 'PSmm.Logging' -MockWith {
                param(
                    [string]$Level,
                    [string]$Message,
                    [string]$Body,
                    [object]$ErrorRecord,
                    [string]$Context,
                    [switch]$Console,
                    [switch]$File
                )
                $global:PSMM_LOG_LastCall = [pscustomobject]@{
                    Level = $Level
                    Message = $Message
                    Context = $Context
                    Console = $Console.IsPresent
                    File = $File.IsPresent
                }
                InModuleScope 'PSmm.Logging' {
                    $script:DevLogCalls += $global:PSMM_LOG_LastCall
                }
            }
        }

        It 'creates the log directory and configures PSLogs defaults' {
            $config = New-TestAppConfiguration
            $logPath = Join-Path -Path $TestDrive -ChildPath 'logs\psmm.log'
            $logDir = Split-Path -Path $logPath -Parent
            $config.Logging.Path = $logPath
            $config.Logging.DefaultLevel = 'DEBUG'
            $config.Logging.Format = '[%{level}] %{message}'
            $config.Parameters.Dev = $false
            $config.Parameters.NonInteractive = $false

            $fs = New-LoggingFileSystemStub

            Initialize-Logging -Config $config -FileSystem $fs

            $fs.Created | Should -Contain $logDir
            $global:PSMM_LOG_ExpectedFormat = $config.Logging.Format
            InModuleScope 'PSmm.Logging' {
                $script:CallerScopeInvocations | Should -HaveCount 1
                $script:CallerScopeInvocations[0] | Should -Be 2
                $script:DefaultLevelInvocations | Should -Contain 'DEBUG'
                $script:DefaultFormatInvocations | Should -Contain $global:PSMM_LOG_ExpectedFormat
            }
        }

        It 'clears the log file and writes a notification in Dev mode' {
            $config = New-TestAppConfiguration
            $config.Parameters.Dev = $true
            $config.Parameters.NonInteractive = $false
            $logPath = Join-Path -Path $TestDrive -ChildPath 'logs\psmm-dev.log'
            $logDir = Split-Path -Path $logPath -Parent
            $config.Logging.Path = $logPath
            $config.Logging.DefaultLevel = 'INFO'
            $config.Logging.Format = '[%{level}] %{message}'

            $fs = New-LoggingFileSystemStub -Directories @($logDir) -Files @{$logPath = (Get-Date)}

            Initialize-Logging -Config $config -FileSystem $fs

            $fs.Cleared | Should -Contain $logPath
            InModuleScope 'PSmm.Logging' {
                $script:DevLogCalls | Should -HaveCount 1
                $script:DevLogCalls[0].Console | Should -BeTrue
                $script:DevLogCalls[0].File | Should -BeTrue
                $script:DevLogCalls[0].Context | Should -Match '-Dev: Clear logfile'
            }
        }

        Context 'Write-PSmmLog' {
            It 'writes to console and file and sets context' {
                InModuleScope 'PSmm.Logging' {
                    $script:Context = @{ Context = $null }
                }

                $script:__file = $false
                $script:__console = $false
                $script:__writeCalls = @()

                Mock Get-LoggingTarget -ModuleName 'PSmm.Logging' {
                    $o = [pscustomobject]@{}
                    $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { } | Out-Null
                    return $o
                }
                Mock Add-LoggingTarget_File -ModuleName 'PSmm.Logging' { $script:__file = $true }
                Mock Add-LoggingTarget_Console -ModuleName 'PSmm.Logging' { $script:__console = $true }
                Mock -CommandName Set-LogContext -ModuleName 'PSmm.Logging' -MockWith {
                    param([string]$Context)
                    $global:PSMM_TEST_ContextStr = '[' + $Context.PadRight(27) + ']'
                    InModuleScope 'PSmm.Logging' {
                        $script:Context = @{ Context = $global:PSMM_TEST_ContextStr }
                    }
                }
                Mock Write-Log -ModuleName 'PSmm.Logging' {
                    param([string]$Level,[string]$Message,[string]$Body,[object]$ExceptionInfo)
                    $script:__writeCalls += [pscustomobject]@{ Level = $Level; Message = $Message; Body = $Body }
                }
                Mock Wait-Logging -ModuleName 'PSmm.Logging' { }

                Write-PSmmLog -Level INFO -Message 'Hello' -Context 'CTX' -Console -File

                $script:__file | Should -BeTrue
                $script:__console | Should -BeTrue
                $script:__writeCalls | Should -HaveCount 1
                $script:__writeCalls[0].Level | Should -Be 'INFO'
                $script:__writeCalls[0].Message | Should -Match '^\[.{27}\] Hello$'
            }

            It 'does not throw when PSLogs is missing' {
                Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Write-Log' }
                { Write-PSmmLog -Level INFO -Message 'NoPSLogs' } | Should -Not -Throw
            }
        }
    }
}
