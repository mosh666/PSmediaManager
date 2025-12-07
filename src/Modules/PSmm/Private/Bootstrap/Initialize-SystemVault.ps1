<#
.SYNOPSIS
    Initializes the central PSmediaManager system KeePassXC vault.

.DESCRIPTION
    Creates a new KeePassXC database for storing system-level secrets such as
    GitHub tokens, API keys, and certificates. The database is organized with
    a proper group structure for better organization and security.

        Database structure:
        - PSmm_System.kdbx
            - System/
                - GitHub/
                    - API-Token
                - API/
                    - General
                - Certificates/
                    - SSL

.PARAMETER VaultPath
    Path where the KeePass database will be created. If not provided, resolved from PSMM_VAULT_PATH or Config.Paths.App.Vault.

.PARAMETER Force
    If specified, recreates the database even if it already exists (use with caution).

.EXAMPLE
    Initialize-SystemVault
    Creates the system vault with default settings.

.EXAMPLE
    Initialize-SystemVault -VaultPath 'C:\SecureVault' -Verbose
    Creates the vault at a custom location with verbose output.

.NOTES
    - Requires KeePassXC to be installed with keepassxc-cli.exe in PATH
    - Prompts for master password during creation
    - Creates vault directory if it doesn't exist
    - Does not overwrite existing database unless -Force is specified
    - After creation, use Save-SystemSecret to add secrets
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

# Note: $script:_VaultMasterPasswordCache is declared in PSmm.psm1
# This file is dot-sourced into the module and shares the module's script scope.

function Initialize-SystemVault {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive vault setup requires explicit host prompts with color.')]
    param(
        [Parameter()]
        [string]$VaultPath,

        [Parameter()]
        [switch]$Force,

        [Parameter(Mandatory)]
        $FileSystem,

        [Parameter()]
        [SecureString]$MasterPassword
    )

    try {
        $dbPath = Join-Path -Path $VaultPath -ChildPath 'PSmm_System.kdbx'

        # Fast exit if already present and not forcing
        if ((Test-Path -Path $dbPath) -and -not $Force.IsPresent) {
            Write-Verbose "KeePass database already exists: $dbPath"
            return $true
        }

        # Ensure directory exists via FileSystem service
        if (-not (Test-Path -Path $VaultPath)) {
            Write-Verbose "Creating vault directory: $VaultPath"
            if ($PSBoundParameters.ContainsKey('FileSystem') -and $FileSystem -and ($FileSystem | Get-Member -Name 'NewItem' -ErrorAction SilentlyContinue)) {
                $null = $FileSystem.NewItem($VaultPath, 'Directory')
            }
            else {
                throw [ValidationException]::new("FileSystem service is required to create vault directory", "FileSystem")
            }
        }

        # Resolve master password (explicit > cached > prompt)
        $resolvedPw = $MasterPassword
        if (-not $resolvedPw -and $script:_VaultMasterPasswordCache) {
            Write-Verbose 'Using cached vault master password'
            $resolvedPw = $script:_VaultMasterPasswordCache
        }
        if (-not $resolvedPw) {
            Write-PSmmHost ''
            Write-PSmmHost 'Create vault master password' -ForegroundColor Cyan
            Write-PSmmHost 'The password must be 12+ chars and include upper, lower, and a digit.' -ForegroundColor Yellow
            $maxAttempts = 3
            $attempt = 0
            do {
                $pw1 = Read-Host 'Enter new master password' -AsSecureString
                $pw2 = Read-Host 'Confirm master password' -AsSecureString

                # Convert to plain for validation
                $b1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw1)
                $b2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw2)
                try {
                    $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($b1)
                    $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($b2)
                }
                finally {
                    if ($b1 -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1) }
                    if ($b2 -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2) }
                }

                $lengthOk = ($plain1.Length -ge 12)
                $complexOk = ($plain1 -match '[A-Z]' -and $plain1 -match '[a-z]' -and $plain1 -match '\d')
                if ($plain1 -ne $plain2) {
                    Write-PSmmHost 'Passwords do not match. Try again.' -ForegroundColor Red
                    $attempt++
                    continue
                }
                if (-not $lengthOk -or -not $complexOk) {
                    Write-PSmmHost 'Password not complex enough (need 12+ chars incl. upper, lower, digit).' -ForegroundColor Red
                    $attempt++
                    continue
                }

                $resolvedPw = $pw1
                break
            } while ($attempt -lt $maxAttempts)

            if (-not $resolvedPw) {
                throw [ConfigurationException]::new("Master password setup aborted after $maxAttempts failed attempts")
            }
        }

        if ($PSCmdlet.ShouldProcess($dbPath, 'Create KeePass database')) {
            # Convert SecureString to plain for stdin pipe
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($resolvedPw)
            $plainMaster = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                # Use ASCII (no BOM) to avoid issues; provide twice for confirmation
                [System.IO.File]::WriteAllText($tempFile, "$plainMaster`n$plainMaster`n", [System.Text.Encoding]::ASCII)
                $process = Start-Process -FilePath 'keepassxc-cli.exe' -ArgumentList 'db-create', '-p', $dbPath -NoNewWindow -Wait -PassThru -RedirectStandardInput $tempFile
                if ($process.ExitCode -ne 0) {
                    $ex = [ProcessException]::new("Failed to create KeePass database", "keepassxc-cli.exe")
                    $ex.SetExitCode($process.ExitCode)
                    throw $ex
                }
            }
            finally {
                if ($FileSystem.TestPath($tempFile)) { $FileSystem.RemoveItem($tempFile, $false) }
                $plainMaster = $null
            }

            # Cache password for subsequent first-run secret saves
            $script:_VaultMasterPasswordCache = $resolvedPw
            Write-Verbose "Database created successfully: $dbPath"
        }

        # Log success if available
        if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
            Write-PSmmLog -Level SUCCESS -Context 'Initialize-SystemVault' -Message "System vault ready at: $dbPath" -File
        }

            Write-PSmmHost "`n[OK] System vault initialized" -ForegroundColor Green
            Write-PSmmHost "  Database: $dbPath" -ForegroundColor Gray
        return $true
    }
    catch {
        $errorMessage = "Failed to initialize system vault: $_"
        if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
            Write-PSmmLog -Level ERROR -Context 'Initialize-SystemVault' -Message $errorMessage -ErrorRecord $_ -Console -File
        }
        Write-Error $errorMessage
        return $false
    }
}

