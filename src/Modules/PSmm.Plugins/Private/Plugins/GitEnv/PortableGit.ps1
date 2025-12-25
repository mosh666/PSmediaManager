<#
.SYNOPSIS
    PortableGit
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-PortableGit {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Process
    )

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'PortableGit' }

    $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1

    if ($InstallPath) {
        $commandPath = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'CommandPath')
        $command = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Command')
        if ([string]::IsNullOrWhiteSpace($commandPath) -or [string]::IsNullOrWhiteSpace($command)) {
            return ''
        }

        $bin = Join-Path -Path $InstallPath -ChildPath $commandPath -AdditionalChildPath $command
        $result = $Process.StartProcess($bin, @('--version'))
        if ($result -and -not $result.Success) {
            throw [System.Exception]::new("Failed to execute $bin (--version). ExitCode=$($result.ExitCode)")
        }

        $text = [string]$result.StdOut
        $firstLine = ($text -split "`r?`n" | Select-Object -First 1)
        return 'v' + $firstLine.Split(' ')[2]
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

        $Process,
        $FileSystem,
        $Environment,
        $PathProvider
    )
    $null = $Environment, $PathProvider

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'PortableGit' }

    try {
        $ExtractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase).Substring(0, (Split-Path $InstallerPath -LeafBase).Length - 3)
        $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process
        if ($null -eq $Process) {
            throw [System.InvalidOperationException]::new('Process service is required to extract PortableGit')
        }

        $result = $Process.InvokeCommand($sevenZipCmd, @('x', $InstallerPath, "-o$ExtractPath", '-y'))
        if ($result -and -not $result.Success) {
            throw [System.Exception]::new("7z extraction failed with exit code $($result.ExitCode)")
        }
        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $pluginName" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
