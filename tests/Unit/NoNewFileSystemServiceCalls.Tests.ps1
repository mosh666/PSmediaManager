#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Service-first FileSystem policy' {

    It 'does not invoke New-FileSystemService anywhere in src (no ad-hoc filesystem construction)' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

        $selfPath = $PSCommandPath
        $definitionPath = Join-Path -Path $repoRoot -ChildPath 'src\Modules\PSmm.Logging\Private\New-FileSystemService.ps1'

        if (-not (Test-Path -LiteralPath $srcRoot -PathType Container)) {
            throw "Expected src root not found: $srcRoot"
        }

        $files = Get-ChildItem -LiteralPath $srcRoot -Recurse -File -ErrorAction Stop |
            Where-Object { $_.Extension -in @('.ps1', '.psm1') }

        $violations = foreach ($f in $files) {
            if ($null -ne $selfPath -and $f.FullName -eq $selfPath) {
                continue
            }

            # Allow the helper definition file itself; we only forbid invocations elsewhere.
            if ($f.FullName -eq $definitionPath) {
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

                    if ($line -match '^\s*function\s+New-FileSystemService\b') {
                        continue
                    }

                    if ($line -match '\bNew-FileSystemService\b') {
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
            throw "Found forbidden invocation(s) of New-FileSystemService in src (service-first DI only):${([System.Environment]::NewLine)}$list"
        }
    }
}
