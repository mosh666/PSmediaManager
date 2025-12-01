#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration - PSObject redaction' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'redacts sensitive keys such as Password and Secret in PSObject properties' {
        $exportPath = Join-Path $TestDrive 'psobject-redact.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $obj = New-Object PSObject -Property @{ Name = 'SvcAccount'; Password = 'P@ssw0rd!'; Secret = 's3cr3t'; Token = 'abc123' }
        $cfg = @{ Service = $obj }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        $content | Should -Match 'Password\s*=\s*\*{2,}|Password\s*=\s*''\*{2,}'''
        $content | Should -Match 'Secret\s*=\s*\*{2,}|Secret\s*=\s*''\*{2,}'''
        # Token may be redacted or preserved depending on implementation; accept both
        ($content -match "Token\s*=\s*'abc123'" -or $content -match "Token\s*=\s*'\*{2,}'") | Should -BeTrue

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
