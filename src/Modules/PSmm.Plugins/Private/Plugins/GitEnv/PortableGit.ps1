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
        $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$($Plugin.Config.Name)*", 'Directory')) | Select-Object -First 1
    }
    else {
        $InstallPath = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Plugin.Config.Name)*" }
    }

    if ($InstallPath) {
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
        $ServiceContainer
    )

    # Resolve Process and FileSystem from ServiceContainer if available
    $Process = $null
    $FileSystem = $null
    if ($null -ne $ServiceContainer -and ($ServiceContainer.PSObject.Methods.Name -contains 'Resolve')) {
        try {
            $Process = $ServiceContainer.Resolve('Process')
            $FileSystem = $ServiceContainer.Resolve('FileSystem')
        }
        catch {
            Write-Verbose "Failed to resolve services from ServiceContainer: $_"
        }
    }

    try {
        $ExtractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase).Substring(0, (Split-Path $InstallerPath -LeafBase).Length - 3)
        $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process
        Start-Process -FilePath $sevenZipCmd -ArgumentList "x `"$InstallerPath`" -o`"$ExtractPath`"" -Wait
        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
