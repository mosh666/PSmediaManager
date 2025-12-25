#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Modules policy (no direct git invocation outside approved files)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow direct git/git.exe command invocations in src/Modules (except explicit allow-list)' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'

        $allowedPaths = @()

        $offenders = [System.Collections.Generic.List[object]]::new()

        $moduleFiles = @(
            Get-ChildItem -LiteralPath $modulesRoot -Filter '*.ps1' -Recurse -File
        )

        foreach ($file in $moduleFiles) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path
            if ($allowedPaths -contains $path) { continue }

            $ast = Get-ParsedAstOrThrow -Path $path
            $calls = Get-CommandAsts -Ast $ast

            foreach ($call in $calls) {
                $cmd = $call.GetCommandName()
                if ([string]::IsNullOrWhiteSpace($cmd)) { continue }

                if ($cmd -ne 'git' -and $cmd -ne 'git.exe') { continue }

                $offenders.Add([pscustomobject]@{
                        Path = $path
                        Line = $call.Extent.StartLineNumber
                        Text = $call.Extent.Text.Trim()
                    })
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Disallowed direct git invocation found in modules (must go through IGitService/IProcessService):`n$details"
        }
    }
}
