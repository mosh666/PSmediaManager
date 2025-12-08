#Requires -Version 7.5.4
Set-StrictMode -Version Latest

$localRepoRoot = (Resolve-Path -Path (Join-Path $PSScriptRoot '..\..\..')).Path
$manifestPath = Join-Path -Path $localRepoRoot -ChildPath 'src/Modules/PSmm.Logging/PSmm.Logging.psd1'

if (Get-Module -Name 'PSmm.Logging' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'PSmm.Logging' -Force
}
Import-Module -Name $manifestPath -Force -ErrorAction Stop

Describe 'Write-PSmmLog' {
    InModuleScope 'PSmm.Logging' {
        BeforeEach {
            $script:Context = @{ Context = $null }
        }

        It 'writes to console and file and sets context' {
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
                $script:Context = @{ Context = '[' + $Context.PadRight(27) + ']' }
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

        It 'handles Body parameter correctly' {
            $script:__writeCalls = @()
            Mock Get-LoggingTarget -ModuleName 'PSmm.Logging' {
                $o = [pscustomobject]@{}
                $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { } | Out-Null
                return $o
            }
            Mock Add-LoggingTarget_File -ModuleName 'PSmm.Logging' { }
            Mock Set-LogContext -ModuleName 'PSmm.Logging' { }
            Mock Write-Log -ModuleName 'PSmm.Logging' {
                param($Level, $Message, $Body, $ExceptionInfo)
                $script:__writeCalls += [pscustomobject]@{ Level = $Level; Message = $Message; Body = $Body }
            }
            Mock Wait-Logging -ModuleName 'PSmm.Logging' { }

            Write-PSmmLog -Level DEBUG -Message 'TestMsg' -Body 'Detailed info' -File

            $script:__writeCalls | Should -HaveCount 1
            $script:__writeCalls[0].Body | Should -Be 'Detailed info'
        }

        It 'handles ErrorRecord parameter' {
            $script:__writeCalls = @()
            Mock Get-LoggingTarget -ModuleName 'PSmm.Logging' {
                $o = [pscustomobject]@{}
                $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { } | Out-Null
                return $o
            }
            Mock Add-LoggingTarget_Console -ModuleName 'PSmm.Logging' { }
            Mock Set-LogContext -ModuleName 'PSmm.Logging' { }
            Mock Write-Log -ModuleName 'PSmm.Logging' {
                param($Level, $Message, $Body, $ExceptionInfo)
                $script:__writeCalls += [pscustomobject]@{
                    Level = $Level
                    Message = $Message
                    HasException = ($null -ne $ExceptionInfo)
                }
            }
            Mock Wait-Logging -ModuleName 'PSmm.Logging' { }

            try {
                throw 'Test error'
            } catch {
                Write-PSmmLog -Level ERROR -Message 'Error occurred' -ErrorRecord $_ -Console
            }

            $script:__writeCalls | Should -HaveCount 1
            $script:__writeCalls[0].HasException | Should -BeTrue
        }

        It 'initializes script context when null' {
            $script:Context = $null
            Mock Get-LoggingTarget -ModuleName 'PSmm.Logging' {
                $o = [pscustomobject]@{}
                $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { } | Out-Null
                return $o
            }
            Mock Add-LoggingTarget_Console -ModuleName 'PSmm.Logging' { }
            Mock Write-Log -ModuleName 'PSmm.Logging' { }
            Mock Wait-Logging -ModuleName 'PSmm.Logging' { }

            { Write-PSmmLog -Level INFO -Message 'Init test' -Console } | Should -Not -Throw
            $script:Context | Should -Not -BeNullOrEmpty
            $script:Context.ContainsKey('Context') | Should -BeTrue
        }

        It 'uses correct log levels' {
            $script:__writeCalls = @()
            Mock Get-LoggingTarget -ModuleName 'PSmm.Logging' {
                $o = [pscustomobject]@{}
                $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { } | Out-Null
                return $o
            }
            Mock Add-LoggingTarget_Console -ModuleName 'PSmm.Logging' { }
            Mock Set-LogContext -ModuleName 'PSmm.Logging' { }
            Mock Write-Log -ModuleName 'PSmm.Logging' {
                param($Level, $Message, $Body, $ExceptionInfo)
                $script:__writeCalls += [pscustomobject]@{ Level = $Level }
            }
            Mock Wait-Logging -ModuleName 'PSmm.Logging' { }

            @('INFO', 'DEBUG', 'WARNING', 'ERROR', 'CRITICAL') | ForEach-Object {
                Write-PSmmLog -Level $_ -Message "Test $_" -Console
            }

            $script:__writeCalls | Should -HaveCount 5
            $script:__writeCalls[0].Level | Should -Be 'INFO'
            $script:__writeCalls[2].Level | Should -Be 'WARNING'
            $script:__writeCalls[4].Level | Should -Be 'CRITICAL'
        }

        It 'clears targets before each write' {
            $script:clearCount = 0
            Mock Get-Command -ModuleName 'PSmm.Logging' -ParameterFilter { $Name -eq 'Get-LoggingTarget' } { return [pscustomobject]@{ Name = 'Get-LoggingTarget' } }
            Mock Get-LoggingTarget -ModuleName 'PSmm.Logging' {
                $o = [pscustomobject]@{}
                $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { $script:clearCount++ } | Out-Null
                return $o
            }
            Mock Add-LoggingTarget_Console -ModuleName 'PSmm.Logging' { }
            Mock Write-Log -ModuleName 'PSmm.Logging' { }
            Mock Wait-Logging -ModuleName 'PSmm.Logging' { }

            Write-PSmmLog -Level INFO -Message 'Test1' -Console
            Write-PSmmLog -Level INFO -Message 'Test2' -Console

            $script:clearCount | Should -BeGreaterThan 1
        }
    }
}
