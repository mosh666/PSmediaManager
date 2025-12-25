#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'FatalErrorUi service-first policy' {

    It "does not call Resolve('FatalErrorUi') in src except entrypoint" {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

        $entrypointPath = Join-Path -Path $repoRoot -ChildPath 'src\PSmediaManager.ps1'

        if (-not (Test-Path -LiteralPath $srcRoot -PathType Container)) {
            throw "Expected src root not found: $srcRoot"
        }

        $files = Get-ChildItem -LiteralPath $srcRoot -Recurse -File -ErrorAction Stop |
            Where-Object { $_.Extension -in @('.ps1', '.psm1') }

        $violations = foreach ($f in $files) {
            if ($f.FullName -eq $entrypointPath) {
                continue
            }

            $lines = $null
            try {
                $lines = Get-Content -LiteralPath $f.FullName -ErrorAction Stop
            }
            catch {
                throw "Failed to read file '$($f.FullName)': $($_.Exception.Message)"
            }

            $inBlockComment = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]

                if (-not $inBlockComment -and $line -match '<#') {
                    $inBlockComment = $true
                }

                if (-not $inBlockComment) {
                    if ($line -match '^\s*#') {
                        continue
                    }

                    if (
                        ($line -match 'Resolve\(\s*''FatalErrorUi''\s*\)') -or
                        ($line -match 'Resolve\(\s*"FatalErrorUi"\s*\)')
                    ) {
                        [pscustomobject]@{ File = $f.FullName; Line = ($i + 1) }
                    }
                }

                if ($inBlockComment -and $line -match '#>') {
                    $inBlockComment = $false
                }
            }
        }

        if (@($violations).Count -gt 0) {
            $top = $violations |
                Sort-Object File, Line |
                Select-Object -First 25 |
                ForEach-Object { "$($_.File):$($_.Line)" }

            $list = $top -join [System.Environment]::NewLine
            throw "Found forbidden Resolve('FatalErrorUi') call(s) in src outside entrypoint (inject FatalErrorUi instead):${([System.Environment]::NewLine)}$list"
        }
    }
}
