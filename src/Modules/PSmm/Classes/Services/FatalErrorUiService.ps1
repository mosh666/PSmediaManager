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
        [object]$Error,
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
            if ($Error -is [System.Management.Automation.ErrorRecord]) {
                $detail = $Error.Exception.Message
            }
            elseif ($Error -is [System.Exception]) {
                $detail = $Error.Message
            }
            elseif ($null -ne $Error) {
                $detail = [string]$Error
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
            # Never let logging failure block fatal handling
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
            # ignore host write failures
        }

        if ($this.IsTestMode()) {
            throw [PSmmFatalException]::new($msg, $ctx, $code, $NonInteractive)
        }

        exit $code
    }
}
