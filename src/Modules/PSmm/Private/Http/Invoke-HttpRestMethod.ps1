#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Invoke-HttpRestMethod {
    <#
    .SYNOPSIS
        Internal wrapper around Invoke-RestMethod to standardize common parameters.

    .DESCRIPTION
        Adds -ErrorAction Stop and only forwards supported parameters. This makes
        unit testing much simpler because tests can mock this function instead of
        the built-in cmdlet with complex common parameters.
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
        [AllowNull()]
        [object] $Body
    )

    $params = @{
        Uri = $Uri
        Method = if ([string]::IsNullOrWhiteSpace($Method)) { 'GET' } else { $Method }
        ErrorAction = 'Stop'
    }

    if ($null -ne $Headers -and $Headers.Count -gt 0) { $params.Headers = $Headers }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) { $params.Body = $Body }

    return Invoke-RestMethod @params
}
