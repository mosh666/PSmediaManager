<#
.SYNOPSIS
    Displays storage configuration information.

.DESCRIPTION
    Formats and displays the configured storage devices, including Master and Backup drives.
    Shows drive letter, label, serial number, and availability status.

.PARAMETER Config
    The AppConfiguration object containing storage configuration.

.PARAMETER ShowDetails
    If specified, shows detailed drive information including manufacturer, model, capacity, etc.

.EXAMPLE
    Show-StorageInfo -Config $appConfig

.EXAMPLE
    Show-StorageInfo -Config $appConfig -ShowDetails

.NOTES
    This function is useful for debugging and displaying the current storage configuration.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PUBLIC ##########

function Show-StorageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

        [Parameter()]
        [switch]$ShowDetails
    )

    if (-not (Get-Command -Name Get-PSmmConfigMemberValue -ErrorAction SilentlyContinue)) {
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $helperPath = Join-Path -Path $moduleRoot -ChildPath 'Private\\Get-PSmmConfigMemberValue.ps1'
        if (Test-Path $helperPath) {
            . $helperPath
        }
    }

    try {
        Write-PSmmHost "`n==================== Storage Configuration ====================" -ForegroundColor Cyan

        # Get available drives if showing details
        $availableDrives = if ($ShowDetails) { Get-StorageDrive } else { $null }

        $storageRoot = Get-PSmmConfigMemberValue -Object $Config -Name 'Storage' -Default $null
        if ($null -eq $storageRoot -or -not ($storageRoot -is [System.Collections.IDictionary]) -or $storageRoot.Count -eq 0) {
            Write-PSmmHost "`n(No storage groups configured)" -ForegroundColor Yellow
            Write-PSmmHost "`n===============================================================`n" -ForegroundColor Cyan
            return
        }

        # Process each storage group
        foreach ($storageGroup in $storageRoot.Keys | Sort-Object) {
            Write-PSmmHost "`n--- Storage Group $storageGroup ---" -ForegroundColor Yellow

            $group = $storageRoot[$storageGroup]

            # Display Master storage
            $master = Get-PSmmConfigMemberValue -Object $group -Name 'Master' -Default $null
            if ($null -ne $master) {
                Write-PSmmHost '  Master:' -ForegroundColor Green
                Show-StorageDevice -Config $master `
                    -AvailableDrives $availableDrives `
                    -ShowDetails:$ShowDetails
            }

            # Display Backup storage(s)
            $backupStorage = Get-PSmmConfigMemberValue -Object $group -Name 'Backups' -Default $null
            if ($null -eq $backupStorage) {
                # Legacy compatibility (old schema used 'Backup')
                $backupStorage = Get-PSmmConfigMemberValue -Object $group -Name 'Backup' -Default $null
            }

            if ($null -ne $backupStorage) {

                if ($backupStorage.Count -eq 0) {
                    Write-PSmmHost '  Backup: (none configured)' -ForegroundColor DarkGray
                }
                else {
                    Write-PSmmHost '  Backup:' -ForegroundColor Green
                    foreach ($backupId in $backupStorage.Keys | Sort-Object) {
                        Write-PSmmHost "    Backup $backupId" -ForegroundColor Magenta
                        $backupCfg = Get-PSmmConfigMemberValue -Object $backupStorage -Name ([string]$backupId) -Default $null
                        if ($null -eq $backupCfg) {
                            continue
                        }
                        Show-StorageDevice -Config $backupCfg `
                            -AvailableDrives $availableDrives `
                            -ShowDetails:$ShowDetails `
                            -Indent 6
                    }
                }
            }
        }

        Write-PSmmHost "`n===============================================================`n" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to display storage information: $_"
        throw
    }
}

<#
.SYNOPSIS
    Displays a single storage device configuration.
#>
function Show-StorageDevice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [Parameter()]
        [array]$AvailableDrives,

        [Parameter()]
        [switch]$ShowDetails,

        [Parameter()]
        [int]$Indent = 4
    )

    $prefix = ' ' * $Indent

    $driveLetter = $null
    $serialNumber = $null
    $label = $null
    $availableFlag = $null

    $driveLetter = Get-PSmmConfigMemberValue -Object $Config -Name 'DriveLetter' -Default $null
    $serialNumber = Get-PSmmConfigMemberValue -Object $Config -Name 'SerialNumber' -Default $null
    $label = Get-PSmmConfigMemberValue -Object $Config -Name 'Label' -Default $null
    $availableFlag = Get-PSmmConfigMemberValue -Object $Config -Name 'IsAvailable' -Default $null

    $driveLetter = if ($null -eq $driveLetter) { '' } else { [string]$driveLetter }
    $serialNumber = if ($null -eq $serialNumber) { '' } else { [string]$serialNumber }
    $label = if ($null -eq $label) { '' } else { [string]$label }

    # Check if drive is available
    $isAvailable = if ($null -ne $availableFlag) { [bool]$availableFlag } else { -not [string]::IsNullOrEmpty($driveLetter) }
    $statusColor = if ($isAvailable) { 'Green' } else { 'Red' }

    # Get drive details if available
    $drive = $null
    if ($ShowDetails -and $AvailableDrives -and $isAvailable) {
        $drive = $AvailableDrives | Where-Object {
            $_.SerialNumber.Trim() -eq $serialNumber.Trim()
        } | Select-Object -First 1
    }

    # Define column widths for alignment
    $col1Width = 18
    $col2Width = 40

    # Helper function to format key-value pairs in two columns
    function Format-TwoColumn {
        param($Key1, $Value1, $Color1, $Key2, $Value2, $Color2)

        $part2 = if ($Key2 -and $null -ne $Value2) {
            "{0,-$col1Width}: {1}" -f $Key2, $Value2
        } else { '' }

        if ($part2) {
            Write-PSmmHost $prefix -NoNewline
            Write-PSmmHost "$Key1" -NoNewline -ForegroundColor Cyan
            Write-PSmmHost ": " -NoNewline
            Write-PSmmHost ("{0,-$($col2Width-2)}" -f $Value1) -NoNewline -ForegroundColor $Color1
            Write-PSmmHost "$Key2" -NoNewline -ForegroundColor Cyan
            Write-PSmmHost ": " -NoNewline
            Write-PSmmHost $Value2 -ForegroundColor $Color2
        } else {
            Write-PSmmHost $prefix -NoNewline
            Write-PSmmHost "$Key1" -NoNewline -ForegroundColor Cyan
            Write-PSmmHost ": " -NoNewline
            Write-PSmmHost $Value1 -ForegroundColor $Color1
        }
    }

    # Display basic information in sorted order with two-column layout
    Format-TwoColumn -Key1 'Drive Letter' -Value1 $driveLetter -Color1 $statusColor -Key2 'Serial Number' -Value2 $serialNumber -Color2 'White'
    Format-TwoColumn -Key1 'Label' -Value1 $label -Color1 'Yellow' -Key2 'Manufacturer' -Value2 $(if ($drive) { $drive.Manufacturer } else { 'N/A' }) -Color2 'White'
    Format-TwoColumn -Key1 'Model' -Value1 $(if ($drive) { $drive.Model } else { 'N/A' }) -Color1 'White' -Key2 'File System' -Value2 $(if ($drive) { $drive.FileSystem } else { 'N/A' }) -Color2 'White'
    Format-TwoColumn -Key1 'Partition Kind' -Value1 $(if ($drive) { $drive.PartitionKind } else { 'N/A' }) -Color1 'White' -Key2 'Total Space' -Value2 $(if ($drive) { "$($drive.TotalSpace) GB" } else { 'N/A' }) -Color2 'White'
    Format-TwoColumn -Key1 'Used Space' -Value1 $(if ($drive) { "$($drive.UsedSpace) GB ($('{0:P2}' -f ($drive.UsedSpace / $drive.TotalSpace)))" } else { 'N/A' }) -Color1 'Magenta' -Key2 'Free Space' -Value2 $(if ($drive) { "$($drive.FreeSpace) GB ($('{0:P2}' -f ($drive.FreeSpace / $drive.TotalSpace)))" } else { 'N/A' }) -Color2 'Green'
    Format-TwoColumn -Key1 'Health Status' -Value1 $(if ($drive) { $drive.HealthStatus } else { 'N/A' }) -Color1 'Green' -Key2 'Projects' -Value2 $(if ($drive) { $drive.Number } else { 'N/A' }) -Color2 'White'

    Write-PSmmHost ''
}

#endregion ########## PUBLIC ##########
