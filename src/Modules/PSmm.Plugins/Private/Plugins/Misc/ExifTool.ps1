<#
.SYNOPSIS
    ExifTool
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-ExifTool {
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
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'ExifTool' }

    $InstallPath = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1

    if ($InstallPath) {
        $commandPath = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'CommandPath')
        $command = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Command')
        $bin = Join-Path -Path $InstallPath -ChildPath $commandPath -AdditionalChildPath $command
        $result = $Process.StartProcess($bin, @('-ver'))
        if ($result -and -not $result.Success) {
            throw [System.Exception]::new("Failed to execute $bin (-ver). ExitCode=$($result.ExitCode)")
        }

        return ([string]$result.StdOut).Trim()
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-ExifTool {
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
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'ExifTool' }
    $versionUrl = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'VersionUrl')
    $baseUri = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'BaseUri')

    $LatestVersion = $Http.InvokeRestMethod($versionUrl, 'GET', $null, $null)
    $LatestVersion = '{0:N2}' -f $LatestVersion
    $LatestVersion = $LatestVersion -replace ',', '.'
    $LatestInstaller = "exiftool-$($LatestVersion)_64.zip"

    $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestVersion
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $LatestInstaller

    $Url = $baseUri + '/' + $LatestInstaller

    return $Url
}

function Invoke-Installer-ExifTool {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath,
        $Process,
        $FileSystem,
        $Environment,
        $PathProvider
    )
    $null = $Process, $Environment, $PathProvider

    try {
        $ExtractPath = $Paths.Root
        if ($null -eq $FileSystem) {
            throw [System.InvalidOperationException]::new('FileSystem service is required to extract ExifTool zip')
        }

        $FileSystem.ExtractZip($InstallerPath, $ExtractPath, $true)

        # Find the extracted exiftool directory
        $ExiftoolDir = Get-ChildItem -Path $ExtractPath -Directory -Filter "exiftool-*_64" -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($ExiftoolDir) {
            # Find and rename the executable file (handles both formats: exiftool(-k).exe and exiftool.exe)
            $ExeFile = Get-ChildItem -Path $ExiftoolDir.FullName -Filter "exiftool*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($ExeFile -and $ExeFile.Name -ne 'exiftool.exe') {
                Rename-Item -Path $ExeFile.FullName -NewName 'exiftool.exe' -Force -ErrorAction Stop
            }

            $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
            $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
            if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'ExifTool' }
            Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $($InstallerPath)" -Console -File
        }
        else {
            throw "ExifTool directory not found after extraction"
        }
    }
    catch {
        $pn = 'ExifTool'
        try {
            $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
            $pnCandidate = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
            if (-not [string]::IsNullOrWhiteSpace($pnCandidate)) { $pn = $pnCandidate }
        }
        catch {
            Write-Verbose "Install ExifTool: failed to get plugin name from config: $($_.Exception.Message)"
        }
        Write-PSmmLog -Level ERROR -Context "Install $pn" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
