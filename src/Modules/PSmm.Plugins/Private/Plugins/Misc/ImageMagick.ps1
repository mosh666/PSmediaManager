<#
.SYNOPSIS
    ImageMagick
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-CurrentVersion-ImageMagick {
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
        #$LatestVersion = [System.IO.Path]::GetFileNameWithoutExtension($Latest.FileName).Split("-")[1,2] -join "-"
        return $CurrentVersion.BaseName.Split('-')[1, 2] -join '-'
    }
    else {
        return ''
    }
}

function Get-LatestUrlFromUrl-ImageMagick {
    param(
        [hashtable]$Plugin
    )

    try {
        $Response = Invoke-WebRequest -Uri $Plugin.Config.VersionUrl -TimeoutSec 10
    }
    catch {
        throw [PluginRequirementException]::new("Failed to retrieve version information from $($Plugin.Config.VersionUrl)", "ImageMagick", $_.Exception)
    }
    # Do not format output; we need raw string parsing
    $ZipMatches = [System.Text.RegularExpressions.Regex]::Matches($Response.Content, $Plugin.Config.AssetPattern, 'IgnoreCase')

    if ($ZipMatches.Count -eq 0) {
        throw [PluginRequirementException]::new("No matching 'portable-Q16-HDRI-x64.zip' downloads found on $($Plugin.Config.VersionUrl)", "ImageMagick")
    }

    $Candidates = foreach ($m in $ZipMatches) {
        $FileName = $m.Value
        $VerTag = $m.Groups['ver'].Value

        # Split version into semantic (x.y.z) and build (-n)
        $Parts = $VerTag.Split('-')
        $SemVer = [Version]$Parts[0]
        [int]$Build = [int]$Parts[1]

        [pscustomobject]@{
            FileName = $FileName
            Version = $VerTag
            SemVer = $SemVer
            Build = $Build
        }
    }

    # Deduplicate by filename
    $Candidates = $Candidates | Group-Object FileName | ForEach-Object { $_.Group | Select-Object -First 1 }

    # Pick the highest version (SemVer then Build)
    $Latest = $Candidates |
        Sort-Object -Property @{Expression = 'SemVer'; Descending = $true }, @{Expression = 'Build'; Descending = $true } |
        Select-Object -First 1

    if (-not $Latest) {
        throw [PluginRequirementException]::new('Could not determine latest version', 'ImageMagick')
    }


    $LatestVersion = $Latest.Version
    $LatestInstaller = $Latest.FileName
    $Plugin.Config.State.LatestVersion = $LatestVersion
    $Plugin.Config.State.LatestInstaller = $LatestInstaller
    # Compose direct download URL as plain string
    $Url = "$($Plugin.Config.BaseUri)/$($LatestInstaller)"
    return [string]$Url
}

function Get-Installer-ImageMagick {
    param(
        [string]$Url,
        [hashtable]$Plugin,
        [hashtable]$Paths
    )
    $Url = $Plugin.Config.BaseUri + '/' + $Plugin.Config.State.LatestInstaller
    Write-PSmmLog -Level INFO -Context "Download $($Plugin.Config.Name)" -Message "Downloading $($Plugin.Config.Name) from $Url ..." -Console -File
    try {
        Invoke-WebRequest -Uri "$Url" -OutFile "$($Paths._Downloads)\$($Plugin.Config.State.LatestInstaller)"
        $InstallerPath = Join-Path -Path $Paths._Downloads -ChildPath $Plugin.Config.State.LatestInstaller
        Write-PSmmLog -Level SUCCESS -Context "Download $($Plugin.Config.Name)" -Message "$($Plugin.Config.Name) downloaded successfully to $InstallerPath" -Console -File
        return $InstallerPath
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Download $($Plugin.Config.Name)" -Message "Failed to download $($Plugin.Config.Name) from $Url" -ErrorRecord $_ -Console -File
        return $null
    }
}

#endregion ########## PRIVATE ##########
