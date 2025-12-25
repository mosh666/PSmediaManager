#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Modules policy (System.Diagnostics.Process usage only via ProcessService)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow direct Process/ProcessStartInfo type usage in src/Modules outside ProcessService' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'

        $allowedPaths = @(
            (Resolve-Path -LiteralPath (Join-Path -Path $modulesRoot -ChildPath 'PSmm\Classes\Services\ProcessService.ps1')).Path
            # Pre-DI helper used by Get-PSmmDynamicVersion when dot-sourced before module import
            (Resolve-Path -LiteralPath (Join-Path -Path $modulesRoot -ChildPath 'PSmm\Private\Invoke-PSmmNativeProcessCapture.ps1')).Path
        )

        $disallowedTypeNames = @(
            'ProcessStartInfo',
            'System.Diagnostics.ProcessStartInfo',
            'Process',
            'System.Diagnostics.Process',
            'Diagnostics.Process'
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
                if ($disallowedTypeNames -notcontains $typeName) { continue }

                $offenders.Add([pscustomobject]@{
                        Path = $path
                        Line = $node.Extent.StartLineNumber
                        Text = $node.Extent.Text.Trim()
                    })
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Disallowed System.Diagnostics.Process usage found in modules (must go through IProcessService):`n$details"
        }
    }
}
