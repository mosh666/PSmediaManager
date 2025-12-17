#Requires -Version 7.5.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\Modules\PSmm\Classes\Exceptions.ps1')
}

Describe 'ConfigValidationException' {
    It 'formats a multi-line summary from issue objects' {
        $issues = @(
            [pscustomobject]@{ Severity = 'Warning'; Category = 'Schema'; Property = 'UI.Width'; Message = 'Out of range' },
            [pscustomobject]@{ Severity = 'Error'; Category = 'Path'; Property = 'Paths.Root'; Message = 'Missing' }
        )

        $ex = [ConfigValidationException]::new('Configuration validation failed', $issues)

        $ex.Message | Should -Match "UI.Width"
        $ex.Message | Should -Match "Paths.Root"
        $ex.Message | Should -Match "\[Warning\]"
        $ex.Message | Should -Match "\[Error\]"
    }
}
