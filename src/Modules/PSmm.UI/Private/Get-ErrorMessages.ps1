#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Retrieves all error messages from a nested hashtable structure.

.DESCRIPTION
    Recursively traverses a nested hashtable structure to extract all non-empty
    string values, which are treated as error messages. Returns an array of
    collected messages.

.PARAMETER ErrorHashtable
    The hashtable structure containing error messages, potentially nested.

.EXAMPLE
    $errors = @{
        Storage = @{
            Disks = @{
                Master = "Drive not found"
                Backup = "Connection failed"
            }
        }
    }
    $messages = Get-ErrorMessages -ErrorHashtable $errors
    # Returns: @("Drive not found", "Connection failed")

.OUTPUTS
    String[] - Array of error message strings. Returns empty array if no errors found.

.NOTES
    This is an internal helper function used by the UI module to display errors.
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-ErrorMessages {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function retrieves multiple error messages')]
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$ErrorHashtable
    )

    try {
        Write-Verbose 'Collecting error messages from error catalog...'

        $messages = [System.Collections.ArrayList]@()

        # Return empty array if input is null
        if ($null -eq $ErrorHashtable) {
            Write-Verbose 'No errors found (error source is null)'
            return [string[]]@()
        }

        # Preferred: typed catalog
        $uiErrorCatalogType = 'UiErrorCatalog' -as [type]
        if ($uiErrorCatalogType -and ($ErrorHashtable -is $uiErrorCatalogType)) {
            $msgs = $ErrorHashtable.GetAllMessages()
            if ($null -eq $msgs) {
                return [string[]]@()
            }
            return [string[]]$msgs
        }

        # Fallback: catalog-like object with GetAllMessages() method
        if ($ErrorHashtable -and $ErrorHashtable.PSObject -and $ErrorHashtable.PSObject.Methods -and $ErrorHashtable.PSObject.Methods.Match('GetAllMessages').Count -gt 0) {
            $msgs = $ErrorHashtable.GetAllMessages()
            if ($null -eq $msgs) {
                return [string[]]@()
            }
            return [string[]]$msgs
        }

        # Recursively collect error messages (legacy hashtable shape)
        if ($ErrorHashtable -is [hashtable]) {
            if ($ErrorHashtable.Count -eq 0) {
                Write-Verbose 'No errors found (hashtable is empty)'
                return [string[]]@()
            }
            Get-ErrorMessagesRecursive -Hash $ErrorHashtable -MessageList $messages
        }
        else {
            # Unknown shape; nothing to collect
            return [string[]]@()
        }

        $count = $messages.Count
        Write-Verbose "Collected $count error message(s)"

        # Return array
        if ($count -eq 0) {
            return [string[]]@()
        }
        else {
            # Ensure we return a strongly-typed string[] rather than object[]
            return [string[]]$messages.ToArray()
        }
    }
    catch {
        Write-Warning "Failed to retrieve error messages: $_"
        return [string[]]@()
    }
}

<#
.SYNOPSIS
    Internal recursive helper to traverse nested hashtables for error messages.

.PARAMETER Hash
    The current hashtable level being processed.

.PARAMETER MessageList
    The ArrayList collecting error messages.
#>
function Get-ErrorMessagesRecursive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Hash,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.ArrayList]$MessageList
    )

    foreach ($key in $Hash.Keys) {
        $value = $Hash[$key]

        if ($value -is [hashtable]) {
            # Recursively process nested hashtables
            Get-ErrorMessagesRecursive -Hash $value -MessageList $MessageList
        }
        elseif ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
            # Add non-empty string values as error messages
            Write-Verbose "Found error message at key '$key': $value"
            [void]$MessageList.Add($value)
        }
    }
}

#endregion ########## PRIVATE ##########
