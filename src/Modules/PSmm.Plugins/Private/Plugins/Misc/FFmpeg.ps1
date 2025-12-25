<#
.SYNOPSIS
    FFmpeg
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-ffmpeg {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem
    )

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'FFmpeg' }

    $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1

    if ($CurrentVersion) {
        return $CurrentVersion.BaseName.Split('-')[1]
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-ffmpeg {
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
    $null = $Http, $Crypto, $Environment, $PathProvider, $Process

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'FFmpeg' }
    $versionUrl = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'VersionUrl')

    if ($null -eq $Http) {
        throw [System.InvalidOperationException]::new('Http service is required to download FFmpeg artifacts')
    }

    # Ensure a clean temp directory state for this plugin
    $existing = @($FileSystem.GetChildItem($Paths._Temp, "$pluginName*.7z", 'File'))
    foreach ($f in $existing) {
        $FileSystem.RemoveItem($f.FullName, $false)
    }

    $fileName = $null
    try { $fileName = [System.IO.Path]::GetFileName(([uri]$versionUrl).LocalPath) } catch { $fileName = $null }
    if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = "$pluginName.7z" }
    $outFile = Join-Path -Path $Paths._Temp -ChildPath $fileName

    $Http.DownloadFile($versionUrl, $outFile)

    $tempFiles = @($FileSystem.GetChildItem($Paths._Temp, "$pluginName*.7z", 'File'))
    $latestFile = $tempFiles | Select-Object -First 1
    $LatestInstaller = $latestFile.Name

    $LatestVersion = $LatestInstaller.Split('-')[1]
    $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestVersion
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $LatestInstaller

    $Url = $versionUrl
    return $Url
}

function Get-Installer-ffmpeg {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Http', Justification = 'Parameter reserved for future HTTP-based downloads')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [hashtable]$Plugin,
        [hashtable]$Paths,
        $Http,
        $Crypto,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem,
        $Environment,
        $PathProvider,
        $Process
    )
    $null = $Url, $Http, $Crypto, $Environment, $PathProvider, $Process

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'FFmpeg' }
    $pattern = "$pluginName*.7z"
    $filesToRemove = @($FileSystem.GetChildItem($Paths._Downloads, $pattern, 'File'))
    foreach ($file in $filesToRemove) {
        $FileSystem.RemoveItem($file.FullName, $false)
    }
    Move-Item -Path "$($Paths._Temp)\$pattern" -Destination $Paths._Downloads -Force

    $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'
    $latestInstaller = [string](Get-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestInstaller')
    $InstallerPath = Join-Path -Path $Paths._Downloads -ChildPath $latestInstaller
    return $InstallerPath
}

function Invoke-Installer-ffmpeg {
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
        $ExtractPath = $Paths.Root

        # Ensure extraction directory exists
        if ($FileSystem -and -not $FileSystem.TestPath($ExtractPath)) {
            $FileSystem.NewItem($ExtractPath, 'Directory')
        }
        elseif (-not $FileSystem -and -not (Test-Path $ExtractPath)) {
            New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null
        }

        if ($null -eq $Process) {
            throw [System.InvalidOperationException]::new('Process service is required to extract FFmpeg archive')
        }

        # Use 7z.exe to extract the archive
        $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process

        # Extract archive
        $result = $Process.InvokeCommand($sevenZipCmd, @('x', $InstallerPath, "-o$ExtractPath", '-y'))

        if ($result -and -not $result.Success) {
            $ex = [System.Exception]::new("7z extraction failed with exit code: $($result.ExitCode)")
            throw $ex
        }

        $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
        $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
        if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'FFmpeg' }
        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        $pn = 'FFmpeg'
        try {
            $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
            $pnCandidate = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
            if (-not [string]::IsNullOrWhiteSpace($pnCandidate)) { $pn = $pnCandidate }
        }
        catch {
            Write-Verbose "Install FFmpeg: failed to get plugin name from config: $($_.Exception.Message)"
        }
        Write-PSmmLog -Level ERROR -Context "Install $pn" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
