#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Fatal banner is centralized' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not emit ad-hoc FATAL banners outside approved files' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

        $allowed = @(
            Join-Path -Path $srcRoot -ChildPath 'Modules/PSmm/Classes/Services/FatalErrorUiService.ps1'
        ) | ForEach-Object { (Resolve-Path -LiteralPath $_).Path }

        $offenders = [System.Collections.Generic.List[object]]::new()

        foreach ($file in Get-ChildItem -LiteralPath $srcRoot -Filter '*.ps1' -Recurse -File) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            $ast = Get-ParsedAstOrThrow -Path $path

            $strings = $ast.FindAll({
                    param($node)
                    return ($node -is [System.Management.Automation.Language.StringConstantExpressionAst])
                }, $true)

            foreach ($s in $strings) {
                if ($s.Value -match '^##########\s+FATAL') {
                    if ($allowed -notcontains $path) {
                        $offenders.Add([pscustomobject]@{
                                Path = $path
                                Line = $s.Extent.StartLineNumber
                                Text = $s.Extent.Text.Trim()
                            })
                    }
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Found disallowed ad-hoc FATAL banner string(s):`n$details"
        }
    }
}
