#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Plugins policy (no Expand-Archive in plugin definitions)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow Expand-Archive usage in src/Modules/PSmm.Plugins/Private/Plugins' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $pluginsRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules\PSmm.Plugins\Private\Plugins'

        $offenders = [System.Collections.Generic.List[object]]::new()

        $pluginFiles = @(
            Get-ChildItem -LiteralPath $pluginsRoot -Filter '*.ps1' -Recurse -File
        )

        foreach ($file in $pluginFiles) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            $ast = Get-ParsedAstOrThrow -Path $path
            $calls = Get-CommandAsts -Ast $ast

            foreach ($call in $calls) {
                $cmd = $call.GetCommandName()
                if ($cmd -ne 'Expand-Archive') { continue }

                $offenders.Add([pscustomobject]@{
                        Path = $path
                        Line = $call.Extent.StartLineNumber
                        Text = $call.Extent.Text.Trim()
                    })
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Disallowed Expand-Archive usage found in plugin definition scripts:`n$details"
        }
    }
}
