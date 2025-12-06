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
        If the class is not available, this indicates a module loading order issue.

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

    # Verify FileSystemService class is available
    try {
        $null = [FileSystemService]
    }
    catch {
        $msg = @(
            'FileSystemService class is not available in the session.'
            'This typically indicates a module loading order issue.'
            'Ensure the PSmm module is imported before using logging functions.'
            'Error: ' + $_.Exception.Message
        ) -join ' '
        throw [InvalidOperationException]::new($msg, $_.Exception)
    }

    # Create and return a new instance
    return [FileSystemService]::new()
}
