#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Side-effect policy (no direct network/process cmdlets in modules)' {
    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"
    }

    It 'does not allow direct Invoke-WebRequest/Invoke-RestMethod/Start-Process usage outside approved wrappers/bootstrap' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $modulesRoot = Join-Path -Path $repoRoot -ChildPath 'src\Modules'

        $bannedCommands = @(
            # Web cmdlets
            'Invoke-WebRequest'
            'Invoke-RestMethod'

            # Common aliases (CommandAst returns alias if used)
            'iwr'
            'irm'

            # Common external download tools
            'curl'
            'curl.exe'
            'wget'
            'wget.exe'

            # Process
            'Start-Process'
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
                if ($cmd -notin $bannedCommands) { continue }

                $isAllowed = $false

                switch ($cmd) {
                    'Invoke-WebRequest' {
                        $isAllowed = $path -like '*\src\Modules\PSmm\Private\Http\*'
                    }
                    'Invoke-RestMethod' {
                        $isAllowed = $path -like '*\src\Modules\PSmm\Private\Http\*'
                    }
                    'iwr' {
                        $isAllowed = $false
                    }
                    'irm' {
                        $isAllowed = $false
                    }
                    'curl' {
                        $isAllowed = $false
                    }
                    'curl.exe' {
                        $isAllowed = $false
                    }
                    'wget' {
                        $isAllowed = $false
                    }
                    'wget.exe' {
                        $isAllowed = $false
                    }
                    'Start-Process' {
                        $isAllowed = $path -like '*\src\Modules\PSmm\Private\Bootstrap\*'
                    }
                }

                if (-not $isAllowed) {
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
            throw "Disallowed direct network/process cmdlets found under src/Modules:`n$details"
        }
    }
}
