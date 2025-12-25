#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent

    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Interfaces.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Services/CimService.ps1')
}

AfterAll {
    if (Get-Command -Name Reset-InternalCimInstanceProvider -ErrorAction SilentlyContinue) {
        Reset-InternalCimInstanceProvider -Confirm:$false
    }
}

Describe 'CimService provider hook' {
    It 'invokes the injected provider with a hashtable of params' {
        $script:capturedParams = $null
        $script:called = 0

        Set-InternalCimInstanceProvider -Provider {
            param([hashtable]$Params)

            $script:called++
            $script:capturedParams = $Params

            [pscustomobject]@{
                From = 'Provider'
                Params = $Params
            }
        } -Confirm:$false

        $svc = [CimService]::new()

        $filter = @{ Name = 'Anything' }
        $instances = $svc.GetInstances('FakeClass', $filter)

        $script:called | Should -Be 1
        $script:capturedParams | Should -Not -BeNullOrEmpty
        $script:capturedParams['ClassName'] | Should -Be 'FakeClass'
        $script:capturedParams['ErrorAction'] | Should -Be 'Stop'
        $script:capturedParams['Filter'] | Should -Be $filter

        $instances | Should -HaveCount 1
        $instances[0].From | Should -Be 'Provider'
    }
}
