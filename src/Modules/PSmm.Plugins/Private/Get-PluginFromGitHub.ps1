<#
.SYNOPSIS
    GitHub plugin management functions for PSmediaManager.

.DESCRIPTION
    Provides functionality to query GitHub releases, download plugins from GitHub
    repositories, and manage plugin versions. Supports authenticated API access
    for higher rate limits.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

# Script-level GitHub release cache (repo -> @{ Release; ExpiresAt })
if (-not (Get-Variable -Name GitHubReleaseCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:GitHubReleaseCache = @{}
}

#region ########## PRIVATE ##########

<#
.SYNOPSIS
    Retrieves the latest release information from a GitHub repository.

.DESCRIPTION
    Queries the GitHub API to fetch details about the latest release of a
    repository. Supports authenticated requests using a personal access token
    to avoid rate limiting.

.PARAMETER Repo
    The GitHub repository in format 'owner/repository' (e.g., 'microsoft/vscode').

.PARAMETER Token
    GitHub personal access token as SecureString for authenticated API requests.
    Provides higher rate limits (5000 requests/hour vs 60 for unauthenticated).

.PARAMETER Http
    HTTP service (injectable for testing).

.PARAMETER Crypto
    Cryptographic service (injectable for testing).

.EXAMPLE
    $vaultPath = 'C:\Path\To\Vault'
    $token = Get-SecureSecret -Path (Join-Path -Path $vaultPath -ChildPath 'GitHub-Token.txt')
    $release = Get-GitHubLatestRelease -Repo 'git-lfs/git-lfs' -Token $token
    Retrieves the latest Git LFS release information.

.OUTPUTS
    PSCustomObject - GitHub release object with properties like tag_name, assets, etc.
    Returns $null if the request fails.

.NOTES
    - Requires GitHub API v3
    - Handles authentication securely using SecureString
    - Rate limits: 5000/hour (authenticated) vs 60/hour (unauthenticated)
    - Returns $null on failure with error logged
#>
function Get-GitHubLatestRelease {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Crypto', Justification = 'Parameter reserved for future cryptographic operations')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[\w\-\.]+/[\w\-\.]+$')]
        [string]$Repo,

        [Parameter()]
        [SecureString]$Token = $null,

        [Parameter()]
        [int]$CacheSeconds = 300,

        [Parameter()]
        [switch]$ForceRefresh,

        [Parameter()]
        $Http,

        [Parameter()]
        $Crypto,

        [Parameter()]
        $FileSystem,

        [Parameter()]
        $Environment,

        [Parameter()]
        $PathProvider,

        [Parameter()]
        $Process
    )

    # Lazy instantiation to avoid parse-time type resolution
    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"

    try {
        Write-Verbose "Fetching latest release for: $Repo"

        # Serve from cache when valid and not forced
        if (-not $ForceRefresh -and $script:GitHubReleaseCache.ContainsKey($Repo)) {
            $cached = $script:GitHubReleaseCache[$Repo]
            if ($cached -and $cached.ExpiresAt -gt (Get-Date)) {
                Write-Verbose "Using cached release for $Repo (expires $($cached.ExpiresAt))"
                return $cached.Release
            }
        }

        # Build request headers (optionally authenticated) and support ETag cache validation
        $headers = @{
            'User-Agent' = 'PSmediaManager-PSmm.Plugins'
            'Accept'     = 'application/vnd.github.v3+json'
        }

        $cachedEntry = $script:GitHubReleaseCache[$Repo]
        if (-not $ForceRefresh -and $cachedEntry -and $cachedEntry.ETag) {
            $headers['If-None-Match'] = $cachedEntry.ETag
            Write-Verbose "Sending If-None-Match with cached ETag: $($cachedEntry.ETag)"
        }

        # Fallback: obtain token securely from system vault when not provided
        if ($null -eq $Token -and (Get-Command -Name Get-SystemSecret -ErrorAction SilentlyContinue)) {
                try {
                    if ($null -ne $FileSystem -and $null -ne $Environment -and $null -ne $PathProvider -and $null -ne $Process) {
                        $Token = Get-SystemSecret -SecretType 'GitHub-Token' -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process -Optional
                    }
                }
                catch {
                    Write-Verbose "Could not retrieve GitHub token from system vault: $_"
                }
        }

        if ($null -ne $Token) {
            try {
                $plainToken = $null
                if ($Token -is [System.Security.SecureString]) {
                    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
                    try { $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) } finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
                }
                elseif ($Token -is [string]) {
                    $plainToken = $Token
                }

                if ([string]::IsNullOrWhiteSpace($plainToken)) {
                    Write-Verbose 'GitHub token resolved empty; using unauthenticated request'
                }
                else {
                    $headers.Authorization = "token $plainToken"
                    Write-Verbose 'Using authenticated GitHub request'
                }
            }
            catch {
                Write-Verbose "Failed to process GitHub token, falling back to unauthenticated request: $_"
            }
        }

        # Prefer Invoke-WebRequest for header (ETag) access; fallback to service on errors
        try {
            $raw = Invoke-WebRequest -Uri $apiUrl -Headers $headers -Method GET -ErrorAction Stop
            if ($raw.StatusCode -eq 304 -and $cachedEntry) {
                Write-Verbose "GitHub responded 304 Not Modified; extending cache TTL"
                $cachedEntry.ExpiresAt = (Get-Date).AddSeconds($CacheSeconds)
                return $cachedEntry.Release
            }
            elseif ($raw.StatusCode -eq 200) {
                $release = $raw.Content | ConvertFrom-Json
                $etag = $raw.Headers['ETag']
                $script:GitHubReleaseCache[$Repo] = @{ Release = $release; ExpiresAt = (Get-Date).AddSeconds($CacheSeconds); ETag = $etag }
                Write-Verbose "Successfully retrieved release: $($release.tag_name); Cached with ETag: $etag"
                return $release
            }
            else {
                Write-Verbose "Unexpected status code $($raw.StatusCode); falling back to HTTP service"
            }
        }
        catch {
            Write-Verbose "Invoke-WebRequest path failed: $($_.Exception.Message); attempting HttpService"
        }

        $response = $Http.InvokeRestMethod($apiUrl, 'GET', $headers, $null)
        $script:GitHubReleaseCache[$Repo] = @{ Release = $response; ExpiresAt = (Get-Date).AddSeconds($CacheSeconds); ETag = $null }
        Write-Verbose "Successfully retrieved release (no ETag capture): $($response.tag_name)"
        return $response
    }
    catch {
        $errorMessage = $_.Exception.Message

        if ($_.Exception.Response) {
            try {
                if ($_.Exception.Response.StatusCode) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                    $errorMessage = "HTTP ${statusCode}: $errorMessage"
                }
            }
            catch {
                Write-Verbose "Unable to read HTTP status code from GitHub response: $_"
            }
        }

        # Treat 304 in catch as soft success when cached entry exists
        try {
            $statusCodeCatch = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $statusCodeCatch = [int]$_.Exception.Response.StatusCode }
            if ($statusCodeCatch -eq 304 -and $cachedEntry) {
                Write-Verbose "GitHub 304 Not Modified (exception path); using cached release and extending TTL"
                $cachedEntry.ExpiresAt = (Get-Date).AddSeconds($CacheSeconds)
                return $cachedEntry.Release
            }
        }
        catch {
            Write-Verbose "Failed to parse 304 status code: $_"
        }

        Write-PSmmLog -Level ERROR -Context 'Get GitHub Release' `
            -Message "Failed to fetch release info for ${Repo}: $errorMessage" `
            -ErrorRecord $_ -Console -File

        return $null
    }

}

