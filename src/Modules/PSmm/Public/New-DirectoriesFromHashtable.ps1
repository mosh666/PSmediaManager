<#
.SYNOPSIS
    Creates directory structures from a hashtable definition.

.DESCRIPTION
    Recursively processes a hashtable structure and creates directories for all valid path entries.
    Supports nested hashtables for hierarchical directory structures. Only creates directories
    for string values that represent valid paths; other value types are skipped.

.PARAMETER Structure
    A hashtable containing directory paths as values. Can contain nested hashtables
    for recursive directory creation.

.EXAMPLE
    $Paths = @{
        Root = 'C:\App'
        Logs = 'C:\App\Logs'
        Data = @{
            Input = 'C:\App\Data\Input'
            Output = 'C:\App\Data\Output'
        }
    }
    New-DirectoriesFromHashtable -Structure $Paths
    
    Creates all directories defined in the hashtable structure.

.EXAMPLE
    New-DirectoriesFromHashtable -Structure $Run.App.Paths -Verbose
    
    Creates directories with verbose output showing each operation.

.INPUTS
    Hashtable - Structure containing directory paths and nested hashtables

.OUTPUTS
    None - Creates directories as a side effect

.NOTES
    Function Name: New-DirectoriesFromHashtable
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Last Modified: 2025-10-26
    
    Only creates directories for valid path strings. Other value types are skipped with verbose output.
    Existing directories are not recreated.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function New-DirectoriesFromHashtable {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [hashtable]$Structure
    )

    begin {
        Write-Verbose "Starting directory creation from hashtable structure"
    }

    process {
        foreach ($key in $Structure.Keys) {
            $value = $Structure[$key]
            
            # Handle string values that represent valid paths
            if ($value -is [string]) {
                # Only process absolute paths or paths starting with known PowerShell drives
                $isAbsolutePath = [System.IO.Path]::IsPathRooted($value) -or $value -match '^[A-Za-z]+:[/\\]'
                
                if ($isAbsolutePath -and (Test-Path -IsValid $value)) {
                    if (-not (Test-Path -Path $value -PathType Container)) {
                        if ($PSCmdlet.ShouldProcess($value, 'Create directory')) {
                            Write-Verbose "Creating directory: $value"
                            try {
                                $null = New-Item -Path $value -ItemType Directory -Force -ErrorAction Stop
                            }
                            catch {
                                Write-Warning "Failed to create directory '$value': $_"
                            }
                        }
                    }
                    else {
                        Write-Verbose "Directory already exists: $value"
                    }
                }
                elseif (-not $isAbsolutePath) {
                    Write-Verbose "Skipping relative or invalid path for key '$key': $value"
                }
                else {
                    Write-Warning "Invalid path for key '$key': $value"
                }
            }
            # Handle nested hashtables recursively
            elseif ($value -is [hashtable]) {
                Write-Verbose "Processing nested structure for key: $key"
                New-DirectoriesFromHashtable -Structure $value
            }
            # Skip non-path values
            else {
                Write-Verbose "Skipping key '$key' - value type: $($value.GetType().Name), value: $value"
            }
        }
    }

    end {
        Write-Verbose "Directory creation completed"
    }
}

#endregion ########## PUBLIC ##########
