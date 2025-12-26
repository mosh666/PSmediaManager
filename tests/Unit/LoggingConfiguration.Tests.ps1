#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $ErrorActionPreference = 'Stop'

    $moduleRoot = (Resolve-Path -Path "$PSScriptRoot\..\..\src\Modules\PSmm").Path
    . (Join-Path -Path $moduleRoot -ChildPath 'Classes\Interfaces.ps1')
    . (Join-Path -Path $moduleRoot -ChildPath 'Classes\ConfigMemberAccess.ps1')
    . (Join-Path -Path $moduleRoot -ChildPath 'Classes\Exceptions.ps1')
    . (Join-Path -Path $moduleRoot -ChildPath 'Classes\UiModels.ps1')
    . (Join-Path -Path $moduleRoot -ChildPath 'Classes\ProjectModels.ps1')
    . (Join-Path -Path $moduleRoot -ChildPath 'Classes\AppConfiguration.ps1')
}

Describe 'LoggingConfiguration' {
    It 'FromObject($null) returns defaults' {
        $cfg = [LoggingConfiguration]::FromObject($null)
        $cfg | Should -Not -BeNullOrEmpty
        $cfg.Level | Should -Be 'INFO'
        $cfg.DefaultLevel | Should -Be 'INFO'
        [string]::IsNullOrWhiteSpace($cfg.Format) | Should -BeFalse
    }

    It 'FromObject maps legacy hashtable shape' {
        $legacy = @{
            Level = 'DEBUG'
            DefaultLevel = 'WARN'
            EnableConsole = $false
            EnableFile = $true
            MaxFileSizeMB = 42
            MaxLogFiles = 7
            PrintBody = $false
            Append = $false
            Encoding = 'utf8'
            PrintException = $false
            ShortLevel = $true
            OnlyColorizeLevel = $true
        }

        $cfg = [LoggingConfiguration]::FromObject($legacy)
        $cfg.Level | Should -Be 'DEBUG'
        $cfg.DefaultLevel | Should -Be 'WARN'
        $cfg.EnableConsole | Should -BeFalse
        $cfg.EnableFile | Should -BeTrue
        $cfg.MaxFileSizeMB | Should -Be 42
        $cfg.MaxLogFiles | Should -Be 7
        $cfg.PrintBody | Should -BeFalse
        $cfg.Append | Should -BeFalse
        $cfg.Encoding | Should -Be 'utf8'
        $cfg.PrintException | Should -BeFalse
        $cfg.ShortLevel | Should -BeTrue
        $cfg.OnlyColorizeLevel | Should -BeTrue
    }

    It 'ToHashtable provides a stable key set' {
        $cfg = [LoggingConfiguration]::new('X:\logs\app.log', 'INFO')
        $cfg.EnableConsole = $false
        $table = $cfg.ToHashtable()

        $table | Should -BeOfType hashtable
        $table.ContainsKey('Path') | Should -BeTrue
        $table.ContainsKey('Level') | Should -BeTrue
        $table.ContainsKey('DefaultLevel') | Should -BeTrue
        $table.ContainsKey('Format') | Should -BeTrue
        $table.ContainsKey('EnableConsole') | Should -BeTrue
        $table.ContainsKey('EnableFile') | Should -BeTrue
        $table.ContainsKey('MaxFileSizeMB') | Should -BeTrue
        $table.ContainsKey('MaxLogFiles') | Should -BeTrue
        $table.ContainsKey('PrintBody') | Should -BeTrue
        $table.ContainsKey('Append') | Should -BeTrue
        $table.ContainsKey('Encoding') | Should -BeTrue
        $table.ContainsKey('PrintException') | Should -BeTrue
        $table.ContainsKey('ShortLevel') | Should -BeTrue
        $table.ContainsKey('OnlyColorizeLevel') | Should -BeTrue

        $table.Path | Should -Be 'X:\logs\app.log'
        $table.Level | Should -Be 'INFO'
        $table.EnableConsole | Should -BeFalse
    }

    It 'FromObject returns input when already typed' {
        $cfg = [LoggingConfiguration]::new('X:\logs\app.log', 'INFO')
        $same = [LoggingConfiguration]::FromObject($cfg)
        $same | Should -Be $cfg
    }
}
