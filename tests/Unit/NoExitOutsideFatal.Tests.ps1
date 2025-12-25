#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'No direct exit outside fatal service' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not use exit outside FatalErrorUiService' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

        $allowedExitFile = Join-Path -Path $srcRoot -ChildPath 'Modules/PSmm/Classes/Services/FatalErrorUiService.ps1'
        $allowedExitFile = (Resolve-Path -LiteralPath $allowedExitFile).Path

        $offenders = [System.Collections.Generic.List[object]]::new()

        foreach ($file in Get-ChildItem -LiteralPath $srcRoot -Filter '*.ps1' -Recurse -File) {
            $path = $file.FullName

            $ast = Get-ParsedAstOrThrow -Path $path
            $exitCommands = @(Get-CommandAsts -Ast $ast | Where-Object { $_.GetCommandName() -eq 'exit' })

            if ($exitCommands.Count -gt 0) {
                $resolved = (Resolve-Path -LiteralPath $path).Path
                if ($resolved -ne $allowedExitFile) {
                    foreach ($cmd in $exitCommands) {
                        $offenders.Add([pscustomobject]@{
                                Path = $resolved
                                Line = $cmd.Extent.StartLineNumber
                                Text = $cmd.Extent.Text.Trim()
                            })
                    }
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Found disallowed exit usage outside FatalErrorUiService:`n$details"
        }
    }
}
