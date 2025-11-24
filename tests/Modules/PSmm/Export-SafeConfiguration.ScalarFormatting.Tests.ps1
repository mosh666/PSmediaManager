#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration - Scalar formatting (numbers & booleans)' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'serializes booleans and numbers in a reasonable form' {
        $exportPath = Join-Path $TestDrive 'scalar-formatting.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $cfg = @{ BoolTrue = $true; BoolFalse = $false; Float = 3.14; Int = 42 }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        # Accept multiple representations for booleans (possibly quoted 'True'/'False', $true/$false, or unquoted true/false)
        ($content -match 'BoolTrue.*(?:True|\$true)') | Should -BeTrue
        ($content -match 'BoolFalse.*(?:False|\$false)') | Should -BeTrue

        # Numeric representation should include the numeric text (allow quoted or unquoted)
        $content | Should -Match 'Float\s*=\s*[''"]?3\.14[''"]?'
        $content | Should -Match 'Int\s*=\s*[''"]?42[''"]?'

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
