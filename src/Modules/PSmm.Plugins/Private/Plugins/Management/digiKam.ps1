<#
.SYNOPSIS
    digiKam
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-digiKam {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $ServiceContainer
    )

    # Resolve FileSystem from ServiceContainer if available, otherwise create fallback
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
        $ServiceContainer
    )
    $null = $Paths, $ServiceContainer
    $Response = Invoke-WebRequest -Uri $Plugin.Config.VersionUrl
    $VersionPattern = '(\d+\.\d+\.\d+)/'
    $Match = [regex]::Matches($Response.Content, $VersionPattern)
    $LatestVersion = ($Match | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Descending | Select-Object -First 1

    $DownloadPageUrl = "$($Plugin.Config.VersionUrl)$($LatestVersion)/"
    $Response = Invoke-WebRequest -Uri "$($DownloadPageUrl)"
    $LatestInstaller = [regex]::Match($Response.Content, '(digiKam-\d+\.\d+\.\d+-Qt6-Win64.exe)').Groups[1].Value


    $Plugin.Config.State.LatestVersion = $LatestVersion
    $Plugin.Config.State.LatestInstaller = $LatestInstaller
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

        $ServiceContainer
    )

    # Resolve optional services
    $FileSystem = $null
    $Process = $null
    if ($null -ne $ServiceContainer -and ($ServiceContainer.PSObject.Methods.Name -contains 'Resolve')) {
        try {
            $FileSystem = $ServiceContainer.Resolve('FileSystem')
        }
        catch {
            Write-Verbose "Failed to resolve FileSystem from ServiceContainer: $_"
        }

        try {
            $Process = $ServiceContainer.Resolve('Process')
        }
        catch {
            Write-Verbose "Failed to resolve Process from ServiceContainer: $_"
        }
    }

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

        if ($Process) {
            $result = $Process.InvokeCommand($sevenZipCmd, $arguments)
            if ($result -and -not $result.Success) {
                throw [System.Exception]::new("7z extraction failed with exit code $($result.ExitCode)")
            }
        }
        else {
            $nativeResult = & $sevenZipCmd @('x', $InstallerPath, "-o$extractPath", '-y')
            if ($LASTEXITCODE -ne 0) {
                throw [System.Exception]::new("7z extraction failed with exit code $LASTEXITCODE. Output: $nativeResult")
            }
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $InstallerPath" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $InstallerPath" -ErrorRecord $_ -Console -File
        throw
    }
}

#endregion ########## PRIVATE ##########
