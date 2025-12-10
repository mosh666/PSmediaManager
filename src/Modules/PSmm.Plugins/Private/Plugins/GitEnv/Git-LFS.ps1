<#
.SYNOPSIS
    Git-LFS
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-Git-LFS {
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
        $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, "$($Plugin.Config.Name)*", 'Directory')) | Select-Object -First 1
    }
    else {
        $CurrentVersion = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }
    }

    if ($CurrentVersion) {
        return 'v' + $CurrentVersion.BaseName.Split('-')[2]
    }
    else {
        return ''
    }
}

function Invoke-Installer-Git-LFS {
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
