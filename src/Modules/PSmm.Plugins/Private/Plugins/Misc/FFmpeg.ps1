<#
.SYNOPSIS
    FFmpeg
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-ffmpeg {
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

function Get-LatestUrlFromUrl-ffmpeg {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths
    )
    Invoke-RestMethod -Uri $Plugin.Config.VersionUrl -OutFile $Paths._Temp
    $LatestInstaller = Split-Path -Path (Get-ChildItem -Path $Paths._Temp -Name "$($Plugin.Config.Name)*.7z") -Leaf
    $LatestVersion = $LatestInstaller.Split('-')[1]
    $Plugin.Config.State.LatestVersion = $LatestVersion
    $Plugin.Config.State.LatestInstaller = $LatestInstaller
    $Url = $Plugin.Config.VersionUrl
    return $Url
}

function Get-Installer-ffmpeg {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths
    )
    Remove-Item -Path "$($Paths._Downloads)\$($Plugin.Config.Name)*.7z" -ErrorAction SilentlyContinue -Force
    Move-Item -Path "$($Paths._Temp)\$($Plugin.Config.Name)*.7z" -Destination $Paths._Downloads -Force
    $InstallerPath = Join-Path -Path $Paths._Downloads -ChildPath $Plugin.Config.State.LatestInstaller
    return $InstallerPath
}

function Invoke-Installer-ffmpeg {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath
    )
    try {
        $ExtractPath = $Paths.Root
        Expand-7Zip -ArchiveFileName $InstallerPath -TargetPath $ExtractPath
        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
