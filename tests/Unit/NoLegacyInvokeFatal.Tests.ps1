#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'No legacy fatal helper usage' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not reference Invoke-Fatal anywhere under src/' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

        $offenders = [System.Collections.Generic.List[object]]::new()

        foreach ($file in Get-ChildItem -LiteralPath $srcRoot -Filter '*.ps1' -Recurse -File) {
            $path = $file.FullName

            $ast = Get-ParsedAstOrThrow -Path $path

            $calls = @(Get-CommandAsts -Ast $ast | Where-Object { $_.GetCommandName() -eq 'Invoke-Fatal' })

            foreach ($cmd in $calls) {
                $offenders.Add([pscustomobject]@{
                        Path = $path
                        Line = $cmd.Extent.StartLineNumber
                        Text = $cmd.Extent.Text.Trim()
                    })
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Found legacy Invoke-Fatal usage:`n$details"
        }
    }
}
