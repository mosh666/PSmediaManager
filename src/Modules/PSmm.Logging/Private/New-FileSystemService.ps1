#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function New-FileSystemService {
    <#
    .SYNOPSIS
        Creates a new FileSystemService instance.

    .DESCRIPTION
        Creates and returns a FileSystemService instance. This function requires that the
        FileSystemService class has been loaded into the session (typically by importing
        the PSmm module first).

        NOTE: No fallback mechanism - FileSystemService class must be available.
        If the class is not available, this indicates a DI/service injection issue.

    .EXAMPLE
        $fs = New-FileSystemService
        $exists = $fs.TestPath('C:\temp')

    .OUTPUTS
        FileSystemService - A new instance of the FileSystemService class
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Factory function creates objects but does not modify system state')]
    [CmdletBinding()]
    [OutputType([FileSystemService])]
    param()

        try {
            return [FileSystemService]::new()
        }
        catch {
            throw "FileSystemService type is not available. Logging requires an injected FileSystem service (service-first DI); do not use fallback filesystem shims. Details: $($_.Exception.Message)"
        }
}
