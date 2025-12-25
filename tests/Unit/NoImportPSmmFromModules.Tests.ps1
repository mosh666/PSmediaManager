#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Loader-first policy (no internal PSmm imports)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow src/Modules to Import-Module PSmm.psd1' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'

        $offenders = [System.Collections.Generic.List[object]]::new()

        foreach ($file in Get-ChildItem -LiteralPath $modulesRoot -Filter '*.ps1' -Recurse -File) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            $ast = Get-ParsedAstOrThrow -Path $path

            $calls = @(Get-CommandAsts -Ast $ast | Where-Object { $_.GetCommandName() -eq 'Import-Module' })

            foreach ($call in $calls) {
                $text = $call.Extent.Text

                # Block any attempt to Import-Module a PSmm manifest by path/name.
                if ($text -match "PSmm\\PSmm\.psd1" -or $text -match "PSmm\.psd1") {
                    $offenders.Add([pscustomobject]@{
                            Path = $path
                            Line = $call.Extent.StartLineNumber
                            Text = $text.Trim()
                        })
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "src/Modules must not import PSmm (loader-first policy):`n$details"
        }
    }
}
