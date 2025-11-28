#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration - Sanitize helper' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'redacts sensitive keys, masks GitHub tokens, and preserves scalar formatting' {
        $exportPath = Join-Path -Path $TestDrive -ChildPath 'sanitize-output.psd1'

        $token = 'ghp_' + ('a' * 40)
        $audit = [pscustomobject]@{
            Token = $token
            Password = 'Pa55w0rd!'
            Timestamp = [datetime]::UtcNow
            Duration = [timespan]::FromMinutes(90)
        }
        $audit | Add-Member -MemberType NoteProperty -Name Loop -Value $audit

        $config = @{
            Metadata = @{
                Secret = 'top-secret'
                ApiKey = 'xyz'
                Nested = @{ Credential = 'abc123' }
            }
            Audit = $audit
        }

        Export-SafeConfiguration -Configuration $config -Path $exportPath
        $imported = Import-PowerShellDataFile -Path $exportPath

        $imported.Metadata.Secret | Should -Be '********'
        $imported.Metadata.ApiKey | Should -Be '********'
        $imported.Metadata.Nested.Credential | Should -Be '********'

        $imported.Audit.Token | Should -Match "ghp_\*+"
        $imported.Audit.Password | Should -Be '********'
        $imported.Audit.Timestamp | Should -Match '\d{4}-\d{2}-\d{2}T'
        $imported.Audit.Duration | Should -Be '01:30:00'
        $imported.Audit.Loop | Should -Be '[CyclicRef]'
    }
}
