<#
.SYNOPSIS
    Tests for duplicate serial numbers across storage groups.

.DESCRIPTION
    Checks if any of the provided serial numbers already exist in other storage groups.
    In Interactive mode, warns the user and requests confirmation to proceed.
    In NonInteractive mode, throws an error if duplicates are found.

.PARAMETER Config
    The AppConfiguration object containing current storage groups.

.PARAMETER Serials
    Array of serial numbers to check for duplicates.

.PARAMETER ExcludeGroupId
    Optional group ID to exclude from the duplicate check (used when editing a group).

.PARAMETER NonInteractive
    If set, fails immediately on duplicate without prompting.

.PARAMETER TestInputs
    Test input array for automated testing.

.PARAMETER TestInputIndex
    Current index in test input array (passed by reference).

.OUTPUTS
    Returns $true if user confirms to proceed (or no duplicates found), $false otherwise.

.EXAMPLE
    Test-DuplicateSerial -Config $config -Serials @('ABC123') -ExcludeGroupId '1'

.NOTES
    Respects MEDIA_MANAGER_TEST_INPUTS for testing scenarios.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Test-DuplicateSerial {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AppConfiguration]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AllowEmptyString()]
        [string[]]$Serials,

        [Parameter()]
        [string]$ExcludeGroupId = '',

        [switch]$NonInteractive,

        # TestInputs and TestInputIndex are used via .Value property in Read-DupInput function (ref type usage)
        [Parameter(DontShow)]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TestInputs', Justification='Used via .Value property access in Read-DupInput nested function')]
        [ref]$TestInputs,

        [Parameter(DontShow)]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TestInputIndex', Justification='Used via .Value property access in Read-DupInput nested function')]
        [ref]$TestInputIndex
    )

    # Explicitly mark ref parameters as used so ScriptAnalyzer does not flag them.
    $null = $TestInputs
    $null = $TestInputIndex

    $logAvail = Get-Command Write-PSmmLog -ErrorAction SilentlyContinue
    function Write-DupLog([string]$level, [string]$msg) {
        if ($logAvail) { Write-PSmmLog -Level $level -Context 'DuplicateSerialCheck' -Message $msg -Console -File }
        else { Write-Verbose $msg }
    }

    function Read-DupInput([string]$Prompt) {
        if ($TestInputs.Value -and ($TestInputIndex.Value -lt $TestInputs.Value.Count)) {
            $val = [string]$TestInputs.Value[$TestInputIndex.Value]
            $TestInputIndex.Value++
            return $val
        }
        return Read-Host -Prompt $Prompt
    }

    # Check each serial against existing groups
    $duplicates = @()
    foreach ($serial in $Serials) {
        if ([string]::IsNullOrWhiteSpace($serial)) { continue }

        foreach ($groupKey in $Config.Storage.Keys) {
            # Skip the group being edited
            if ($groupKey -eq $ExcludeGroupId) { continue }

            $group = $Config.Storage[$groupKey]

            # Check Master
            if ($null -ne $group.Master -and $group.Master.SerialNumber -eq $serial) {
                $duplicates += [PSCustomObject]@{
                    Serial = $serial
                    GroupId = $groupKey
                    DriveType = 'Master'
                    Label = $group.Master.Label
                }
            }

            # Check Backups
            if ($null -ne $group.Backups) {
                foreach ($bKey in $group.Backups.Keys) {
                    $backup = $group.Backups[$bKey]
                    if ($backup.SerialNumber -eq $serial) {
                        $duplicates += [PSCustomObject]@{
                            Serial = $serial
                            GroupId = $groupKey
                            DriveType = "Backup $bKey"
                            Label = $backup.Label
                        }
                    }
                }
            }
        }
    }

    # No duplicates found
    if ($duplicates.Count -eq 0) {
        return $true
    }

    # Duplicates found
    $dupGroups = ($duplicates | Select-Object -ExpandProperty GroupId -Unique) -join ', '
    $warningMsg = "Warning: Drive serial number(s) already in use in Storage Group(s): $dupGroups"

    Write-DupLog 'WARNING' $warningMsg

    if ($NonInteractive) {
        # In NonInteractive mode, fail immediately
        $errorMsg = "Duplicate serial number(s) detected in group(s) $dupGroups. Cannot proceed in NonInteractive mode."
        Write-DupLog 'ERROR' $errorMsg
        throw $errorMsg
    }

    # Interactive mode: show details and prompt for confirmation
    Write-Information ''
    Write-PSmmHost $warningMsg -ForegroundColor Yellow
    Write-Information ''
    Write-Information 'Duplicate serial details:'
    foreach ($dup in $duplicates) {
        Write-Information "  - Serial: $($dup.Serial) | Group $($dup.GroupId) | $($dup.DriveType) | Label: $($dup.Label)"
    }
    Write-Information ''
    Write-PSmmHost 'This may indicate the same physical drive is being configured in multiple groups.' -ForegroundColor Yellow
    Write-Information ''

    $response = Read-DupInput 'Continue anyway? (Y/N)'

    if ($response -match '^(?i)y$') {
        Write-DupLog 'NOTICE' 'User confirmed to proceed despite duplicate serials'
        return $true
    }
    else {
        Write-DupLog 'NOTICE' 'User declined to proceed due to duplicate serials'
        return $false
    }
}
