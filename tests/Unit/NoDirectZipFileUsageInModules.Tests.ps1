#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Modules policy (ZipFile usage only via FileSystemService)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow direct ZipFile type usage in src/Modules outside FileSystemService' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'

        $allowedPaths = @(
            (Resolve-Path -LiteralPath (Join-Path -Path $modulesRoot -ChildPath 'PSmm\Classes\Services\FileSystemService.ps1')).Path
        )

        $offenders = [System.Collections.Generic.List[object]]::new()

        $moduleFiles = @(
            Get-ChildItem -LiteralPath $modulesRoot -Filter '*.ps1' -Recurse -File
        )

        foreach ($file in $moduleFiles) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path
            if ($allowedPaths -contains $path) { continue }

            $ast = Get-ParsedAstOrThrow -Path $path

            $typeNodes = $ast.FindAll({
                    param($n)
                    ($n -is [System.Management.Automation.Language.TypeExpressionAst]) -or
                    ($n -is [System.Management.Automation.Language.TypeConstraintAst])
                }, $true)

            foreach ($node in $typeNodes) {
                $typeName = $node.TypeName.FullName
                if ($typeName -ne 'ZipFile' -and $typeName -ne 'System.IO.Compression.ZipFile') { continue }

                $offenders.Add([pscustomobject]@{
                        Path = $path
                        Line = $node.Extent.StartLineNumber
                        Text = $node.Extent.Text.Trim()
                    })
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Disallowed ZipFile usage found in modules (must go through IFileSystemService.ExtractZip):`n$details"
        }
    }
}
