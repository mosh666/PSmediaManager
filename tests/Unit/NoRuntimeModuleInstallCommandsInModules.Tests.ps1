#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Runtime environment policy (no installs/updates in modules)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow module install/update/repository mutation commands in src/Modules' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'

        $bannedCommands = @(
            'Install-Module'
            'Update-Module'
            'Find-Module'
            'Save-Module'
            'Install-PackageProvider'
            'Install-Package'
            'Find-Package'
            'Set-PSRepository'
            'Register-PSRepository'
            'Unregister-PSRepository'
        )

        $offenders = [System.Collections.Generic.List[object]]::new()

        $moduleFiles = @(
            Get-ChildItem -LiteralPath $modulesRoot -Filter '*.ps1' -Recurse -File
            Get-ChildItem -LiteralPath $modulesRoot -Filter '*.psm1' -Recurse -File
        )

        foreach ($file in $moduleFiles) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            $ast = Get-ParsedAstOrThrow -Path $path
            $calls = Get-CommandAsts -Ast $ast

            foreach ($call in $calls) {
                $cmd = $call.GetCommandName()
                if ($null -eq $cmd) { continue }

                if ($cmd -in $bannedCommands) {
                    $offenders.Add([pscustomobject]@{
                            Command = $cmd
                            Path = $path
                            Line = $call.Extent.StartLineNumber
                            Text = $call.Extent.Text.Trim()
                        })
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Command, Path, Line | ForEach-Object { "- $($_.Command) @ $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Disallowed runtime environment mutation commands found under src/Modules:`n$details"
        }
    }
}
