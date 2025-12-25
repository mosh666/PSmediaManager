#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Invoke-PSmmNativeProcessCapture {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter()]
        [string[]]$ArgumentList
    )

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        foreach ($arg in @($ArgumentList)) {
            if ($null -ne $arg) {
                $null = $psi.ArgumentList.Add([string]$arg)
            }
        }

        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        return [pscustomobject]@{
            ExitCode = [int]$proc.ExitCode
            StdOut   = [string]$stdout
            StdErr   = [string]$stderr
            Success  = ($proc.ExitCode -eq 0)
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = 1
            StdOut   = ''
            StdErr   = [string]$_
            Success  = $false
        }
    }
}
