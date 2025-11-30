Set-StrictMode -Version Latest

Describe 'Export-SafeConfiguration (_StringifyValues scalar normalization)' -Tag 'SafeExport','Stringify' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\..\..\src\Modules\PSmm\PSmm.psm1'
        Import-Module $modulePath -Force -ErrorAction Stop
    }

    It 'Converts mixed scalar types to expected invariant string values' {
        $now = Get-Date
        $dto = [System.DateTimeOffset]::Now
        $ts = [TimeSpan]::FromHours(1.5)  # 01:30:00
        $cfg = @{
            BoolTrue = $true
            BoolFalse = $false
            SingleVal = [single]12.34001
            DateVal = $now
            DateOffsetVal = $dto
            TimeSpanVal = $ts
            EnumVal = [System.DayOfWeek]::Wednesday
        }
        $outPath = Join-Path $env:TEMP 'dummy-safe-stringify.psd1'
        $exportedPath = Export-SafeConfiguration -Configuration $cfg -Path $outPath -Verbose:$false
        $exportedPath | Should -Be $outPath
        # Validate via raw PSD1 content to avoid parser coercions
        $raw = Get-Content -Path $exportedPath -Raw
        $raw -match "BoolTrue\s*=\s*'True'" | Should -BeTrue
        $raw -match "BoolFalse\s*=\s*'False'" | Should -BeTrue
        $raw -match "SingleVal\s*=\s*'12\.34001'" | Should -BeTrue
        # For dates, just verify the keys exist with opening quote (format varies per environment)
        $raw -match "DateVal\s*=\s*'" | Should -BeTrue
        $raw -match "DateOffsetVal\s*=\s*'" | Should -BeTrue
        $raw -match "TimeSpanVal\s*=\s*'01:30:00'" | Should -BeTrue
        $raw -match "EnumVal\s*=\s*'Wednesday'" | Should -BeTrue
    }
}
