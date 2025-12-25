#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'PSmm.UI service-first policy' {

    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'requires injected Process, FileSystem, and PathProvider for Invoke-PSmmUI' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $uiPath = Join-Path -Path $repoRoot -ChildPath 'src\Modules\PSmm.UI\Public\Invoke-PSmmUI.ps1'

        if (-not (Test-Path -LiteralPath $uiPath -PathType Leaf)) {
            throw "Expected Invoke-PSmmUI not found: $uiPath"
        }

        $ast = Get-ParsedAstOrThrow -Path $uiPath

        $func = $ast.Find({
                param($n)
                ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and ($n.Name -eq 'Invoke-PSmmUI')
            }, $true)

        if ($null -eq $func) {
            throw 'Invoke-PSmmUI function definition not found in file.'
        }

        $paramBlock = $func.Body.ParamBlock
        if ($null -eq $paramBlock) {
            throw 'Invoke-PSmmUI is missing a param() block.'
        }

        $required = @('Process', 'FileSystem', 'PathProvider')
        foreach ($name in $required) {
            $p = $paramBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $name } | Select-Object -First 1
            if ($null -eq $p) {
                throw "Invoke-PSmmUI must declare -${name}"
            }

            $hasMandatory = $false
            foreach ($attr in $p.Attributes) {
                $attrName = $null
                try { $attrName = $attr.TypeName.Name } catch { $attrName = $null }
                if ($attrName -eq 'Parameter' -or $attrName -eq 'ParameterAttribute') {
                    foreach ($na in $attr.NamedArguments) {
                        if ($na.ArgumentName -ne 'Mandatory') { continue }

                        # [Parameter(Mandatory)] is a switch argument and may not have an explicit value.
                        if ($null -eq $na.Argument) {
                            $hasMandatory = $true
                            continue
                        }

                        $argText = $na.Argument.Extent.Text
                        if ($argText -notmatch '\$false|false') {
                            $hasMandatory = $true
                        }
                    }
                }
            }

            if (-not $hasMandatory) {
                throw "Invoke-PSmmUI parameter -${name} must be Mandatory"
            }
        }
    }

    It "does not resolve Process/FileSystem/PathProvider inside Invoke-PSmmUI" {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $uiPath = Join-Path -Path $repoRoot -ChildPath 'src\Modules\PSmm.UI\Public\Invoke-PSmmUI.ps1'

        $lines = Get-Content -LiteralPath $uiPath -ErrorAction Stop

        $inBlockComment = $false
        $violations = for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]

            if (-not $inBlockComment -and $line -match '<#') {
                $inBlockComment = $true
            }

            if (-not $inBlockComment) {
                if ($line -match '^\s*#') {
                    continue
                }

                if (
                    ($line -match 'Resolve\(\s*''Process''\s*\)') -or ($line -match 'Resolve\(\s*"Process"\s*\)') -or
                    ($line -match 'Resolve\(\s*''FileSystem''\s*\)') -or ($line -match 'Resolve\(\s*"FileSystem"\s*\)') -or
                    ($line -match 'Resolve\(\s*''PathProvider''\s*\)') -or ($line -match 'Resolve\(\s*"PathProvider"\s*\)')
                ) {
                    [pscustomobject]@{ File = $uiPath; Line = ($i + 1) }
                }
            }

            if ($inBlockComment -and $line -match '#>') {
                $inBlockComment = $false
            }
        }

        if (@($violations).Count -gt 0) {
            $top = $violations | Sort-Object Line | Select-Object -First 25 | ForEach-Object { "$($_.File):$($_.Line)" }
            $list = $top -join [System.Environment]::NewLine
            throw "Invoke-PSmmUI must not resolve Process/FileSystem/PathProvider (inject them instead):${([System.Environment]::NewLine)}$list"
        }
    }
}
