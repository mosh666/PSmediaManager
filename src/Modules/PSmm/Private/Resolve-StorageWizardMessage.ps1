<#
.SYNOPSIS
    Resolves standardized messages for the Storage Wizard with stable IDs.

.DESCRIPTION
    Returns a hashtable with Id and Text fields for consistent logging and UI prompts.
    Message IDs are stable for testing and troubleshooting.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Resolve-StorageWizardMessage {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter()]
        [hashtable]$Arguments
    )

    $messages = @{
        'PSMM-STORAGE-NO-USB'              = 'No USB/removable drives detected; skipping storage configuration for now. Connect a USB drive and retry via "Reconfigure Storage".'
        'PSMM-STORAGE-DUPLICATE-SERIAL'    = 'Duplicate device selection rejected: the same SerialNumber cannot be used more than once in a group.'
        'PSMM-STORAGE-MASTER-BACKUP-COLLISION' = 'Selection rejected: the same device cannot be both Master and Backup.'
        'PSMM-STORAGE-OVERWRITE'           = 'A storage configuration already exists. Overwrite PSmm.Storage.psd1?'
        'PSMM-STORAGE-SUMMARY'             = 'Review your selections and confirm to write PSmm.Storage.psd1.'
    }

    $text = $messages[$Key]
    if ([string]::IsNullOrWhiteSpace($text)) {
        $text = "Unknown message key: $Key"
    }

    # Optional lightweight templating with {Name} placeholders
    if ($Arguments) {
        foreach ($k in $Arguments.Keys) {
            $placeholder = '{' + $k + '}'
            $text = $text -replace [regex]::Escape($placeholder), [string]$Arguments[$k]
        }
    }

    return @{ Id = $Key; Text = $text }
}
