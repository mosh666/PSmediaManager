<#
.SYNOPSIS
    7-Zip
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########
function Get-CurrentVersion-7z {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $FileSystem
    )
    if ($FileSystem) {
        $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, $Plugin.Config.Command, 'File', $true)) | Select-Object -First 1
    }
    else {
        $CurrentVersion = Get-ChildItem -Path $Paths.Root -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $Plugin.Config.Command }
    }
    
    if ($CurrentVersion) {
        return $CurrentVersion.VersionInfo.FileVersion
    }
    else {
        return ''
    }
}

function Invoke-Installer-7z {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath
    )
    try {
        $ExtractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase)
        Expand-7Zip -ArchiveFileName $InstallerPath -TargetPath $ExtractPath
        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
