<#
.SYNOPSIS
    Centralized host output helper for PSmediaManager.

.DESCRIPTION
    `Write-PSmmHost` centralizes interactive console output. When running
    interactively it writes colored output via `Write-Host`. When running
    non-interactively (scripts, CI, tests) it emits equivalent messages via
    `Write-Verbose` and returns the message object so callers can capture or
    assert on output. This minimizes scattered `Write-Host` usage across the
    codebase while preserving interactive UX.

.PARAMETER Message
    The message to write to the host or output pipeline.

.PARAMETER ForegroundColor
    Optional foreground color name (same set as `Write-Host`).

.PARAMETER NoNewline
    When specified, the message is written without a trailing newline.

.PARAMETER Force
    When specified, forces host output even in non-interactive contexts.

.OUTPUTS
    String - The message written when non-interactive; callers may capture it.

.EXAMPLE
    Write-PSmmHost 'Ready' -ForegroundColor Green

.NOTES
    This function intentionally centralizes `Write-Host` usage. The analyzer
    PSAvoidUsingWriteHost is suppressed on this wrapper with justification.
#>
function Write-PSmmHost {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Wrapper intentionally uses Write-Host for interactive host output; centralizes UX and allows non-interactive paths to avoid Write-Host.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [string]$Message = '',
        [ValidateSet('Black','DarkBlue','DarkGreen','DarkCyan','DarkRed','DarkMagenta','DarkYellow','Gray','DarkGray','Blue','Green','Cyan','Red','Magenta','Yellow','White')]
        [string]$ForegroundColor,
        [switch]$NoNewline,
        [switch]$Force
    )

    process {
        $isInteractive = $false
        try {
            if ($Host -and $Host.UI -and $Host.UI.RawUI) { $isInteractive = $true }
        } catch { $isInteractive = $false }

        if ($isInteractive -or $Force) {
            if ($PSBoundParameters.ContainsKey('NoNewline')) {
                if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
                    Write-Host -NoNewline -ForegroundColor $ForegroundColor $Message
                } else {
                    Write-Host -NoNewline $Message
                }
            } else {
                if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
                    Write-Host -ForegroundColor $ForegroundColor $Message
                } else {
                    Write-Host $Message
                }
            }
        } else {
            # Non-interactive: emit to verbose and return the message so callers/tests can capture
            Write-Verbose $Message
            if ($PSBoundParameters.ContainsKey('NoNewline')) {
                Write-Output -NoEnumerate -InputObject $Message
            } else {
                Write-Output -InputObject $Message
            }
        }
    }
}

Export-ModuleMember -Function Write-PSmmHost
