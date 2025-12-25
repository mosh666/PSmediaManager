<#
.SYNOPSIS
    MKVToolNix
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-MKVToolNix {
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
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'MKVToolNix' }

    $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1

    if ($InstallPath) {
        $commandPath = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'CommandPath')
        $command = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Command')
        $bin = Join-Path -Path $InstallPath -ChildPath $commandPath -AdditionalChildPath $command
        $result = $Process.StartProcess($bin, @('--version'))
        if ($result -and -not $result.Success) {
            throw [System.Exception]::new("Failed to execute $bin (--version). ExitCode=$($result.ExitCode)")
        }

        $currentVersionText = [string]$result.StdOut
        if ([string]::IsNullOrWhiteSpace($currentVersionText)) { $currentVersionText = [string]$result.StdErr }
        $firstLine = ($currentVersionText -split "`r?`n" | Select-Object -First 1)
        return $firstLine.Split(' ')[1].Substring(1)
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-MKVToolNix {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Http,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Crypto,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Environment,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $PathProvider,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Process
    )
    $null = $Paths, $Http, $Crypto, $FileSystem, $Environment, $PathProvider, $Process
    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $versionUrl = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'VersionUrl')
    $Response = $Http.InvokeWebRequest($versionUrl, 'GET', $null, 0)
    # Get the latest version
    if ($Response.Links) {
        # Extract version numbers from the links
        $Versions = $Response.Links | Where-Object { $_.href -match '(\d+\.\d+)/$' } | ForEach-Object { $matches[1] } | Sort-Object { [version]$_ } -Descending
        # Ensure versions were found
        if ($Versions.Count -gt 0) {
            $LatestVersion = $Versions[0]
        }
        else {
            throw 'No valid versions found.'
        }
    }
    # Ensure State exists
    $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }

    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'MKVToolNix' }
    # Use correctly-cased variable name
    $LatestInstaller = "$pluginName-64-bit-$LatestVersion.7z"
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestVersion
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $LatestInstaller
    $Url = $versionUrl + $LatestVersion + '/' + $LatestInstaller
    return $Url
}

function Invoke-Installer-MKVToolNix {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath,
        $Process,
        $FileSystem,
        $Environment,
        $PathProvider
    )
    $null = $Environment, $PathProvider

    try {
        $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
        $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
        if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'MKVToolNix' }
        $ExtractPath = $Paths.Root

        # Ensure extraction directory exists
        if ($FileSystem -and -not $FileSystem.TestPath($ExtractPath)) {
            $FileSystem.NewItem($ExtractPath, 'Directory')
        }
        elseif (-not $FileSystem -and -not (Test-Path $ExtractPath)) {
            New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null
        }

        if ($null -eq $Process) {
            throw [System.InvalidOperationException]::new('Process service is required to extract MKVToolNix archive')
        }

        # Use 7z.exe to extract the archive
        $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process

        # Extract archive
        $result = $Process.InvokeCommand($sevenZipCmd, @('x', $InstallerPath, "-o$ExtractPath", '-y'))
        if ($result -and -not $result.Success) {
            $ex = [System.Exception]::new("7z extraction failed with exit code: $($result.ExitCode)")
            throw $ex
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        $pn = 'MKVToolNix'
        try {
            $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
            $pnCandidate = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
            if (-not [string]::IsNullOrWhiteSpace($pnCandidate)) { $pn = $pnCandidate }
        }
        catch {
            Write-Verbose "Invoke-Installer-MKVToolNix: failed to resolve plugin name: $($_.Exception.Message)"
        }
        Write-PSmmLog -Level ERROR -Context "Install $pn" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
