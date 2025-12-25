#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Repo policy (no pwsh/powershell -Command style execution)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow pwsh/powershell to be invoked with -Command/-EncodedCommand (directly or via Start-Process)' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot

        $allowedPaths = @()

        $shellNames = @(
            'pwsh',
            'pwsh.exe',
            'powershell',
            'powershell.exe'
        )

        $blockedFlags = @(
            '-Command',
            '-c',
            '-EncodedCommand',
            '-ec'
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

                # 1) Direct invocation: pwsh -Command ...
                if ($shellNames -contains $name) {
                    foreach ($el in $cmd.CommandElements) {
                        $text = $null
                        if ($el -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            $text = $el.Value
                        }
                        else {
                            $text = $el.Extent.Text
                        }

                        if ($blockedFlags -contains $text) {
                            $offenders.Add([pscustomobject]@{
                                    Path = $path
                                    Line = $cmd.Extent.StartLineNumber
                                    Text = $cmd.Extent.Text.Trim()
                                })
                            break
                        }
                    }

                    continue
                }

                # 2) Start-Process -FilePath pwsh -ArgumentList '-Command', ...
                if ($name -ne 'Start-Process') { continue }

                $elements = $cmd.CommandElements
                if ($elements.Count -lt 2) { continue }

                $filePathValue = $null
                $argumentListText = @()

                # Positional FilePath (first arg after Start-Process)
                $firstArg = $elements[1]
                if ($firstArg -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                    if ($firstArg -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $filePathValue = $firstArg.Value
                    }
                }

                for ($i = 1; $i -lt $elements.Count; $i++) {
                    $el = $elements[$i]
                    if ($el -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

                    $paramName = $el.ParameterName
                    if (-not $paramName) { continue }

                    if ($paramName -ieq 'FilePath') {
                        if (($i + 1) -lt $elements.Count) {
                            $val = $elements[$i + 1]
                            if ($val -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                                $filePathValue = $val.Value
                            }
                        }
                        continue
                    }

                    if ($paramName -ieq 'ArgumentList') {
                        if (($i + 1) -lt $elements.Count) {
                            $val = $elements[$i + 1]
                            if ($val -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                                foreach ($item in $val.Elements) {
                                    if ($item -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                                        $argumentListText += $item.Value
                                    }
                                    else {
                                        $argumentListText += $item.Extent.Text
                                    }
                                }
                            }
                            elseif ($val -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                                $argumentListText += $val.Value
                            }
                            else {
                                $argumentListText += $val.Extent.Text
                            }
                        }
                        continue
                    }
                }

                if (-not $filePathValue) { continue }
                if ($shellNames -notcontains $filePathValue) { continue }

                foreach ($arg in $argumentListText) {
                    foreach ($flag in $blockedFlags) {
                        if ($arg -ieq $flag) {
                            $offenders.Add([pscustomobject]@{
                                    Path = $path
                                    Line = $cmd.Extent.StartLineNumber
                                    Text = $cmd.Extent.Text.Trim()
                                })
                            break
                        }
                    }
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Disallowed pwsh/powershell -Command style invocation found:`n$details"
        }
    }
}