<#
    based on the configured pattern, and returns its download URL. Updates the
    plugin configuration with latest version and installer information.

.PARAMETER Plugin
    Plugin configuration hashtable with structure:
    - Config.Repo: GitHub repository (owner/repo)
    - Config.AssetPattern: Wildcard pattern to match asset name
    - Config.Name: Plugin display name
    - Config.State.LatestVersion: (output) Latest version tag
    - Config.State.LatestInstaller: (output) Latest installer filename

.PARAMETER Paths
    Paths configuration hashtable (reserved for future use).

.PARAMETER Token
    GitHub personal access token as SecureString.

.PARAMETER Http
    HTTP service (injectable for testing).

.PARAMETER Crypto
    Cryptographic service (injectable for testing).

.EXAMPLE
    $plugin = @{
        Config = @{
            Repo = 'git-lfs/git-lfs'
            AssetPattern = '*windows-amd64*.zip'
            Name = 'git-lfs'
            State = @{}
        }
    }
    $url = Get-LatestUrlFromGitHub -Plugin $plugin -Token $token
    Returns download URL and updates plugin state with version info.

.OUTPUTS
    String - Download URL for the latest matching asset, or $null if not found.

.NOTES
    - Updates Plugin.Config.State.LatestVersion with release tag
    - Updates Plugin.Config.State.LatestInstaller with asset filename
    - Returns $null if release not found or no matching asset
    - Selects first matching asset if multiple matches exist
