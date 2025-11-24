<#
.SYNOPSIS
    PortableGit
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-PortableGit {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths
    )
    if ($InstallPath = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }) {
        $bin = Join-Path -Path $InstallPath -ChildPath $Plugin.Config.CommandPath -AdditionalChildPath $Plugin.Config.Command
        $CurrentVersion = (& $bin --version)
        return 'v' + $CurrentVersion.Split(' ')[2]
    }
    else {
        return ''
    }
}

function Invoke-Installer-PortableGit {
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
        # Mark injected but unused parameter as intentionally unused for static analysis
        $null = $FileSystem
        $ExtractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase).Substring(0, (Split-Path $InstallerPath -LeafBase).Length - 3)
        $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -Process $Process
        Start-Process -FilePath $sevenZipCmd -ArgumentList "x `"$InstallerPath`" -o`"$ExtractPath`"" -Wait
        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
