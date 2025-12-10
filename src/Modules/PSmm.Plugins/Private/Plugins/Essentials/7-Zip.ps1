<#
.SYNOPSIS
    7-Zip
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########
function Get-CurrentVersion-7z {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths
    )

    # Resolve FileSystem from ServiceContainer if available
    $FileSystem = $null
    if ($null -ne $ServiceContainer -and ($ServiceContainer.PSObject.Methods.Name -contains 'Resolve')) {
        try {
            $FileSystem = $ServiceContainer.Resolve('FileSystem')
        }
        catch {
            Write-Verbose "Failed to resolve FileSystem from ServiceContainer: $_"
        }
    }

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
        $process = Start-Process -FilePath $InstallerPath -ArgumentList "/S /D=$($ExtractPath)\" -Wait -PassThru
        $process | Out-Null
        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
