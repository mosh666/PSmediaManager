#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration - Build-SafeSnapshot registry permutations' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'serializes registry-shaped inputs with nested Master/Backup structures' {
        $exportPath = Join-Path $TestDrive 'registry-perms.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $registry = @{
            Master = @{
                M1 = @{ Label = 'M1'; Path = 'X:\Projects\P1'; SerialNumber = 'SN-M1' }
            }
            Backup = @{
                B1 = @{ Label = 'B1'; Path = 'Y:\Archive'; SerialNumber = 'SN-B1' }
            }
            ProjectDirs = @{ P1 = 'X:\Projects\P1' }
        }

        $cfg = @{ Projects = @{ Registry = $registry } }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        $content | Should -Match '\bRegistry\b'
        $content | Should -Match '\bMaster\b'
        $content | Should -Match 'SN-M1'
        $content | Should -Match 'SN-B1'

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