#>
function Get-LatestUrlFromGitHub {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Plugin,

        [Parameter()]
        [SecureString]$Token = $null,

        [Parameter()]
        $Http,

        [Parameter()]
        $Crypto,

        [Parameter()]
        $FileSystem,

        [Parameter()]
        $Environment,

        [Parameter()]
        $PathProvider,

        [Parameter()]
        $Process
    )

    # Lazy instantiation to avoid parse-time type resolution

    try {
        function Get-ConfigMemberValue([object]$Object, [string]$Name) {
            if ($null -eq $Object) {
                return $null
            }

            if ($Object -is [System.Collections.IDictionary]) {
                try {
                    if ($Object.ContainsKey($Name)) {
                        return $Object[$Name]
                    }
                }
                catch {
                    # fall through
                }

                try {
                    if ($Object.Contains($Name)) {
                        return $Object[$Name]
                    }
                }
                catch {
                    # fall through
                }

                try {
                    foreach ($k in $Object.Keys) {
                        if ($k -eq $Name) {
                            return $Object[$k]
                        }
                    }
                }
                catch {
                    # fall through
                }

                return $null
            }

            try {
                $p = $Object.PSObject.Properties[$Name]
                if ($null -ne $p) {
                    return $p.Value
                }
            }
            catch {
                # fall through
            }

            return $null
        }

        function Set-ConfigMemberValue([object]$Object, [string]$Name, [object]$Value) {
            if ($null -eq $Object) {
                return $false
            }

            if ($Object -is [System.Collections.IDictionary]) {
                try {
                    $Object[$Name] = $Value
                    return $true
                }
                catch {
                    return $false
                }
            }

            try {
                $prop = $Object.PSObject.Properties[$Name]
                if ($null -ne $prop) {
                    $prop.Value = $Value
                    return $true
                }
            }
            catch {
                # fall through
            }

            try {
                $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
                return $true
            }
            catch {
                return $false
            }
        }

        # Validate required plugin configuration
        $pluginConfig = Get-ConfigMemberValue -Object $Plugin -Name 'Config'
        if ($null -eq $pluginConfig) {
            throw [PluginRequirementException]::new("Plugin missing required 'Config' member", "Plugin")
        }

        $pluginName = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Name')
        $repo = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'Repo')
        $assetPattern = [string](Get-ConfigMemberValue -Object $pluginConfig -Name 'AssetPattern')

        if ([string]::IsNullOrWhiteSpace($repo)) {
            throw [PluginRequirementException]::new("Plugin.Config missing required 'Repo' member", $pluginName)
        }
        if ([string]::IsNullOrWhiteSpace($assetPattern)) {
            throw [PluginRequirementException]::new("Plugin.Config missing required 'AssetPattern' member", $pluginName)
        }

        Write-Verbose "Getting latest release URL for: $pluginName from $repo"

        # Get latest release information
        $release = Get-GitHubLatestRelease -Repo $repo -Token $Token -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process

        if (-not $release) {
            Write-Warning "Could not retrieve release information for: $pluginName"
            return $null
        }

        # Store latest version
        $latestVersion = $release.tag_name
        $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
        if ($null -eq $state) {
            $null = Set-ConfigMemberValue -Object $pluginConfig -Name 'State' -Value @{}
            $state = Get-ConfigMemberValue -Object $pluginConfig -Name 'State'
        }
        $null = Set-ConfigMemberValue -Object $state -Name 'LatestVersion' -Value $latestVersion
        Write-Verbose "Latest version: $latestVersion"

        # Find matching asset
        $matchingAsset = Find-MatchingReleaseAsset -Release $release `
            -Pattern $assetPattern `
            -PluginName $pluginName

        if (-not $matchingAsset) {
            return $null
        }

        # Store installer information and return URL
        $null = Set-ConfigMemberValue -Object $state -Name 'LatestInstaller' -Value $matchingAsset.name
        $downloadUrl = $matchingAsset.browser_download_url

        Write-Verbose "Found matching asset: $($matchingAsset.name)"
        Write-Verbose "Download URL: $downloadUrl"

        return $downloadUrl
    }
    catch {
        $safeName = $null
        try {
            if ($null -eq $safeName -or $safeName -eq '') {
                if (Get-Variable -Name pluginName -Scope Local -ErrorAction SilentlyContinue) {
                    $safeName = $pluginName
                }
            }
        }
        catch {
            $safeName = $null
        }

        if ([string]::IsNullOrWhiteSpace([string]$safeName)) {
            $safeName = 'UNKNOWN'
        }

        Write-PSmmLog -Level ERROR -Context 'Get Plugin URL' `
            -Message "Failed to get latest URL for ${safeName}: $_" `
            -ErrorRecord $_ -Console -File
        return $null
    }
}

