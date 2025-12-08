<#
.SYNOPSIS
    ExifTool
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-ExifTool {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $FileSystem
    )
    if ($FileSystem) {
        $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$($Plugin.Config.Name)*", 'Directory')) | Select-Object -First 1
    }
    else {
        $InstallPath = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }
    }

    if ($InstallPath) {
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

        # Find the extracted exiftool directory
        $ExiftoolDir = Get-ChildItem -Path $ExtractPath -Directory -Filter "exiftool-*_64" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($ExiftoolDir) {
            # Find and rename the executable file (handles both formats: exiftool(-k).exe and exiftool.exe)
            $ExeFile = Get-ChildItem -Path $ExiftoolDir.FullName -Filter "exiftool*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($ExeFile -and $ExeFile.Name -ne 'exiftool.exe') {
                Rename-Item -Path $ExeFile.FullName -NewName 'exiftool.exe' -Force -ErrorAction Stop
            }

            Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
        }
        else {
            throw "ExifTool directory not found after extraction"
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
