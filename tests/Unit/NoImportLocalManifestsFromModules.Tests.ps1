#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Loader-first policy (no internal manifest imports from modules)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow src/Modules to Import-Module any local .psd1 manifest path' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'

        $offenders = [System.Collections.Generic.List[object]]::new()

        foreach ($file in Get-ChildItem -LiteralPath $modulesRoot -Filter '*.ps1' -Recurse -File) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path

            $ast = Get-ParsedAstOrThrow -Path $path

            $calls = @(Get-CommandAsts -Ast $ast | Where-Object { $_.GetCommandName() -eq 'Import-Module' })

            foreach ($call in $calls) {
                $text = $call.Extent.Text

                # Policy: modules may import external modules by name, but must NOT import local manifests by path.
                # We treat any '.psd1' mention as a manifest import attempt (path or relative).
                if ($text -match "\.psd1\b") {
                    $offenders.Add([pscustomobject]@{
                            Path = $path
                            Line = $call.Extent.StartLineNumber
                            Text = $text.Trim()
                        })
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "src/Modules must not import local module manifests via Import-Module *.psd1 (loader-first policy):`n$details"
        }
    }
}
