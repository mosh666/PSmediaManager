<#
.SYNOPSIS
    digiKam
#>

Set-StrictMode -Version Latest

if (-not (Get-Command -Name Get-PSmmPluginsConfigMemberValue -ErrorAction SilentlyContinue)) {
    throw "Get-PSmmPluginsConfigMemberValue is not available. Ensure PSmm.Plugins is imported before loading plugin definitions."
}

#region ########## PRIVATE ##########

function Get-CurrentVersion-digiKam {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem
    )

    $pluginConfig = Get-PSmmPluginsConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'digiKam' }

    $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1

    if ($CurrentVersion) {
        return $CurrentVersion.BaseName.Split('-')[1]
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-digiKam {
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
    if ([string]::IsNullOrWhiteSpace($versionUrl)) {
        throw [System.InvalidOperationException]::new('Plugin config is missing VersionUrl')
    }

    $Response = $Http.InvokeWebRequest($versionUrl, 'GET', $null, 0)
    $VersionPattern = '(\d+\.\d+\.\d+)/'
    $Match = [regex]::Matches($Response.Content, $VersionPattern)
    $LatestVersion = ($Match | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Descending | Select-Object -First 1

    $DownloadPageUrl = "$versionUrl$LatestVersion/"
    $Response = $Http.InvokeWebRequest($DownloadPageUrl, 'GET', $null, 0)
    $LatestInstaller = [regex]::Match($Response.Content, '(digiKam-\d+\.\d+\.\d+-Qt6-Win64.exe)').Groups[1].Value

    $state = Get-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-PSmmPluginsConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }

    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestVersion
    Set-PSmmPluginsConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $LatestInstaller
    $Url = $DownloadPageUrl + $LatestInstaller
    return $Url
}

function Invoke-Installer-digiKam {
    [CmdletBinding()]
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
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'digiKam' }

    try {
        $extractPath = Join-Path -Path $Paths.Root -ChildPath (Split-Path $InstallerPath -LeafBase)

        if ($FileSystem) {
            if (-not $FileSystem.TestPath($extractPath)) {
                $FileSystem.NewItem($extractPath, 'Directory') | Out-Null
            }
        }
        elseif (-not (Test-Path -LiteralPath $extractPath)) {
            New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
        }

        $sevenZipCmd = $null
        if ($Process) {
            try {
                $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process
            }
            catch {
                Write-Verbose "Unable to resolve 7z via Process service: $_"
            }
        }

        if (-not $sevenZipCmd) {
            $sevenZipCmd = (Get-Command -Name '7z' -ErrorAction SilentlyContinue)?.Source
        }

        if (-not $sevenZipCmd) {
            throw [System.InvalidOperationException]::new('7z command is required to extract digiKam installer but was not found')
        }

        $arguments = @('x', $InstallerPath, "-o$extractPath", '-y')

        if ($null -eq $Process) {
            throw [System.InvalidOperationException]::new('Process service is required to extract digiKam installer')
        }

        $result = $Process.InvokeCommand($sevenZipCmd, $arguments)
        if ($result -and -not $result.Success) {
            throw [System.Exception]::new("7z extraction failed with exit code $($result.ExitCode)")
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $pluginName" -Message "Installation completed for $InstallerPath" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $pluginName" -Message "Installation failed for $InstallerPath" -ErrorRecord $_ -Console -File
        throw
    }
}

#endregion ########## PRIVATE ##########
