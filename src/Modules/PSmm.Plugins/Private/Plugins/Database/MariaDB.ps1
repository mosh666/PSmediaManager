<#
.SYNOPSIS
    MariaDB
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-MariaDB {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $FileSystem
    )
    if ($FileSystem) {
        $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, "$($Plugin.Config.Name)*", 'Directory')) | Select-Object -First 1
    }
    else {
        $CurrentVersion = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }
    }
    
    if ($CurrentVersion) {
        return $CurrentVersion.BaseName.Split('-')[1]
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-MariaDB {
    param(
        [hashtable]$Plugin
    )
    $MajorReleases = Invoke-RestMethod -Uri $Plugin.Config.VersionUrl
    $LatestMajorReleaseId = $MajorReleases.major_releases | Where-Object release_status -EQ 'Stable' | Where-Object release_support_type -EQ 'Long Term Support' | Sort-Object -Property release_id -Descending | Select-Object -First 1 -ExpandProperty release_id
    $PointReleases = Invoke-RestMethod -Uri ("$($Plugin.Config.VersionUrl)$LatestMajorReleaseId/")
    $LatestPointReleaseId = ($PointReleases.releases | Get-Member -MemberType NoteProperty | Sort-Object -Descending | Select-Object -First 1).Name
    $Plugin.Config.State.LatestVersion = $LatestPointReleaseId
    $Files = Invoke-RestMethod -Uri "$($Plugin.Config.VersionUrl)$latestPointReleaseId/"
    $File = $Files.release_data.$LatestPointReleaseId.files | Where-Object { $_.file_name -like '*winx64.zip' } | Select-Object -First 1
    $Plugin.Config.State.LatestInstaller = $File.file_name
    $Url = $File.file_download_url
    return $Url
}

function Invoke-Installer-MariaDB {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath
    )
    try {
        $ExtractPath = $Paths.Root
        Expand-Archive -Path $InstallerPath -DestinationPath $ExtractPath -Force
        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
