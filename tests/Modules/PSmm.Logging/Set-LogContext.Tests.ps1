#Requires -Version 7.5.4
#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.5' }

BeforeAll {
    $ErrorActionPreference = 'Stop'
    $RootPath = Split-Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent
    
    # Import the module
    $ModulePath = Join-Path $RootPath 'src\Modules\PSmm.Logging\PSmm.Logging.psd1'
    Import-Module $ModulePath -Force
}

Describe 'Set-LogContext' {
    Context 'Context setting' {
        It 'Should set context label' {
            { Set-LogContext -Context 'TestContext' } | Should -Not -Throw
        }
        
        It 'Should accept various context names' {
            { Set-LogContext -Context 'Database' } | Should -Not -Throw
            { Set-LogContext -Context 'UserAuthentication' } | Should -Not -Throw
            { Set-LogContext -Context 'Short' } | Should -Not -Throw
        }
        
        It 'Should output verbose message' {
            $verboseOutput = Set-LogContext -Context 'TestVerbose' -Verbose 4>&1
            
            $verboseOutput | Should -Not -BeNullOrEmpty
            $verboseOutput | Where-Object { $_ -match 'Log context set to' } | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Parameter validation' {
        It 'Should not accept empty context' {
            { Set-LogContext -Context '' } | Should -Throw
        }
        
        It 'Should not accept null context' {
            { Set-LogContext -Context $null } | Should -Throw
        }
        
        It 'Should accept context with spaces' {
            { Set-LogContext -Context 'Context With Spaces' } | Should -Not -Throw
        }
        
        It 'Should accept long context names' {
            { Set-LogContext -Context 'VeryLongContextNameThatExceedsTypicalLength' } | Should -Not -Throw
        }
    }
    
    Context 'ShouldProcess support' {
        It 'Should support WhatIf' {
            { Set-LogContext -Context 'WhatIfTest' -WhatIf } | Should -Not -Throw
        }
        
        It 'Should support Confirm' {
            { Set-LogContext -Context 'ConfirmTest' -Confirm:$false } | Should -Not -Throw
        }
    }
}
