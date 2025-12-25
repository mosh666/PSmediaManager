#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Service-first core service construction policy' {

    It 'does not directly construct core services in src outside the entrypoint' {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $srcRoot = Join-Path -Path $repoRoot -ChildPath 'src'

        $allowed = @(
            (Join-Path -Path $repoRoot -ChildPath 'src\PSmediaManager.ps1'),
            (Join-Path -Path $repoRoot -ChildPath 'src\Modules\PSmm.Logging\Private\New-FileSystemService.ps1')
        )

        $patterns = @(
            '\[FileSystemService\]::new\s*\(',
            '\[EnvironmentService\]::new\s*\(',
            '\[ProcessService\]::new\s*\(',
            '\[CryptoService\]::new\s*\(',
            '\[HttpService\]::new\s*\(',
            '\[PathProvider\]::new\s*\('
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

                    foreach ($pattern in $patterns) {
                        if ($line -match $pattern) {
                            [pscustomobject]@{ File = $f.FullName; Line = ($i + 1); Match = $pattern }
                        }
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
            throw "Found forbidden direct service construction in src (service-first DI only):${([System.Environment]::NewLine)}$list"
        }
    }
}
