#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Repo policy (no runtime compilation / ad-hoc assembly loading)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow Add-Type or Assembly::Load* in repository PowerShell files' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot

        $allowedPaths = @()

        $blockedCommandNames = @(
            'Add-Type'
        )

        # Text patterns are built via concatenation to avoid self-matching this test.
        $blockedTextPatterns = @(
            ('Assembly' + ']::' + 'Load('),
            ('Assembly' + ']::' + 'LoadFrom('),
            ('Assembly' + ']::' + 'LoadFile(')
        )

        $offenders = [System.Collections.Generic.List[object]]::new()

        $repoFiles = @(
            Get-RepoPowerShellFiles -RepoRoot $repoRoot
        )

        foreach ($file in $repoFiles) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path
            if ($allowedPaths -contains $path) { continue }

            $ast = Get-ParsedAstOrThrow -Path $path
            $commands = Get-CommandAsts -Ast $ast

            foreach ($cmd in $commands) {
                $name = $cmd.GetCommandName()
                if (-not $name) { continue }
                if ($blockedCommandNames -notcontains $name) { continue }

                $offenders.Add([pscustomobject]@{
                        Path = $path
                        Line = $cmd.Extent.StartLineNumber
                        Kind = 'Command'
                        Text = $cmd.Extent.Text.Trim()
                    })
            }

            foreach ($pattern in $blockedTextPatterns) {
                $match = $ast.Extent.Text.IndexOf($pattern, [System.StringComparison]::OrdinalIgnoreCase)
                if ($match -lt 0) { continue }

                $offenders.Add([pscustomobject]@{
                        Path = $path
                        Line = 0
                        Kind = 'Text'
                        Text = $pattern
                    })
            }
        }

        if ($offenders.Count -gt 0) {
            $details = (
                $offenders |
                    Sort-Object Path, Line, Kind |
                    ForEach-Object {
                        if ($_.Line -gt 0) {
                            "- $($_.Path):$($_.Line) [$($_.Kind)] => $($_.Text)"
                        }
                        else {
                            "- $($_.Path) [$($_.Kind)] => $($_.Text)"
                        }
                    }
            ) -join [System.Environment]::NewLine

            throw "Disallowed runtime compilation / assembly loading found:`n$details"
        }
    }
}
