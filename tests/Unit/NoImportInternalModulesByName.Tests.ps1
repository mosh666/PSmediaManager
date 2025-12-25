#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Loader-first policy (no internal module imports by name)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow non-PSmm modules to Import-Module PSmm* by name' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'
        $psmmRoot = Join-Path -Path $modulesRoot -ChildPath 'PSmm'

        $offenders = [System.Collections.Generic.List[object]]::new()

        foreach ($file in Get-ChildItem -LiteralPath $modulesRoot -Filter '*.ps1' -Recurse -File) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            # Allow PSmm itself to manage module imports during bootstrap.
            if ($path.StartsWith($psmmRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $ast = Get-ParsedAstOrThrow -Path $path

            $calls = @(Get-CommandAsts -Ast $ast | Where-Object { $_.GetCommandName() -eq 'Import-Module' })

            foreach ($call in $calls) {
                # Only flag obvious imports by string literal name (avoid false positives for variables).
                foreach ($elem in $call.CommandElements) {
                    if ($elem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $val = $elem.Value
                        if ($val -match '^PSmm(\.|$)') {
                            $offenders.Add([pscustomobject]@{
                                    Path = $path
                                    Line = $call.Extent.StartLineNumber
                                    Text = $call.Extent.Text.Trim()
                                })
                            break
                        }
                    }
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Non-PSmm modules must not import internal PSmm* modules by name (loader-first policy):`n$details"
        }
    }
}
