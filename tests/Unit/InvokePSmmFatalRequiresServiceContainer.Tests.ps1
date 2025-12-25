#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Invoke-PSmmFatal call policy' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'requires -FatalErrorUi for all Invoke-PSmmFatal call sites under src/' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

        $offenders = [System.Collections.Generic.List[object]]::new()

        foreach ($file in Get-ChildItem -LiteralPath $srcRoot -Filter '*.ps1' -Recurse -File) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            $ast = Get-ParsedAstOrThrow -Path $path
            $calls = @(Get-CommandAsts -Ast $ast | Where-Object { $_.GetCommandName() -eq 'Invoke-PSmmFatal' })

            foreach ($call in $calls) {
                $hasFatalErrorUi = $false

                foreach ($elem in $call.CommandElements) {
                    if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                        if ($elem.ParameterName -eq 'FatalErrorUi') {
                            $hasFatalErrorUi = $true
                            break
                        }
                    }
                }

                if (-not $hasFatalErrorUi) {
                    $offenders.Add([pscustomobject]@{
                            Path = $path
                            Line = $call.Extent.StartLineNumber
                            Text = $call.Extent.Text.Trim()
                        })
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Invoke-PSmmFatal must be called with -FatalErrorUi (service-first fatal authority; no container fallback):`n$details"
        }
    }
}
