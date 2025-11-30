<#
.SYNOPSIS
    System secret management using KeePassXC.

.DESCRIPTION
    Provides centralized secret retrieval for system-level secrets (GitHub tokens, API keys, etc.)
    using KeePassXC as the exclusive storage mechanism.

    Secrets are organized in a central PSmm_System.kdbx database with proper grouping:
    - System/GitHub/API-Token
    - System/API/General
    - System/Certificates/SSL

.PARAMETER SecretType
    The type of secret to retrieve.
    Valid values: 'GitHub-Token', 'APIKey', 'Certificate'

.PARAMETER AsPlainText
    If specified, returns the secret as plain text. Otherwise returns as SecureString (recommended).

.PARAMETER VaultPath
    Path to the KeePass vault directory. Defaults to d:\PSmediaManager\Vault

.EXAMPLE
    $token = Get-SystemSecret -SecretType 'GitHub-Token'
    Retrieves GitHub token as SecureString from KeePassXC.

.EXAMPLE
    $apiKey = Get-SystemSecret -SecretType 'APIKey' -AsPlainText
    Retrieves API key as plain text (use with caution).

.OUTPUTS
    SecureString - When -AsPlainText is not specified (default, recommended)
    String - When -AsPlainText is specified

.NOTES
    - KeePassXC must be installed and keepassxc-cli.exe must be in PATH
    - Master password is prompted by KeePassXC CLI (cached in session)
    - Use Initialize-SystemVault to create the KeePass database
    - Use Save-SystemSecret to store new secrets
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

# Ensure module-scoped cache exists
if (-not (Get-Variable -Name _VaultMasterPasswordCache -Scope Script -ErrorAction SilentlyContinue)) {
    $script:_VaultMasterPasswordCache = $null
}

function Get-KeePassCliCandidatePaths {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Returns multiple candidate paths; plural noun is intentional')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultPath
    )

    $paths = [System.Collections.Generic.List[string]]::new()

    $programRoots = @()
    if ($env:ProgramFiles) { $programRoots += $env:ProgramFiles }
    if (${env:ProgramFiles(x86)}) { $programRoots += ${env:ProgramFiles(x86)} }
    if ($env:LOCALAPPDATA) { $programRoots += (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs') }

    foreach ($root in $programRoots | Select-Object -Unique) {
        $candidate = Join-Path -Path $root -ChildPath 'KeePassXC'
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            $paths.Add((Resolve-Path -LiteralPath $candidate).Path)
        }
    }

    $vaultRoot = Split-Path -Path $VaultPath -Parent
    $portableRootCandidates = @()
    if ($vaultRoot) {
        $portableRootCandidates += (Join-Path -Path $vaultRoot -ChildPath 'PSmm.Plugins')
        $portableRootCandidates += (Join-Path -Path $vaultRoot -ChildPath 'Plugins')
        $portableRootCandidates += (Join-Path -Path $vaultRoot -ChildPath 'PSmediaManager\Plugins')
    }

    foreach ($portableRoot in ($portableRootCandidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $portableRoot)) {
            continue
        }

        try {
            Get-ChildItem -Path $portableRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'KeePassXC' } |
                ForEach-Object { $paths.Add($_.FullName) }
        }
        catch {
            Write-Verbose "Failed to enumerate KeePassXC directory candidates at $portableRoot : $_"
        }
    }

    return $paths | Select-Object -Unique
}

function Resolve-KeePassCliCommand {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultPath
    )

    $result = [ordered]@{
        Command = $null
        CandidatePaths = @()
        ResolvedExecutable = $null
    }

    $cli = Get-Command 'keepassxc-cli.exe' -ErrorAction SilentlyContinue
    if ($cli) {
        $result.Command = $cli
        return [pscustomobject]$result
    }

    $candidatePaths = Get-KeePassCliCandidatePaths -VaultPath $VaultPath
    $result.CandidatePaths = $candidatePaths

    if (-not $candidatePaths) {
        return [pscustomobject]$result
    }

    $exeCandidates = @()
    foreach ($base in $candidatePaths) {
        try {
            $exeCandidates += Get-ChildItem -Path $base -Filter 'keepassxc-cli.exe' -Recurse -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty FullName
        }
        catch {
            Write-Verbose "Failed to inspect KeePassXC path $base : $_"
        }
    }

    $resolvedCli = $exeCandidates | Sort-Object -Unique | Select-Object -First 1
    if ($resolvedCli) {
        $resolvedDir = Split-Path -Parent $resolvedCli
        Write-Verbose "Resolved keepassxc-cli.exe at: $resolvedCli"
        if ($env:PATH -notlike "*${resolvedDir}*") {
            $env:PATH = "$resolvedDir;$env:PATH"
            Write-Verbose 'Added KeePassXC directory to PATH for current session.'
        }
        $result.ResolvedExecutable = $resolvedCli
        $result.Command = Get-Command 'keepassxc-cli.exe' -ErrorAction SilentlyContinue
    }

    return [pscustomobject]$result
}

