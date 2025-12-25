#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Invoke-PSmm call policy' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'requires injected core services and -FatalErrorUi for all Invoke-PSmm call sites under src/' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

        $offenders = [System.Collections.Generic.List[object]]::new()

        foreach ($file in Get-ChildItem -LiteralPath $srcRoot -Filter '*.ps1' -Recurse -File) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            $ast = Get-ParsedAstOrThrow -Path $path
            $calls = @(Get-CommandAsts -Ast $ast | Where-Object { $_.GetCommandName() -eq 'Invoke-PSmm' })

            foreach ($call in $calls) {
                $hasFatalErrorUi = $false
                $hasFileSystem = $false
                $hasEnvironment = $false
                $hasPathProvider = $false
                $hasProcess = $false
                $hasHttp = $false
                $hasCrypto = $false

                $hasForbiddenServiceContainer = $false

                foreach ($elem in $call.CommandElements) {
                    if ($elem -is [System.Management.Automation.Language.CommandParameterAst]) {
                        if ($elem.ParameterName -eq 'ServiceContainer') {
                            $hasForbiddenServiceContainer = $true
                            continue
                        }
                        if ($elem.ParameterName -eq 'FatalErrorUi') {
                            $hasFatalErrorUi = $true
                            continue
                        }
                        if ($elem.ParameterName -eq 'FileSystem') {
                            $hasFileSystem = $true
                            continue
                        }
                        if ($elem.ParameterName -eq 'Environment') {
                            $hasEnvironment = $true
                            continue
                        }
                        if ($elem.ParameterName -eq 'PathProvider') {
                            $hasPathProvider = $true
                            continue
                        }
                        if ($elem.ParameterName -eq 'Process') {
                            $hasProcess = $true
                            continue
                        }
                        if ($elem.ParameterName -eq 'Http') {
                            $hasHttp = $true
                            continue
                        }
                        if ($elem.ParameterName -eq 'Crypto') {
                            $hasCrypto = $true
                            continue
                        }
                    }
                }

                $missing = (-not $hasFatalErrorUi) -or (-not $hasFileSystem) -or (-not $hasEnvironment) -or (-not $hasPathProvider) -or (-not $hasProcess) -or (-not $hasHttp) -or (-not $hasCrypto)

                if ($hasForbiddenServiceContainer -or $missing) {
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
            throw "Invoke-PSmm must be called with injected core services (-FileSystem/-Environment/-PathProvider/-Process/-Http/-Crypto) and -FatalErrorUi, and must NOT receive -ServiceContainer:`n$details"
        }
    }
}
