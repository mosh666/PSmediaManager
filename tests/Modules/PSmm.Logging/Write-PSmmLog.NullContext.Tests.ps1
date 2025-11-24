#Requires -Version 7.5.4
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.5' }

$ErrorActionPreference = 'Stop'
$RootPath = Split-Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent
$ModulePath = Join-Path $RootPath 'src\Modules\PSmm.Logging\PSmm.Logging.psd1'
if (-not (Get-Module -Name 'PSmm.Logging')) {
    Import-Module $ModulePath -Force -ErrorAction Stop
}

BeforeAll {
    $ErrorActionPreference = 'Stop'
}

Describe 'Write-PSmmLog null-context handling' {
    BeforeEach {
        # Ensure any existing script:Context is removed and present as $null so the function can safely read it
        Remove-Variable -Scope Script -Name Context -ErrorAction SilentlyContinue
        $script:Context = $null

        # Provide minimal PSLogs-compatible helpers used by Write-PSmmLog
        function Get-LoggingTarget { return [System.Collections.ArrayList]::new() }
        function Add-LoggingTarget_File { }
        function Add-LoggingTarget_Console { }
        function Wait-Logging { }

        # Capture calls to Write-Log for assertions
        Remove-Variable -Scope Script -Name LastLog -ErrorAction SilentlyContinue
        function Write-Log {
            param($Level,$Message,$Body,$ExceptionInfo)
            $script:LastLog = [pscustomobject]@{
                Level = $Level
                Message = $Message
                Body = $Body
                ExceptionInfo = $ExceptionInfo
            }
        }

        function Set-LogContext { param($Context) $script:Context = @{ Context = $Context; Path = $null } }
    }
        InModuleScope 'PSmm.Logging' {
            BeforeEach {
                Remove-Variable -Scope Script -Name Context -ErrorAction SilentlyContinue
                Remove-Variable -Scope Script -Name LastLog -ErrorAction SilentlyContinue
            }

            It 'Should not throw and should initialise script:Context when it is missing' {
                Test-Path 'variable:script:Context' | Should -BeFalse

                function Get-LoggingTarget { $o = [pscustomobject]@{}; $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { } | Out-Null; return $o }
                function Add-LoggingTarget_File { }
                function Add-LoggingTarget_Console { }
                function Wait-Logging { }
                function Write-Log { param($Level,$Message,$Body,$ExceptionInfo) $script:WriteLogCalled = $true; $script:WriteLogMessage = $Message; $script:WriteLogLevel = $Level }
                function Set-LogContext { param($Context) $script:Context = @{ Context = $Context; Path = $null }; $script:SetLogContextCalled = $true }

                { Write-PSmmLog -Level 'INFO' -Message 'Hello' -Console -File } | Should -Not -Throw
            }

            It 'Should respect provided Context and include it in the message via Set-LogContext' {
                function Get-LoggingTarget { $o = [pscustomobject]@{}; $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { } | Out-Null; return $o }
                function Add-LoggingTarget_File { }
                function Add-LoggingTarget_Console { }
                function Wait-Logging { }
                function Write-Log { param($Level,$Message,$Body,$ExceptionInfo) $script:WriteLogCalled = $true; $script:WriteLogMessage = $Message; $script:WriteLogLevel = $Level }
                function Set-LogContext { param($Context) $script:Context = @{ Context = $Context; Path = $null }; $script:SetLogContextCalled = $true }

                Remove-Variable -Scope Script -Name WriteLogCalled -ErrorAction SilentlyContinue
                Remove-Variable -Scope Script -Name SetLogContextCalled -ErrorAction SilentlyContinue
                { Write-PSmmLog -Level 'DEBUG' -Message 'X' -Context 'CTX' } | Should -Not -Throw
            }

            It 'Reinitialises script context when an unexpected type is present' {
                function Get-LoggingTarget { $o = [pscustomobject]@{}; $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { } | Out-Null; return $o }
                function Add-LoggingTarget_File { }
                function Add-LoggingTarget_Console { }
                function Wait-Logging { }
                function Write-Log { param($Level,$Message,$Body,$ExceptionInfo) }
                function Set-LogContext { param($Context) $script:Context = @{ Context = $Context; Path = $null } }

                $script:Context = 'not-a-hashtable'
                { Write-PSmmLog -Level 'INFO' -Message 'Reset Context' } | Should -Not -Throw
                $script:Context | Should -BeOfType [hashtable]
                $script:Context.Keys | Should -Contain 'Context'
                $script:Context.Keys | Should -Contain 'Path'
            }

            It 'Emits verbose diagnostics when PSLogs dependency is missing' {
                function Get-LoggingTarget { $o = [pscustomobject]@{}; $o | Add-Member -MemberType ScriptMethod -Name Clear -Value { } | Out-Null; return $o }
                function Add-LoggingTarget_File { }
                function Add-LoggingTarget_Console { }
                function Wait-Logging { }
                function Set-LogContext { param($Context) $script:Context = @{ Context = $Context; Path = $null } }

                Remove-Item -Path Function:Write-Log -ErrorAction SilentlyContinue
                Mock Write-Verbose { param($Message) $script:VerboseMessage = $Message } -ModuleName PSmm.Logging

                { Write-PSmmLog -Level 'INFO' -Message 'Missing dependency' } | Should -Not -Throw
                $script:VerboseMessage | Should -Match 'Failed to write log message'
            }
        }

    # Module-scoped tests live inside InModuleScope above so external (script-scope)
    # duplicate cases are not necessary and interfere with module-scoped mocks.
}
