Set-StrictMode -Version Latest

Describe 'New-CustomFileName edge/error paths' -Tag 'CustomFileName','Edge' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\..\..\src\Modules\PSmm\PSmm.psm1'
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    Context 'Username placeholder resolves via whoami fallback when env is empty' {
        It 'Replaces %username% using whoami and does not warn' {
            $origUser = $env:USERNAME; $origUser2 = $env:USER
            try {
                $env:USERNAME = ''
                $env:USER = ''
                if (-not (Get-Command -Name whoami -ErrorAction SilentlyContinue)) {
                    function whoami { & (Get-Command whoami.exe -ErrorAction Stop) }
                }
                $warnings = @()
                $result = New-CustomFileName -Template 'file-%username%-x.log' -WarningVariable warnings -Verbose:$false
                $actualUser = & whoami
                $expected = 'file-{0}-x.log' -f $actualUser
                $result | Should -Be $expected
                $warnings.Count | Should -Be 0
            }
            finally {
                $env:USERNAME = $origUser
                $env:USER = $origUser2
                Remove-Item function:whoami -ErrorAction SilentlyContinue
            }
        }
    }
}
