<#
.SYNOPSIS
    FFmpeg
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-ffmpeg {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $FileSystem
    )
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

function Get-LatestUrlFromUrl-ffmpeg {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $FileSystem
    )
    Invoke-RestMethod -Uri $Plugin.Config.VersionUrl -OutFile $Paths._Temp

    if ($FileSystem) {
        $tempFiles = @($FileSystem.GetChildItem($Paths._Temp, "$($Plugin.Config.Name)*.7z", 'File'))
        $latestFile = $tempFiles | Select-Object -First 1
        $LatestInstaller = $latestFile.Name
    }
    else {
        $LatestInstaller = Split-Path -Path (Get-ChildItem -Path $Paths._Temp -Name "$($Plugin.Config.Name)*.7z") -Leaf
    }

    $LatestVersion = $LatestInstaller.Split('-')[1]
    $Plugin.Config.State.LatestVersion = $LatestVersion
    $Plugin.Config.State.LatestInstaller = $LatestInstaller
    $Url = $Plugin.Config.VersionUrl
    return $Url
}

function Get-Installer-ffmpeg {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Http', Justification = 'Parameter reserved for future HTTP-based downloads')]
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $Http,
        $FileSystem
    )
    $pattern = "$($Plugin.Config.Name)*.7z"
    if ($FileSystem) {
        $filesToRemove = @($FileSystem.GetChildItem($Paths._Downloads, $pattern, 'File'))
        foreach ($file in $filesToRemove) {
            $FileSystem.RemoveItem($file.FullName, $false)
        }
    }
    else {
        Get-ChildItem -Path "$($Paths._Downloads)\$pattern" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Move-Item -Path "$($Paths._Temp)\$pattern" -Destination $Paths._Downloads -Force
    $InstallerPath = Join-Path -Path $Paths._Downloads -ChildPath $Plugin.Config.State.LatestInstaller
    return $InstallerPath
}

function Invoke-Installer-ffmpeg {
    param (
        [hashtable]$Plugin,
        [hashtable]$Paths,
        [string]$InstallerPath,
        $Process,
        $FileSystem
    )
    try {
        $ExtractPath = $Paths.Root

        # Ensure extraction directory exists
        if ($FileSystem -and -not $FileSystem.TestPath($ExtractPath)) {
            $FileSystem.NewItem($ExtractPath, 'Directory')
        }
        elseif (-not $FileSystem -and -not (Test-Path $ExtractPath)) {
            New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null
        }

        # Use 7z.exe to extract the archive
        if ($Process) {
            $sevenZipCmd = Resolve-PluginCommandPath -Paths $Paths -CommandName '7z' -DefaultCommand '7z' -FileSystem $FileSystem -Process $Process
        }
        else {
            $sevenZipCmd = '7z'
        }

        # Extract archive
        $result = if ($Process) {
            $Process.InvokeCommand($sevenZipCmd, @('x', $InstallerPath, "-o$ExtractPath", '-y'))
        }
        else {
            & $sevenZipCmd x $InstallerPath "-o$ExtractPath" -y
        }

        if ($Process -and -not $result.Success) {
            $ex = [System.Exception]::new("7z extraction failed with exit code: $($result.ExitCode)")
            throw $ex
        }

        Write-PSmmLog -Level SUCCESS -Context "Install $($Plugin.Config.Name)" -Message "Installation completed for $($InstallerPath)" -Console -File
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Install $($Plugin.Config.Name)" -Message "Installation failed for $($InstallerPath)" -ErrorRecord $_ -Console -File
    }
}

#endregion ########## PRIVATE ##########
