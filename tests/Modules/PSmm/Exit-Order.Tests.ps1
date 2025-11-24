<#
Tests for verifying PSmm exit-order behavior: ensure `Write-PSmmHost` is available
when the application prints its final exit message, and that no missing-symbol
errors occur during shutdown.
#>

Describe 'PSmediaManager exit-order behavior' {

    It 'Prints final exit message and does not error with missing Write-PSmmHost' {
        # Determine repository root from test location
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
        $starter = Join-Path $repoRoot 'Start-PSmediaManager.ps1'

        # Ensure starter exists
        Test-Path $starter | Should -BeTrue

        # Prepare temporary output capture
        $outFile = [System.IO.Path]::GetTempFileName()

        # Resolve pwsh executable
        $pwshCmd = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwshCmd) { $pwshCmd = 'pwsh' }

        # Run in a subprocess but make it CI-friendly:
        # - Set test env flags so app uses test-mode behavior
        # - Stub Get-SystemSecret to avoid interactive KeePass prompts
        $childCmd = @"
[Environment]::SetEnvironmentVariable('MEDIA_MANAGER_TEST_MODE','1','Process')
[Environment]::SetEnvironmentVariable('MEDIA_MANAGER_SKIP_READKEY','1','Process')
function Get-SystemSecret {
    param(
        [string]$SecretType,
        [switch]$AsPlainText,
        [string]$VaultPath
    )
    # Return $null so AppSecrets.LoadSecrets silently continues in tests
    return $null
}
& '$starter' -NonInteractive -Verbose; exit `$LASTEXITCODE
"@

        $args = @('-NoProfile','-NoLogo','-ExecutionPolicy','Bypass','-Command',$childCmd)

        $proc = Start-Process -FilePath $pwshCmd -ArgumentList $args -Wait -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $outFile -PassThru

        $output = Get-Content -Raw -Path $outFile -ErrorAction SilentlyContinue

        # Clean up temp file
        Remove-Item -Path $outFile -ErrorAction SilentlyContinue

        # Assert exit message present and no missing-symbol error
        $output | Should -Match 'PSmediaManager exited successfully'
        $output | Should -NotMatch "The term 'Write-PSmmHost' is not recognized"
    }

}
