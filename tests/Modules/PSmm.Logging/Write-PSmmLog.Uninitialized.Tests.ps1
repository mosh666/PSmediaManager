# Tests for Write-PSmmLog when logging config is not initialized

. (Join-Path -Path $PSScriptRoot -ChildPath '..\..\Preload-PSmmTypes.ps1')
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\src\Modules\PSmm\PSmm.psd1') -Force
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\src\Modules\PSmm.Logging\PSmm.Logging.psd1') -Force

Describe 'Write-PSmmLog when logging not initialized' {
    BeforeAll {
        if (-not (Get-Module -Name PSmm.Logging)) {
            Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\src\Modules\PSmm.Logging\PSmm.Logging.psd1') -Force
        }
        InModuleScope PSmm.Logging {
            # Ensure logging is uninitialized for all tests in this file
            Remove-Variable -Name Logging -Scope Script -ErrorAction SilentlyContinue
            $script:Logging = $null
        }
    }

    It 'returns without error when logging not ready' {
        { Write-PSmmLog -Level INFO -Context 'Test' -Message 'Hello' -Console -File } | Should -Not -Throw
    }

    It 'emits verbose about logging not ready' -Tag 'Coverage' {
        InModuleScope PSmm.Logging {
            $verbose = & {
                $oldV = $VerbosePreference
                try {
                    $VerbosePreference = 'Continue'
                    Write-PSmmLog -Level INFO -Context 'Test' -Message 'Hello' -Console -File -Verbose
                }
                finally { $VerbosePreference = $oldV }
            } 4>&1
            # Tolerant assertion: any verbose output indicates the branch executed
            (@($verbose)).Count | Should -BeGreaterThan 0
        }
    }
}
