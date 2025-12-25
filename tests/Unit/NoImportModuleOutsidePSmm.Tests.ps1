#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Loader-first policy (PSmm owns module loading)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow Import-Module outside src/Modules/PSmm' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'
        $psmmRoot = Join-Path -Path $modulesRoot -ChildPath 'PSmm'
        $psmmPublicBootstrap = Join-Path -Path $psmmRoot -ChildPath 'Public\Bootstrap'
        $psmmPrivateBootstrap = Join-Path -Path $psmmRoot -ChildPath 'Private\Bootstrap'
        $psmmImportHelper = Join-Path -Path $psmmRoot -ChildPath 'Public\Import-PSmmModuleOrFatal.ps1'

        $offenders = [System.Collections.Generic.List[object]]::new()

        $moduleFiles = @(
            Get-ChildItem -LiteralPath $modulesRoot -Filter '*.ps1' -Recurse -File
            Get-ChildItem -LiteralPath $modulesRoot -Filter '*.psm1' -Recurse -File
        )

        foreach ($file in $moduleFiles) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            $isAllowedOwner =
                $path.StartsWith($psmmPublicBootstrap, [System.StringComparison]::OrdinalIgnoreCase) -or
                $path.StartsWith($psmmPrivateBootstrap, [System.StringComparison]::OrdinalIgnoreCase) -or
                ($path -eq $psmmImportHelper)

            $ast = Get-ParsedAstOrThrow -Path $path

            $calls = @(Get-CommandAsts -Ast $ast | Where-Object { $_.GetCommandName() -eq 'Import-Module' })

            foreach ($call in $calls) {
                if ($isAllowedOwner) {
                    continue
                }
                $offenders.Add([pscustomobject]@{
                        Path = $path
                        Line = $call.Extent.StartLineNumber
                        Text = $call.Extent.Text.Trim()
                    })
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Import-Module must only be used within PSmm bootstrap (Public/Bootstrap, Private/Bootstrap) or Import-PSmmModuleOrFatal.ps1:`n$details"
        }
    }
}
