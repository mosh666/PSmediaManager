#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Repo policy (no ampersand invocation anywhere)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow call-operator invocation in any repository PowerShell file' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot

        $allowedPaths = @()

        $offenders = [System.Collections.Generic.List[object]]::new()

        $repoFiles = @(
            Get-RepoPowerShellFiles -RepoRoot $repoRoot
        )

        foreach ($file in $repoFiles) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path
            if ($allowedPaths -contains $path) { continue }

            $ast = Get-ParsedAstOrThrow -Path $path
            $calls = Get-CommandAsts -Ast $ast

            foreach ($call in $calls) {
                if ($call.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Ampersand) { continue }

                $offenders.Add([pscustomobject]@{
                        Path = $path
                        Line = $call.Extent.StartLineNumber
                        Text = $call.Extent.Text.Trim()
                    })
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Disallowed ampersand invocation found in repository PowerShell files:`n$details"
        }
    }
}
