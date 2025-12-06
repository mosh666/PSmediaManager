<#
.SYNOPSIS
    MKVToolNix
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-MKVToolNix {
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
        $CurrentVersion = (& $bin --version)
        return $CurrentVersion.Split(' ')[1].Substring(1)
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-MKVToolNix {
    param(
        [hashtable]$Plugin
    )
    $Response = Invoke-WebRequest -Uri $Plugin.Config.VersionUrl
    # Get the latest version
    if ($Response.Links) {
        # Extract version numbers from the links
        $Versions = $Response.Links | Where-Object { $_.href -match '(\d+\.\d+)/$' } | ForEach-Object { $matches[1] } | Sort-Object { [version]$_ } -Descending
        # Ensure versions were found
        if ($Versions.Count -gt 0) {
            $LatestVersion = $Versions[0]
        }
        else {
            Write-Error 'No valid versions found.'
            exit
        }
    }
    # Ensure State exists
    if (-not $Plugin.Config.ContainsKey('State') -or $null -eq $Plugin.Config.State) { $Plugin.Config.State = @{} }
    # Use correctly-cased variable name
    $LatestInstaller = "$(($Plugin.Config.Name))-64-bit-$LatestVersion.7z"
    $Plugin.Config.State.LatestVersion = $LatestVersion
    $Plugin.Config.State.LatestInstaller = $LatestInstaller
    $Url = $Plugin.Config.VersionUrl + $LatestVersion + '/' + $LatestInstaller
    return $Url
}

function Invoke-Installer-MKVToolNix {
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
