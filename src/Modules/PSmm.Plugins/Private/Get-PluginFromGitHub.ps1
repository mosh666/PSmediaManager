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
    $token = Get-SecureSecret -Path (Join-Path -Path $Config.Paths.App.Vault -ChildPath 'GitHub-Token.txt')
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
        $Http,

        [Parameter()]
        $Crypto
    )

    # Lazy instantiation to avoid parse-time type resolution
    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"

    try {
        Write-Verbose "Fetching latest release for: $Repo"

        # Build request headers (optionally authenticated)
        $headers = @{
            'User-Agent' = 'PSmediaManager-PSmm.Plugins'
            'Accept'     = 'application/vnd.github.v3+json'
        }

        # Fallback: obtain token securely from system vault when not provided
        if ($null -eq $Token -and (Get-Command -Name Get-SystemSecret -ErrorAction SilentlyContinue)) {
                try {
                    $Token = Get-SystemSecret -SecretType 'GitHub-Token' -Optional
                }
                catch {
                    Write-Verbose "Could not retrieve GitHub token from system vault: $_"
                }
        }

        if ($null -ne $Token) {
            try {
                $plainToken = $Crypto.ConvertFromSecureString($Token)
                if ($plainToken) {
                    $headers.Authorization = "token $plainToken"
                    Write-Verbose 'Using authenticated GitHub request'
                }
            }
            catch {
                Write-Verbose "Failed to use provided GitHub token, falling back to unauthenticated request: $_"
            }
        }

        $response = $Http.InvokeRestMethod($apiUrl, 'GET', $headers, $null)

        Write-Verbose "Successfully retrieved release: $($response.tag_name)"
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
        [hashtable]$Plugin,

        [Parameter()]
        [SecureString]$Token = $null,

        [Parameter()]
        $Http,

        [Parameter()]
        $Crypto
    )

    # Lazy instantiation to avoid parse-time type resolution

    try {
        # Validate required plugin configuration
        if (-not $Plugin.ContainsKey('Config')) {
            throw "Plugin hashtable missing required 'Config' key"
        }
        if (-not $Plugin.Config.ContainsKey('Repo')) {
            throw "Plugin.Config missing required 'Repo' key"
        }
        if (-not $Plugin.Config.ContainsKey('AssetPattern')) {
            throw "Plugin.Config missing required 'AssetPattern' key"
        }

        $pluginName = $Plugin.Config.Name
        $repo = $Plugin.Config.Repo
        $assetPattern = $Plugin.Config.AssetPattern

        Write-Verbose "Getting latest release URL for: $pluginName from $repo"

        # Get latest release information
        $release = Get-GitHubLatestRelease -Repo $repo -Token $Token -Http $Http -Crypto $Crypto

        if (-not $release) {
            Write-Warning "Could not retrieve release information for: $pluginName"
            return $null
        }

        # Store latest version
        $latestVersion = $release.tag_name
        if (-not $Plugin.Config.ContainsKey('State')) {
            $Plugin.Config.State = @{}
        }
        $Plugin.Config.State.LatestVersion = $latestVersion
        Write-Verbose "Latest version: $latestVersion"

        # Find matching asset
        $matchingAsset = Find-MatchingReleaseAsset -Release $release `
            -Pattern $assetPattern `
            -PluginName $pluginName

        if (-not $matchingAsset) {
            return $null
        }

        # Store installer information and return URL
        $Plugin.Config.State.LatestInstaller = $matchingAsset.name
        $downloadUrl = $matchingAsset.browser_download_url

        Write-Verbose "Found matching asset: $($matchingAsset.name)"
        Write-Verbose "Download URL: $downloadUrl"

        return $downloadUrl
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Get Plugin URL' `
            -Message "Failed to get latest URL for $($Plugin.Config.Name): $_" `
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
