#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Displays an invalid selection message to the user.

.DESCRIPTION
    Helper function to show a standardized error message when user
    enters an invalid menu selection. This is an internal function
    used only within the PSmm.UI module.
#>
function Show-InvalidSelection {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Wait
    )

    Write-PSmmHost ''
    $InvalidColumns = @(
        New-UiColumn -Text 'Invalid selection, please try again.' -Width 80 -Alignment 'c'
    )
    # Use no decorative border; 'None' previously produced a literal 'N' border due to non-empty string.
    # Pass empty string to suppress border characters entirely.
    Format-UI -Columns $InvalidColumns -Width 80 -Border ''
    Write-PSmmHost ''
    if ($Wait) { Pause } else { Start-Sleep -Milliseconds 500 }
}