function ConvertTo-SecretSecureString {
    [CmdletBinding()]
    [OutputType([SecureString])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    $secure = [System.Security.SecureString]::new()
    foreach ($char in $Value.ToCharArray()) {
        $secure.AppendChar($char)
    }
    $secure.MakeReadOnly()
    return $secure
}

function Get-SystemSecret {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive prompts require explicit host output.')]
    [OutputType([SecureString], [string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GitHub-Token', 'APIKey', 'Certificate')]
        [string]$SecretType,

        [Parameter()]
        [switch]$AsPlainText,

        [Parameter()]
        [string]$VaultPath,

        [Parameter()]
        [switch]$Optional
    )

    try {
        # Resolve vault path from parameter, environment, or app configuration to avoid hardcoded literals
        if (-not $VaultPath -or [string]::IsNullOrWhiteSpace($VaultPath)) {
            if ($env:PSMM_VAULT_PATH) {
                $VaultPath = $env:PSMM_VAULT_PATH
            }
            elseif (Get-Command -Name Get-AppConfiguration -ErrorAction SilentlyContinue) {
                try { $VaultPath = (Get-AppConfiguration).Paths.App.Vault } catch { }
            }
            if (-not $VaultPath) {
                if ($Optional) {
                    Write-Verbose 'VaultPath not set; optional secret retrieval returning null.'
                    return $null
                }
                throw 'VaultPath is not set. Provide -VaultPath or set PSMM_VAULT_PATH.'
            }
        }
        Write-Verbose "Retrieving system secret: $SecretType"

        # Define KeePass entry mapping
        $entryMap = @{
            'GitHub-Token' = 'System/GitHub/API-Token'
            'APIKey' = 'System/API/General'
            'Certificate' = 'System/Certificates/SSL'
        }

        $entry = $entryMap[$SecretType]
        $dbPath = Join-Path $VaultPath 'PSmm_System.kdbx'

        # Check if KeePass database exists
        if (-not (Test-Path $dbPath)) {
            $errorMsg = "KeePass database not found: $dbPath. Use Initialize-SystemVault to create it."
            if ($Optional) {
                Write-PSmmLog -Level NOTICE -Context 'Get-SystemSecret' -Message $errorMsg -Console -File
                return $null
            }
            Write-PSmmLog -Level ERROR -Context 'Get-SystemSecret' -Message $errorMsg -Console -File
            throw $errorMsg
        }

        Write-Verbose "Retrieving from KeePassXC database: $dbPath"

        $cliResolution = Resolve-KeePassCliCommand -VaultPath $VaultPath
        $cli = $cliResolution.Command

        if (-not $cli) {
            $searched = if ($cliResolution.CandidatePaths) { $cliResolution.CandidatePaths -join ', ' } else { 'No candidate directories discovered' }
            $errorMsg = "keepassxc-cli.exe not found. Install KeePassXC or place the portable plugins folder so the CLI can be auto-resolved. Searched: $searched"
            if ($Optional) {
                Write-PSmmLog -Level NOTICE -Context 'Get-SystemSecret' -Message $errorMsg -Console -File
                return $null
            }
            Write-PSmmLog -Level ERROR -Context 'Get-SystemSecret' -Message $errorMsg -Console -File
            throw $errorMsg
        }

        # Retrieve password field from KeePass entry
        # Provide master password via stdin to avoid silent prompt and to allow custom messaging.
        Write-PSmmHost "Unlocking vault to read secret ($SecretType)..." -ForegroundColor Cyan

        # Resolve from cache if present
        $masterPw = $script:_VaultMasterPasswordCache
        if (-not $masterPw) {
            Write-PSmmHost "Enter vault master password (input hidden):" -ForegroundColor Yellow
            # Prompt user explicitly (KeePassXC would otherwise prompt without context)
            $masterPw = Read-Host 'Vault Master Password' -AsSecureString
            # Offer to cache for this session
            $cacheAns = Read-Host 'Cache this master password for this session? [Y/n]'
            if ([string]::IsNullOrWhiteSpace($cacheAns) -or $cacheAns.Trim().ToLower() -eq 'y') {
                $script:_VaultMasterPasswordCache = $masterPw
                Write-Verbose 'Vault master password cached for this session.'
            }
        }
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($masterPw)
        $plainMaster = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $tmpPw = [System.IO.Path]::GetTempFileName()
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $tmpErr = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText($tmpPw, "$plainMaster`n", [System.Text.Encoding]::ASCII)
            $proc = Start-Process -FilePath 'keepassxc-cli.exe' -ArgumentList 'show', '-s', '-a', 'Password', $dbPath, $entry -NoNewWindow -Wait -PassThru -RedirectStandardInput $tmpPw -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -ErrorAction Stop
            $secretValue = ''
            if ($proc.ExitCode -eq 0 -and (Test-Path $tmpOut)) {
                $secretValue = (Get-Content -Path $tmpOut -Raw -ErrorAction SilentlyContinue).Trim()
            }
        }
        finally {
            if (Test-Path $tmpPw) { Remove-Item $tmpPw -Force -ErrorAction SilentlyContinue }
            if (Test-Path $tmpOut) { Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue }
            if (Test-Path $tmpErr) { Remove-Item $tmpErr -Force -ErrorAction SilentlyContinue }
            $plainMaster = $null
        }

        if ($proc.ExitCode -eq 0 -and $secretValue) {
            Write-Verbose "Successfully retrieved $SecretType from KeePassXC"

            if ($AsPlainText) {
                return $secretValue
            }

            return ConvertTo-SecretSecureString -Value $secretValue
        }
        else {
            $exit = if ($null -ne $proc) { $proc.ExitCode } else { $LASTEXITCODE }
            $errorMsg = "Failed to retrieve from KeePassXC (exit code: $exit). Entry may not exist: $entry"
            if ($Optional) {
                Write-PSmmLog -Level NOTICE -Context 'Get-SystemSecret' -Message $errorMsg -Console -File
                return $null
            }
            Write-PSmmLog -Level ERROR -Context 'Get-SystemSecret' -Message $errorMsg -Console -File
            throw $errorMsg
        }
    }
    catch {
        $errorMessage = "Failed to retrieve system secret '$SecretType': $_"
        if ($Optional) {
            Write-PSmmLog -Level NOTICE -Context 'Get-SystemSecret' -Message $errorMessage -Console -File
            return $null
        }
        Write-PSmmLog -Level ERROR -Context 'Get-SystemSecret' -Message $errorMessage -ErrorRecord $_ -Console -File
        throw $errorMessage
    }
}

<#
.SYNOPSIS
    Gets metadata about a system secret from KeePassXC.

.DESCRIPTION
    Retrieves custom attributes and metadata from a KeePassXC entry without
    exposing the actual secret value. Useful for checking expiration dates,
    scopes, and other non-sensitive information.

.PARAMETER SecretType
    The type of secret to query.

.PARAMETER AttributeName
    Specific attribute to retrieve (e.g., 'Scope', 'ExpiresOn', 'Created').
    If not specified, lists all custom attributes.

.PARAMETER VaultPath
    Path to the KeePass vault directory.

.EXAMPLE
    Get-SystemSecretMetadata -SecretType 'GitHub-Token' -AttributeName 'ExpiresOn'
    Returns the expiration date of the GitHub token.

.EXAMPLE
    Get-SystemSecretMetadata -SecretType 'GitHub-Token'
    Lists all custom attributes for the GitHub token entry.

.OUTPUTS
    String or Hashtable of attributes
#>
function Get-SystemSecretMetadata {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function returns detailed metadata collection for a single secret.')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GitHub-Token', 'APIKey', 'Certificate')]
        [string]$SecretType,

        [Parameter()]
        [string]$AttributeName,

        [Parameter()]
        [string]$VaultPath = 'd:\_mediaManager_\Vault'
    )

    try {
        $entryMap = @{
            'GitHub-Token' = 'System/GitHub/API-Token'
            'APIKey' = 'System/API/General'
            'Certificate' = 'System/Certificates/SSL'
        }

        $entry = $entryMap[$SecretType]
        $dbPath = Join-Path $VaultPath 'PSmm_System.kdbx'

        if (-not (Test-Path $dbPath)) {
            throw "KeePass database not found: $dbPath"
        }

        $cliCheck = Get-Command 'keepassxc-cli.exe' -ErrorAction SilentlyContinue
        if (-not $cliCheck) {
            # Attempt same auto-resolution strategy
            $pluginsRoot = (Split-Path -Parent $VaultPath)
            $portableDir = Join-Path $pluginsRoot 'Plugins'
            if (Test-Path $portableDir) {
                $kpDir = Get-ChildItem -Path $portableDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'KeePassXC' } | Select-Object -First 1
                if ($kpDir) {
                    $exe = Get-ChildItem -Path $kpDir.FullName -Filter 'keepassxc-cli.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($exe) {
                        $dir = Split-Path -Parent $exe.FullName
                        if ($env:PATH -notlike "*${dir}*") { $env:PATH = "$dir;$env:PATH" }
                        $cliCheck = Get-Command 'keepassxc-cli.exe' -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        if (-not $cliCheck) { throw 'keepassxc-cli.exe not found (after auto-resolution attempt)' }

        if ($AttributeName) {
            # Get specific attribute
            $result = & keepassxc-cli.exe show -s -a "$AttributeName" "$dbPath" "$entry" 2>&1

            if ($LASTEXITCODE -eq 0) {
                return $result
            }
            else {
                throw "Failed to retrieve attribute '$AttributeName' (exit code: $LASTEXITCODE)"
            }
        }
        else {
            # List all attributes
            $result = & keepassxc-cli.exe show "$dbPath" "$entry" 2>&1

            if ($LASTEXITCODE -eq 0) {
                return $result
            }
            else {
                throw "Failed to retrieve entry information (exit code: $LASTEXITCODE)"
            }
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Get-SystemSecretMetadata' `
            -Message "Failed to retrieve metadata for '$SecretType': $_" -Console -File
        throw
    }
}
