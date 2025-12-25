#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Service-first ServiceContainer policy' {

    It 'does not create a ServiceContainer in src outside the entrypoint' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

        $allowed = @(
            (Join-Path -Path $repoRoot -ChildPath 'src\PSmediaManager.ps1')
        )

        $files = Get-ChildItem -LiteralPath $srcRoot -Recurse -File -ErrorAction Stop |
            Where-Object { $_.Extension -in @('.ps1', '.psm1') }

        $violations = foreach ($f in $files) {
            if ($allowed -contains $f.FullName) {
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

                if (-not $inBlockComment -and $line -match '<#') { $inBlockComment = $true }

                if (-not $inBlockComment) {
                    if ($line -match '^\s*#') { continue }

                    if ($line -match '\[ServiceContainer\]::new\s*\(') {
                        [pscustomobject]@{ File = $f.FullName; Line = ($i + 1); Match = '[ServiceContainer]::new(' }
                    }

                    if ($line -match '\bNew-Object\s+ServiceContainer\b') {
                        [pscustomobject]@{ File = $f.FullName; Line = ($i + 1); Match = 'New-Object ServiceContainer' }
                    }
                }

                if ($inBlockComment -and $line -match '#>') { $inBlockComment = $false }
            }
        }

        if (@($violations).Count -gt 0) {
            $top = $violations |
                Sort-Object File, Line |
                Select-Object -First 25 |
                ForEach-Object { "$($_.File):$($_.Line) ($($_.Match))" }

            $list = $top -join [System.Environment]::NewLine
            throw "Found forbidden ServiceContainer construction in src (service-first DI only):${([System.Environment]::NewLine)}$list"
        }
    }
}
