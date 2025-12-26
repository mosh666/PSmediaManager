#Requires -Version 7.5.4
Set-StrictMode -Version Latest

class FatalErrorUiService : IFatalErrorUiService {
    hidden [bool] $Invoked = $false

    hidden [bool] IsTestMode() {
        try {
            $v = [System.Environment]::GetEnvironmentVariable('MEDIA_MANAGER_TEST_MODE')
            if ([string]::IsNullOrWhiteSpace($v)) { return $false }
            return ($v -eq '1' -or $v -eq 'true' -or $v -eq 'True' -or $v -eq 'TRUE')
        }
        catch {
            return $false
        }
    }

    [void] InvokeFatal(
        [string]$Context,
        [string]$Message,
        [object]$ErrorObject,
        [int]$ExitCode,
        [bool]$NonInteractive
    ) {
        if ($this.Invoked) {
            return
        }
        $this.Invoked = $true

        $ctx = if ([string]::IsNullOrWhiteSpace($Context)) { 'Fatal' } else { $Context }
        $msg = if ([string]::IsNullOrWhiteSpace($Message)) { 'A fatal error occurred.' } else { $Message }
        $code = if ($ExitCode -le 0) { 1 } else { $ExitCode }

        $detail = $null
        try {
            if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
                $detail = $ErrorObject.Exception.Message
            }
            elseif ($ErrorObject -is [System.Exception]) {
                $detail = $ErrorObject.Message
            }
            elseif ($null -ne $ErrorObject) {
                $detail = [string]$ErrorObject
            }
        }
        catch {
            $detail = $null
        }

        try {
            if (Get-Command -Name Write-PSmmLog -ErrorAction SilentlyContinue) {
                if ($detail) {
                    Write-PSmmLog -Level ERROR -Context $ctx -Message ($msg + ' ' + $detail) -Console -File
                }
                else {
                    Write-PSmmLog -Level ERROR -Context $ctx -Message $msg -Console -File
                }
            }
        }
        catch {
            Write-Verbose "[FatalErrorUiService] Logging failed: $($_.Exception.Message)"
        }

        try {
            Write-Host ''
            Write-Host ('########## FATAL ({0}) ##########' -f $ctx) -ForegroundColor Red
            Write-Host $msg -ForegroundColor Red
            if ($detail) {
                Write-Host $detail -ForegroundColor DarkRed
            }
            Write-Host ('ExitCode: {0}' -f $code) -ForegroundColor DarkRed
            Write-Host '#################################' -ForegroundColor Red
            Write-Host ''
        }
        catch {
            Write-Verbose "[FatalErrorUiService] Host output failed: $($_.Exception.Message)"
        }

        if ($this.IsTestMode()) {
            throw [PSmmFatalException]::new($msg, $ctx, $code, $NonInteractive)
        }

        exit $code
    }
}
