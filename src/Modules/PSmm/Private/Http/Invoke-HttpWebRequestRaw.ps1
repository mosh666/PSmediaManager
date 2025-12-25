#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Invoke-HttpWebRequestRaw {
    <#
    .SYNOPSIS
        Internal wrapper around Invoke-WebRequest for simplified mocking.

    .DESCRIPTION
        Ensures -ErrorAction Stop and forwards only supported parameters.
        Returns the raw Invoke-WebRequest response object so callers can access
        StatusCode and Headers (e.g. ETag) when needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Method = 'GET',

        [Parameter()]
        [hashtable] $Headers,

        [Parameter()]
        [ValidateRange(0, 2147483647)]
        [int] $TimeoutSec = 0
    )

    $params = @{
        Uri = $Uri
        Method = if ([string]::IsNullOrWhiteSpace($Method)) { 'GET' } else { $Method }
        ErrorAction = 'Stop'
    }

    if ($null -ne $Headers -and $Headers.Count -gt 0) { $params.Headers = $Headers }
    if ($TimeoutSec -gt 0) { $params.TimeoutSec = $TimeoutSec }

    return Invoke-WebRequest @params
}
