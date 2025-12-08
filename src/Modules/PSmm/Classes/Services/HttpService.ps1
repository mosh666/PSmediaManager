<#
.SYNOPSIS
    Implementation of IHttpService interface.

.DESCRIPTION
    Provides testable HTTP/Web operations by wrapping PowerShell cmdlets.
    This service can be mocked in tests for full testability.

.NOTES
    Author: Der Mosh
    Requires: PowerShell 7.5.4 or higher
    Version: 1.0.0
#>

using namespace System
using namespace System.Net

<#
.SYNOPSIS
    Production implementation of HTTP service.
#>
class HttpService : IHttpService {

    [FileSystemService] $FileSystem

    HttpService() {
        try {
            $this.FileSystem = [FileSystemService]::new()
        }
        catch {
            throw [InvalidOperationException]::new('FileSystemService is required by HttpService and could not be initialized')
        }
    }

    <#
    .SYNOPSIS
        Invokes an HTTP request and returns the result.
    #>
    [object] InvokeRequest([string]$uri, [hashtable]$headers) {
        if ([string]::IsNullOrWhiteSpace($uri)) {
            throw [ArgumentException]::new("URI cannot be empty", "uri")
        }

        $params = @{
            Uri = $uri
            ErrorAction = 'Stop'
        }

        if ($null -ne $headers -and $headers.Count -gt 0) {
            $params['Headers'] = $headers
        }

        try {
            # Route through internal wrapper to simplify testing/mocking
            return Invoke-HttpRestMethod -Uri $uri -Method 'GET' -Headers $headers
        }
        catch {
            throw [WebException]::new("Failed to invoke request to $uri : $_", $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        Downloads a file from a URI to a local path.
    #>
    [void] DownloadFile([string]$uri, [string]$outFile) {
        if ([string]::IsNullOrWhiteSpace($uri)) {
            throw [ArgumentException]::new("URI cannot be empty", "uri")
        }

        if ([string]::IsNullOrWhiteSpace($outFile)) {
            throw [ArgumentException]::new("Output file path cannot be empty", "outFile")
        }

        # Ensure directory exists via FileSystem service
        $directory = Split-Path -Path $outFile -Parent
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            if (-not $this.FileSystem.TestPath($directory)) {
                $null = $this.FileSystem.NewItem($directory, 'Directory')
            }
        }

        try {
            # Route through internal wrapper to simplify testing/mocking
            Invoke-HttpWebRequest -Uri $uri -OutFile $outFile
        }
        catch {
            throw [WebException]::new("Failed to download file from $uri : $_", $_.Exception)
        }
    }

    <#
    .SYNOPSIS
        Invokes a REST method with full control over HTTP method and body.
    #>
    [object] InvokeRestMethod([string]$uri, [string]$method, [hashtable]$headers, [object]$body) {
        if ([string]::IsNullOrWhiteSpace($uri)) {
            throw [ArgumentException]::new("URI cannot be empty", "uri")
        }

        $effectiveMethod = if ([string]::IsNullOrWhiteSpace($method)) { 'GET' } else { $method }

        try {
            # Route through internal wrapper to simplify testing/mocking
            return Invoke-HttpRestMethod -Uri $uri -Method $effectiveMethod -Headers $headers -Body $body
        }
        catch {
            throw [WebException]::new("Failed to invoke REST method $method on $uri : $_", $_.Exception)
        }
    }
}
