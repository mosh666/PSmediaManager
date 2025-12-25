#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Import-Module policy (break-fast)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'requires Import-Module calls in src/Modules to use -ErrorAction Stop' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'

        $offenders = [System.Collections.Generic.List[object]]::new()

        $moduleFiles = @(
            Get-ChildItem -LiteralPath $modulesRoot -Filter '*.ps1' -Recurse -File
            Get-ChildItem -LiteralPath $modulesRoot -Filter '*.psm1' -Recurse -File
        )

        foreach ($file in $moduleFiles) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            $ast = Get-ParsedAstOrThrow -Path $path

            $calls = @(Get-CommandAsts -Ast $ast | Where-Object { $_.GetCommandName() -eq 'Import-Module' })

            foreach ($call in $calls) {
                $hasErrorActionStop = $false

                for ($i = 0; $i -lt $call.CommandElements.Count; $i++) {
                    $elem = $call.CommandElements[$i]

                    if ($elem -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                        continue
                    }

                    $paramName = $elem.ParameterName
                    if ($paramName -notin @('ErrorAction', 'EA')) {
                        continue
                    }

                    if ($i -ge ($call.CommandElements.Count - 1)) {
                        continue
                    }

                    $arg = $call.CommandElements[$i + 1]
                    if ($arg -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        if ($arg.Value -eq 'Stop') {
                            $hasErrorActionStop = $true
                            break
                        }
                    }
                }

                if (-not $hasErrorActionStop) {
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
            throw "Import-Module calls must use -ErrorAction Stop (break-fast policy):`n$details"
        }
    }
}
