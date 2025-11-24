#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration - StringifyValues path extraction' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'stringifies nested object properties and preserves member names' {
        $exportPath = Join-Path $TestDrive 'stringify-paths.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $nested = [pscustomobject]@{ Sub = 'svalue'; Count = 7 }
        $obj = [pscustomobject]@{ Name = 'Parent'; Nested = $nested; Info = @{ Key = 'V' } }
        $cfg = @{ Demo = $obj }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        # Ensure parent and nested member names appear in output
        $content | Should -Match '\bDemo\b'
        $content | Should -Match '\bNested\b'
        $content | Should -Match '\bSub\b'
        $content | Should -Match 'svalue'

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
