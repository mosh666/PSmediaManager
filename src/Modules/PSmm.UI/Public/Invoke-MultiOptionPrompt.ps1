<#
.SYNOPSIS
    Displays an interactive multi-option prompt for user selection.

.DESCRIPTION
    Creates a console-based multiple-choice prompt using PowerShell's built-in
    PromptForChoice functionality. Supports keyboard shortcuts and default selections.

.PARAMETER Title
    The title displayed at the top of the prompt.

.PARAMETER Message
    The message or question displayed above the options.

.PARAMETER Options
    Array of options in the format "HotKey:Description".
    HotKey should include an ampersand (&) before the shortcut character.
    Example: "Option &1:First Option", "&Yes:Confirm action"

.PARAMETER Default
    Zero-based index of the default option (highlighted by default).

.EXAMPLE
    $options = @('&Yes:Proceed with operation', '&No:Cancel operation')
    $result = Invoke-MultiOptionPrompt -Title 'Confirm' -Message 'Continue?' -Options $options -Default 0
    # Returns 0 for Yes, 1 for No

.EXAMPLE
    $opts = @('Option &1:First choice', 'Option &2:Second choice', 'Option &3:Third choice')
    $selection = Invoke-MultiOptionPrompt -Title 'Choose' -Options $opts

.OUTPUTS
    Int32 - Zero-based index of the selected option.

.NOTES
    Requires an interactive console host. Will not work in non-interactive scenarios.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Invoke-MultiOptionPrompt {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Title = 'Select option',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Message = 'Please select one of the following options:',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$Options = @('Option &1:Option 1', 'Option &2:Option 2', 'Option &3:Option 3'),

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Default = 0
    )

    try {
        Write-Verbose "Displaying prompt: $Title"

        # Validate Default is within Options range
        if ($Default -ge $Options.Count) {
            Write-Warning "Default index $Default exceeds options count. Using 0 instead."
            $Default = 0
        }

        # Create ChoiceDescription objects for each option
        $Choices = [System.Collections.ArrayList]@()

        foreach ($Option in $Options) {
            $parts = $Option -split ':', 2

            if ($parts.Count -ne 2) {
                Write-Warning "Invalid option format: '$Option'. Expected 'HotKey:Description'"
                continue
            }

            $hotKey = $parts[0]
            $description = $parts[1]

            $choice = New-Object System.Management.Automation.Host.ChoiceDescription $hotKey, $description
            [void]$Choices.Add($choice)
        }

        if ($Choices.Count -eq 0) {
            throw "No valid options provided for prompt"
        }

        # Display prompt and get user selection
        $Result = $host.UI.PromptForChoice($Title, $Message, $Choices, $Default)

        Write-Verbose "User selected option index: $Result"
        return $Result
    }
    catch {
        Write-Error "Failed to display multi-option prompt: $_"
        throw
    }
}

#endregion ########## PUBLIC ##########
