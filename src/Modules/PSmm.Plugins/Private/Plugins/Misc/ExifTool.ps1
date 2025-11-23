<#
.SYNOPSIS
    ExifTool
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-ExifTool {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths
    )
    if ($InstallPath = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }) {
        $bin = Join-Path -Path $InstallPath -ChildPath $Plugin.Config.CommandPath -AdditionalChildPath $Plugin.Config.Command
        $CurrentVersion = (& $bin -ver)
        return $CurrentVersion
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-ExifTool {
    param(
        [hashtable]$Plugin
    )
    $LatestVersion = Invoke-RestMethod -Uri $Plugin.Config.VersionUrl
    $LatestVersion = '{0:N2}' -f $latestVersion
    $LatestVersion = $LatestVersion -replace ',', '.'
    $LatestInstaller = "exiftool-$($LatestVersion)_64.zip"
    $Plugin.Config.State.LatestVersion = $LatestVersion
    $Plugin.Config.State.LatestInstaller = $LatestInstaller
    $Url = $Plugin.Config.BaseUri + '/' + $LatestInstaller

    return $Url
}

function Invoke-Installer-ExifTool {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath
    )
    try {
        $ExtractPath = $Paths.Root
        Expand-Archive -Path $InstallerPath -DestinationPath $ExtractPath -Force
        Rename-Item -Path "$("$ExtractPath")\exiftool-$($Plugin.Config.State.LatestVersion)_64\exiftool(-k).exe" -NewName 'exiftool.exe'
        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}   

#endregion ########## PRIVATE ##########
