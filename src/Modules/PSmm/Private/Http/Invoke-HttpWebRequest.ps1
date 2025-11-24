#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Invoke-HttpWebRequest {
    <#
    .SYNOPSIS
        Internal wrapper around Invoke-WebRequest for simplified mocking.
    .DESCRIPTION
        Ensures -ErrorAction Stop and forwards only the required parameters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Uri,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OutFile
    )

    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -ErrorAction Stop | Out-Null
}
