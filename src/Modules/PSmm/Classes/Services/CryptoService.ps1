<#
.SYNOPSIS
    Implementation of ICryptoService interface.

.DESCRIPTION
    Provides testable cryptographic operations.
    This service can be mocked in tests for full testability.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System
using namespace System.Security

<#
.SYNOPSIS
    Production implementation of cryptographic service.
#>
class CryptoService : ICryptoService {

    <#
    .SYNOPSIS
        Converts a plain text or encrypted string to a SecureString.

    .DESCRIPTION
        If the input string appears to be a DPAPI encrypted string (starts with
        01000000d08c9ddf), it will be decrypted using ConvertTo-SecureString.
        Otherwise, it will be treated as plain text.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Service method for converting plain text to secure string - callers responsibility to ensure security')]
    [SecureString] ConvertToSecureString([string]$plainText) {
        if ($null -eq $plainText) {
            throw [ArgumentNullException]::new("plainText")
        }

        # Check if this is a DPAPI encrypted string (Windows Data Protection API format)
        if ($plainText -match '^01000000d08c9ddf') {
            # Encrypted string - decrypt it
            return ConvertTo-SecureString -String $plainText
        }
        else {
            # Plain text - convert it
            return ConvertTo-SecureString -String $plainText -AsPlainText -Force
        }
    }

    <#
    .SYNOPSIS
        Converts a SecureString to an encrypted string.
    #>
    [string] ConvertFromSecureString([SecureString]$secureString) {
        if ($null -eq $secureString) {
            throw [ArgumentNullException]::new("secureString")
        }

        return ConvertFrom-SecureString -SecureString $secureString
    }

    <#
    .SYNOPSIS
        Converts a SecureString to plain text.
        WARNING: This exposes the secret in memory. Use with caution.
    #>
    [string] ConvertFromSecureStringAsPlainText([SecureString]$secureString) {
        if ($null -eq $secureString) {
            throw [ArgumentNullException]::new("secureString")
        }

        $ptr = [IntPtr]::Zero
        try {
            $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        }
        finally {
            if ($ptr -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
            }
        }
    }
}