<#
.SYNOPSIS
    Finds a release asset matching the specified pattern.

.PARAMETER Release
    GitHub release object containing assets collection.

.PARAMETER Pattern
    Wildcard pattern to match against asset names.

.PARAMETER PluginName
    Plugin name for logging purposes.

.OUTPUTS
    PSCustomObject - Matching asset object, or $null if not found.
#>
function Find-MatchingReleaseAsset {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Release,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PluginName
    )

    try {
        if (-not $Release.assets -or $Release.assets.Count -eq 0) {
            Write-Warning "No assets found in release for: $PluginName"
            return $null
        }

        Write-Verbose "Searching for assets matching pattern: $Pattern"

        # Find matching assets
        $matchingAssets = $Release.assets | Where-Object { $_.name -like $Pattern }

        if (-not $matchingAssets) {
            Write-PSmmLog -Level WARNING -Context "Check $PluginName" `
                -Message "No matching asset found for pattern: $Pattern" -Console -File

            # Log available assets for debugging
            $availableAssets = ($Release.assets | Select-Object -ExpandProperty name) -join ', '
            Write-Verbose "Available assets: $availableAssets"

            return $null
        }

        # Select first match if multiple found
        $selectedAsset = if ($matchingAssets -is [array]) {
            Write-Verbose "Multiple assets matched pattern, selecting first: $($matchingAssets[0].name)"
            $matchingAssets[0]
        }
        else {
            $matchingAssets
        }

        return $selectedAsset
    }
    catch {
        Write-Verbose "Error finding matching asset: $_"
        return $null
    }
}

#endregion ########## PRIVATE ##########
