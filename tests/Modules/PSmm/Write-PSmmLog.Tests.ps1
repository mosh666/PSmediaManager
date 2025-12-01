Describe 'Write-PSmmLog' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm.Logging/Public/Write-PSmmLog.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'Writes using PSLogs when available' {
        # Provide minimal PSLogs-compatible helper functions (only what's necessary)
        function Write-Log { param($Level, $Message, $Body, $ExceptionInfo) $script:LastWriteLog = @{ Level = $Level; Message = $Message; Body = $Body; Exception = $ExceptionInfo } }
        function Wait-Logging { return }
        function Get-LoggingTarget { return [System.Collections.ArrayList]::new() }
        function Add-LoggingTarget_File { return }
        function Add-LoggingTarget_Console { return }
        function Set-LogContext { param($Context) return }

        # Initialize the variable that Write-Log will set
        $script:LastWriteLog = $null

        # Initialize script-scoped context (the implementation reads $script:Context directly)
        $script:Context = @{ Context = $null }

        # Initialize script-scoped Logging configuration
        $script:Logging = @{ DefaultLevel = 'INFO'; Format = '[%{level}] %{message}' }

        # Call the logger without passing -Context to avoid invoking Set-LogContext
        { Write-PSmmLog -Level 'INFO' -Message 'Hello' -Body 'Details' -Console -File } | Should -Not -Throw

        $script:LastWriteLog | Should -Not -BeNullOrEmpty
        $script:LastWriteLog.Level | Should -Be 'INFO'
        $script:LastWriteLog.Message | Should -Match 'Hello'
        $script:LastWriteLog.Body | Should -Be 'Details'

        # Clean up helpers so other tests aren't affected
        Remove-Item Function:\Get-LoggingTarget -ErrorAction SilentlyContinue
        Remove-Item Function:\Add-LoggingTarget_File -ErrorAction SilentlyContinue
        Remove-Item Function:\Add-LoggingTarget_Console -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-LogContext -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-Log -ErrorAction SilentlyContinue
        Remove-Item Function:\Wait-Logging -ErrorAction SilentlyContinue
    }

    It 'Handles missing PSLogs dependency gracefully' {
        # Ensure PSLogs helpers are absent
        Remove-Item Function:\Get-LoggingTarget -ErrorAction SilentlyContinue
        Remove-Item Function:\Add-LoggingTarget_File -ErrorAction SilentlyContinue
        Remove-Item Function:\Add-LoggingTarget_Console -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-LogContext -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-Log -ErrorAction SilentlyContinue
        Remove-Item Function:\Wait-Logging -ErrorAction SilentlyContinue

        # Initialize script-scoped context and ensure missing dependency is handled without throwing
        $script:Context = @{ Context = $null }
        { Write-PSmmLog -Level 'ERROR' -Message 'NoDeps' -Console -File } | Should -Not -Throw
    }
}