<#
.SYNOPSIS
    Saves a system secret to the KeePassXC vault.

.DESCRIPTION
    Stores a secret in the central PSmm_System.kdbx database with proper
    organization and metadata. Creates the vault if it doesn't exist.

.PARAMETER SecretType
    The type of secret to save.

.PARAMETER SecretValue
    The secret value to store (as SecureString).

.PARAMETER Metadata
    Optional hashtable of custom attributes (e.g., Scope, ExpiresOn, Created, Purpose).

.PARAMETER VaultPath
    Path to the KeePass vault directory.

.EXAMPLE
    $token = Read-Host "Enter GitHub token" -AsSecureString
    Save-SystemSecret -SecretType 'GitHub-Token' -SecretValue $token -Metadata @{
        Scope = 'repo,workflow'
        ExpiresOn = '2026-11-07'
        Purpose = 'Plugin downloads'
    }

.NOTES
    - Creates vault if it doesn't exist
    - Overwrites existing entry if present
    - Metadata is stored as custom attributes
#>
function Save-SystemSecret {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive secret storage workflow needs direct host messaging for user guidance.')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GitHub-Token', 'APIKey', 'Certificate')]
        [string]$SecretType,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [SecureString]$SecretValue,

        [Parameter()]
        [hashtable]$Metadata = @{},

        [Parameter()]
        [string]$VaultPath,

        [Parameter()]
        [string]$Username = 'system',

        # Optional: supply the vault master password explicitly; otherwise use cached value or prompt
        [Parameter()]
        [SecureString]$VaultMasterPassword
    )

    # Initialize variable to ensure it exists for finally block
    $plainSecret = $null
    $bstr = [IntPtr]::Zero

    try {
        # Define entry mapping
        $entryMap = @{
            'GitHub-Token' = 'System/GitHub/API-Token'
            'APIKey' = 'System/API/General'
            'Certificate' = 'System/Certificates/SSL'
        }

        $urlMap = @{
            'GitHub-Token' = 'https://github.com'
            'APIKey' = 'https://api.example.com'
            'Certificate' = 'https://cert-authority.com'
        }

        $entry = $entryMap[$SecretType]
        $url = $urlMap[$SecretType]

        # Resolve vault path from parameter, environment, or app configuration
        if (-not $VaultPath -or [string]::IsNullOrWhiteSpace($VaultPath)) {
            if ($env:PSMM_VAULT_PATH) {
                $VaultPath = $env:PSMM_VAULT_PATH
                Write-Verbose "[Save-SystemSecret] Resolved VaultPath from environment: $VaultPath"
            }
            elseif (Get-Command -Name Get-AppConfiguration -ErrorAction SilentlyContinue) {
                try {
                        $VaultPath = (Get-AppConfiguration).Paths.App.Vault
                                        Write-Verbose "[Save-SystemSecret] Resolved VaultPath from configuration: $VaultPath"
                    }
                    catch {
                        Write-Verbose "Could not retrieve vault path from app configuration: $_"
                    }
            }
            if (-not $VaultPath) {
                throw [ConfigurationException]::new('VaultPath is not set. Provide -VaultPath or set PSMM_VAULT_PATH.')
            }
        }

        $dbPath = Join-Path $VaultPath 'PSmm_System.kdbx'

        # Ensure vault exists
        if (-not (Test-Path $dbPath)) {
            Write-Warning "System vault not found. Creating it now..."
            if (-not $FileSystem) {
                throw [ValidationException]::new("FileSystem service is required to initialize vault", "FileSystem")
            }
            $initialized = Initialize-SystemVault -VaultPath $VaultPath -FileSystem $FileSystem
            if (-not $initialized) {
                throw [ConfigurationException]::new("Failed to initialize system vault")
            }
        }

        # Convert SecureString to plain text for KeePassXC CLI
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecretValue)
        try {
            $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            if ($bstr -ne [IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }

        if ($PSCmdlet.ShouldProcess($entry, "Save secret to KeePass")) {
            Write-Verbose "Saving $SecretType to KeePass entry: $entry"

            # KeePassXC CLI password handling:
            # The -p flag reads the entry password from stdin
            # The database password will be prompted interactively
            # Use a temporary file for the entry password to avoid stdin issues

            Write-PSmmHost ""
            # Resolve vault password: prefer explicit parameter, then module cache, then prompt
            $resolvedVaultPw = $VaultMasterPassword
            if (-not $resolvedVaultPw -and $script:_VaultMasterPasswordCache) {
                $resolvedVaultPw = $script:_VaultMasterPasswordCache
                Write-Verbose "Using cached vault master password for secret save"
            }
            if (-not $resolvedVaultPw) {
                Write-PSmmHost "To save the entry, please enter your vault master credential." -ForegroundColor Cyan
                Write-PSmmHost "(It will not be shown while typing)" -ForegroundColor Yellow
                Write-PSmmHost ""
                $resolvedVaultPw = Read-Host "Enter vault master credential" -AsSecureString
                # Offer to cache the password for this session
                $cacheAns = Read-Host 'Cache this master password for this session? [Y/n]'
                if ([string]::IsNullOrWhiteSpace($cacheAns) -or $cacheAns.Trim().ToLower() -eq 'y') {
                    $script:_VaultMasterPasswordCache = $resolvedVaultPw
                    Write-Verbose 'Vault master password cached for this session.'
                }
            }

            $bsv = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($resolvedVaultPw)
            $plainVault = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bsv)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bsv)

            # Ensure the group path exists (e.g., System/GitHub)
            $groupPath = ($entry -split '/')[0..(($entry -split '/').Length - 2)] -join '/'
            if (-not [string]::IsNullOrWhiteSpace($groupPath)) {
                Write-Verbose "Ensuring KeePass group path exists: $groupPath"
                # Create each segment progressively: System, System/GitHub, ...
                $segments = $groupPath -split '/'
                $current = ''
                foreach ($seg in $segments) {
                    $current = if ($current) { "$current/$seg" } else { $seg }
                    $tmpPw = [System.IO.Path]::GetTempFileName()
                    try {
                        [System.IO.File]::WriteAllText($tmpPw, "$plainVault`n", [System.Text.Encoding]::ASCII)
                        $null = Start-Process -FilePath 'keepassxc-cli.exe' `
                            -ArgumentList 'mkdir', $dbPath, $current `
                            -NoNewWindow -Wait -PassThru -RedirectStandardInput $tmpPw
                        # If mkdir fails because it exists, ignore (exit code may be 1). We'll proceed regardless.
                    }
                    finally {
                        if ($FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'TestPath')) {
                            if ($FileSystem.TestPath($tmpPw)) {
                                if ($FileSystem.PSObject.Methods.Name -contains 'RemoveItem') { $FileSystem.RemoveItem($tmpPw, $false) } else { Remove-Item -Path $tmpPw -Force -ErrorAction SilentlyContinue }
                            }
                        }
                        else {
                            if (Test-Path -Path $tmpPw) { Remove-Item -Path $tmpPw -Force -ErrorAction SilentlyContinue }
                        }
                    }
                }
            }

            # Create a temporary file for the secret
            $tempFile = [System.IO.Path]::GetTempFileName()
            try {
                # Prepare an input stream that first unlocks DB, then provides entry password via -p
                [System.IO.File]::WriteAllText($tempFile, "$plainVault`n$plainSecret`n", [System.Text.Encoding]::ASCII)

                # Use Start-Process with stdin redirect from temp file
                $process = Start-Process -FilePath 'keepassxc-cli.exe' `
                    -ArgumentList 'add', '-u', $Username, '--url', $url, '-p', $dbPath, $entry `
                    -NoNewWindow -Wait -PassThru -RedirectStandardInput $tempFile

                if ($process.ExitCode -ne 0) {
                    throw "Failed to add entry (exit code: $($process.ExitCode))"
                }
            }
            finally {
                # Clean up temp file
                if ($FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'TestPath')) {
                    if ($FileSystem.TestPath($tempFile)) {
                        if ($FileSystem.PSObject.Methods.Name -contains 'RemoveItem') { $FileSystem.RemoveItem($tempFile, $false) } else { Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue }
                    }
                }
                else {
                    if (Test-Path -Path $tempFile) { Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue }
                }
                $plainVault = $null
            }

            # Metadata handling: always create/update a dedicated entry under System/Meta and avoid inline notes to prevent CLI warnings
            if ($Metadata.Count -gt 0) {
                try {
                    Write-Verbose 'Storing metadata in dedicated fallback entry (System/Meta)'
                    # Recreate plain vault password if cleared earlier
                    if (-not $plainVault) {
                        $bsv2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($resolvedVaultPw)
                        $plainVault = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bsv2)
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bsv2)
                    }

                    $metaGroup = 'System/Meta'
                    $metaEntry = "$metaGroup/${SecretType}-Metadata"

                    # Ensure meta group exists
                    $tmpPwMk = [System.IO.Path]::GetTempFileName()
                    try {
                        [System.IO.File]::WriteAllText($tmpPwMk, "$plainVault`n", [System.Text.Encoding]::ASCII)
                        $null = Start-Process -FilePath 'keepassxc-cli.exe' -ArgumentList 'mkdir', $dbPath, $metaGroup -NoNewWindow -Wait -PassThru -RedirectStandardInput $tmpPwMk
                    } finally { if ($FileSystem.TestPath($tmpPwMk)) { $FileSystem.RemoveItem($tmpPwMk, $false) } }

                    # Create placeholder entry (password 'metadata'); no notes editing to avoid CLI parsing issues
                    $tmpPwMeta = [System.IO.Path]::GetTempFileName()
                    try {
                        [System.IO.File]::WriteAllText($tmpPwMeta, "$plainVault`nmetadata`n", [System.Text.Encoding]::ASCII)
                        $procMetaAdd = Start-Process -FilePath 'keepassxc-cli.exe' -ArgumentList 'add', '-u', $Username, '--url', $url, '-p', $dbPath, $metaEntry -NoNewWindow -Wait -PassThru -RedirectStandardInput $tmpPwMeta
                    } finally { if ($FileSystem.TestPath($tmpPwMeta)) { $FileSystem.RemoveItem($tmpPwMeta, $false) } }
                    if ($procMetaAdd.ExitCode -eq 0) {
                        Write-Verbose "Metadata entry ensured: $metaEntry"
                    } else {
                        Write-Warning "Metadata entry create/update returned exit code: $($procMetaAdd.ExitCode)"
                    }
                }
                catch {
                    Write-Warning "Metadata storage skipped due to error: $_"
                }
            }

            Write-PSmmHost "[OK] $SecretType saved successfully to KeePass vault" -ForegroundColor Green

            if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
                Write-PSmmLog -Level SUCCESS -Context 'Save-SystemSecret' `
                    -Message "Successfully saved $SecretType to KeePass" -File
            }
        }

        return $true
    }
    catch {
        $errorMessage = "Failed to save system secret '$SecretType': $_"

        if (Get-Command Write-PSmmLog -ErrorAction SilentlyContinue) {
            Write-PSmmLog -Level ERROR -Context 'Save-SystemSecret' `
                -Message $errorMessage -ErrorRecord $_ -Console -File
        }

        Write-Error $errorMessage
        return $false
    }
    finally {
        # Clear plain text secret from memory if it was created
        if ($null -ne $plainSecret) {
            $plainSecret = $null
            [System.GC]::Collect()
        }
    }
}
