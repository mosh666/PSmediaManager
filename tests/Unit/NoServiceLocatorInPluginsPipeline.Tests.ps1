Set-StrictMode -Version Latest

Describe 'Architecture: Plugins pipeline is DI-first' {
    It 'does not call ServiceContainer.Resolve in PSmm.Plugins module' {
        $root = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\src\Modules\PSmm.Plugins')).Path

        $files = Get-ChildItem -Path $root -Recurse -Filter '*.ps1' -File
        $matches = foreach ($f in $files) {
            $content = Get-Content -LiteralPath $f.FullName -Raw
            if ($content -match 'ServiceContainer\s*\.\s*Resolve\s*\(') {
                [pscustomobject]@{ Path = $f.FullName }
            }
        }

        if ($matches) {
            $list = ($matches | Select-Object -ExpandProperty Path | Sort-Object | ForEach-Object { "- $_" }) -join [System.Environment]::NewLine
            throw "Found forbidden ServiceContainer.Resolve usage in PSmm.Plugins (inject services instead):$([System.Environment]::NewLine)$list"
        }
    }
}
