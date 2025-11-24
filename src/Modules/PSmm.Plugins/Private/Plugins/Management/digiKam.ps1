<#
.SYNOPSIS
    digiKam
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-digiKam {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths
    )
    if ($CurrentVersion = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }) {
        return $CurrentVersion.BaseName.Split('-')[1]
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-digiKam {
    param(
        [hashtable]$Plugin
    )
    $Response = Invoke-WebRequest -Uri $Plugin.Config.VersionUrl
    $VersionPattern = '(\d+\.\d+\.\d+)/'
    $Match = [regex]::Matches($Response.Content, $VersionPattern)
    $LatestVersion = ($Match | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Descending | Select-Object -First 1

    $DownloadPageUrl = "$($Plugin.Config.VersionUrl)$($LatestVersion)/"
    $Response = Invoke-WebRequest -Uri "$($DownloadPageUrl)"
    $LatestInstaller = [regex]::Match($Response.Content, '(digiKam-\d+\.\d+\.\d+-Qt6-Win64.exe)').Groups[1].Value


    $Plugin.Config.State.LatestVersion = $LatestVersion
    $Plugin.Config.State.LatestInstaller = $LatestInstaller
    $Url = $DownloadPageUrl + $LatestInstaller
    return $Url
}

function Invoke-Installer-digiKam {
    param (
        [Parameter(Mandatory)]
        [hashtable]$Plugin,

        [Parameter(Mandatory)]
        [hashtable]$Paths,

        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        $Process,

        [Parameter()]
        $FileSystem
    )
    try {
        $ExtractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase)
        $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -Process $Process
        Start-Process -FilePath $sevenZipCmd -ArgumentList "x `"$InstallerPath`" -o`"$ExtractPath`"" -Wait
        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
