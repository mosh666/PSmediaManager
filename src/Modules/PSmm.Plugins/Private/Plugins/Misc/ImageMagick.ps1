<#
.SYNOPSIS
    ImageMagick
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function Get-ConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        try {
            if ($Object.ContainsKey($Name)) { return $Object[$Name] }
        }
        catch {
            Write-Verbose "Get-ConfigMemberValue: IDictionary.ContainsKey failed: $($_.Exception.Message)"
        }

        try {
            if ($Object.Contains($Name)) { return $Object[$Name] }
        }
        catch {
            Write-Verbose "Get-ConfigMemberValue: IDictionary.Contains failed: $($_.Exception.Message)"
        }

        try {
            foreach ($k in $Object.Keys) {
                if ($k -eq $Name) { return $Object[$k] }
            }
        }
        catch {
            Write-Verbose "Get-ConfigMemberValue: IDictionary.Keys iteration failed: $($_.Exception.Message)"
        }

        return $null
    }

    try {
        $p = $Object.PSObject.Properties[$Name]
        if ($null -ne $p) { return $p.Value }
    }
    catch {
        Write-Verbose "Get-ConfigMemberValue: PSObject property lookup failed: $($_.Exception.Message)"
    }

    return $null
}

function Set-ConfigMemberValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Object) {
        return
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if (-not $PSCmdlet.ShouldProcess("$Name", 'Set config value')) {
            return
        }
        $Object[$Name] = $Value
        return
    }

    try {
        if (-not $PSCmdlet.ShouldProcess("$Name", 'Set config value')) {
            return
        }
        $Object.$Name = $Value
        return
    }
    catch {
        Write-Verbose "Set-ConfigMemberValue: direct assignment failed: $($_.Exception.Message)"
    }

    try {
        if (-not $PSCmdlet.ShouldProcess("$Name", 'Set config value')) {
            return
        }
        if ($null -eq $Object.PSObject.Properties[$Name]) {
            $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
        }
        else {
            $Object.PSObject.Properties[$Name].Value = $Value
        }
    }
    catch {
        Write-Verbose "Set-ConfigMemberValue: PSObject property set failed: $($_.Exception.Message)"
    }
}

function Get-CurrentVersion-ImageMagick {
    param(
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $ServiceContainer
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

    $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'ImageMagick' }

    if ($FileSystem) {
        $CurrentVersion = @($FileSystem.GetChildItem($Paths.Root, "$pluginName*", 'Directory')) | Select-Object -First 1
    }
    else {
        $CurrentVersion = Get-ChildItem -Path $Paths.Root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$pluginName*" }
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
        [hashtable]$Plugin,
        [hashtable]$Paths,
        $ServiceContainer
    )
    $null = $Paths, $ServiceContainer

    $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'ImageMagick' }
    $versionUrl = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'VersionUrl')
    $assetPattern = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'AssetPattern')
    $baseUri = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'BaseUri')

    try {
        $Response = Invoke-WebRequest -Uri $versionUrl -TimeoutSec 10
    }
    catch {
        throw [PluginRequirementException]::new("Failed to retrieve version information from $versionUrl", $pluginName, $_.Exception)
    }
    # Do not format output; we need raw string parsing
    $ZipMatches = [System.Text.RegularExpressions.Regex]::Matches($Response.Content, $assetPattern, 'IgnoreCase')

    if ($ZipMatches.Count -eq 0) {
        throw [PluginRequirementException]::new("No matching 'portable-Q16-HDRI-x64.zip' downloads found on $versionUrl", $pluginName)
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

    $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
    if ($null -eq $state) {
        $state = @{}
        Set-ConfigMemberValue -Object $pluginConfig -Name 'State' -Value $state
    }
    Set-ConfigMemberValue -Object $state -Name 'LatestVersion' -Value $LatestVersion
    Set-ConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $LatestInstaller

    # Compose direct download URL as plain string
    $Url = "$baseUri/$LatestInstaller"
    return [string]$Url
}

function Get-Installer-ImageMagick {
    param(
        [string]$Url,
        [hashtable]$Plugin,
        [hashtable]$Paths
    )
    $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
    $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
    if ([string]::IsNullOrWhiteSpace($pluginName)) { $pluginName = 'ImageMagick' }
    $baseUri = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'BaseUri')
    $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
    $latestInstaller = [string](Get-ConfigMemberValue -Object $state -Name 'LatestInstaller')
    $Url = $baseUri + '/' + $latestInstaller
    Write-PSmmLog -Level INFO -Context "Download $pluginName" -Message "Downloading $pluginName from $Url ..." -Console -File
    try {
        $outFile = Join-Path -Path $Paths._Downloads -ChildPath $latestInstaller
        Invoke-WebRequest -Uri "$Url" -OutFile $outFile
        $InstallerPath = Join-Path -Path $Paths._Downloads -ChildPath $latestInstaller
        Write-PSmmLog -Level SUCCESS -Context "Download $pluginName" -Message "$pluginName downloaded successfully to $InstallerPath" -Console -File
        return $InstallerPath
    }
    catch {
        Write-PSmmLog -Level ERROR -Context "Download $pluginName" -Message "Failed to download $pluginName from $Url" -ErrorRecord $_ -Console -File
        return $null
    }
}

#endregion ########## PRIVATE ##########
