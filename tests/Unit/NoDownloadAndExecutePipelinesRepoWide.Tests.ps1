#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Repo policy (no download-and-execute pipelines)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow piping web downloads directly into a shell interpreter' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot

        $allowedPaths = @()

        $downloaders = @(
            'Invoke-WebRequest',
            'iwr',
            'Invoke-RestMethod',
            'irm',
            'curl',
            'curl.exe',
            'wget',
            'wget.exe'
        )

        $shells = @(
            'sh',
            'bash',
            'zsh',
            'fish',
            'cmd',
            'cmd.exe',
            'powershell',
            'powershell.exe',
            'pwsh',
            'pwsh.exe'
        )

        $offenders = [System.Collections.Generic.List[object]]::new()

        $repoFiles = @(
            Get-RepoPowerShellFiles -RepoRoot $repoRoot
        )

        foreach ($file in $repoFiles) {
            $path = (Resolve-Path -LiteralPath $file.FullName).Path
            if ($allowedPaths -contains $path) { continue }

            $ast = Get-ParsedAstOrThrow -Path $path
            $pipelines = Get-PipelineAsts -Ast $ast

            foreach ($pl in $pipelines) {
                $elements = @($pl.PipelineElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandAst] })
                if ($elements.Count -lt 2) { continue }

                $first = [System.Management.Automation.Language.CommandAst]$elements[0]
                $last = [System.Management.Automation.Language.CommandAst]$elements[$elements.Count - 1]

                $firstName = $first.GetCommandName()
                $lastName = $last.GetCommandName()
                if (-not $firstName -or -not $lastName) { continue }

                if (($downloaders -contains $firstName) -and ($shells -contains $lastName)) {
                    $offenders.Add([pscustomobject]@{
                            Path = $path
                            Line = $pl.Extent.StartLineNumber
                            Text = $pl.Extent.Text.Trim()
                        })
                }
            }
        }

        if ($offenders.Count -gt 0) {
            $details = ($offenders | Sort-Object Path, Line | ForEach-Object { "- $($_.Path):$($_.Line) => $($_.Text)" }) -join [System.Environment]::NewLine
            throw "Disallowed download-and-execute pipeline found:`n$details"
        }
    }
}
