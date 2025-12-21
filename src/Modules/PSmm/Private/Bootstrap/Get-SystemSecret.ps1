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

# Note: $script:_VaultMasterPasswordCache is declared in Initialize-SystemVault.ps1
# Both files are dot-sourced into PSmm module and share the same module scope.

function Get-KeePassCliCandidatePaths {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Returns multiple candidate paths; plural noun is intentional')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$VaultPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Environment,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $PathProvider
    )

    $paths = [System.Collections.Generic.List[string]]::new()

    $programRoots = @()
    $progFiles = $Environment.GetVariable('ProgramFiles')
    if ($progFiles) { $programRoots += $progFiles }
    $progFilesX86 = $Environment.GetVariable('ProgramFiles(x86)')
    if ($progFilesX86) { $programRoots += $progFilesX86 }
    $localAppData = $Environment.GetVariable('LOCALAPPDATA')
    if ($localAppData) { $programRoots += $PathProvider.CombinePath(@($localAppData, 'Programs')) }

    foreach ($root in $programRoots | Select-Object -Unique) {
        $candidate = $PathProvider.CombinePath(@($root, 'KeePassXC'))
        if ($candidate -and $FileSystem.TestPath($candidate)) {
            $paths.Add((Resolve-Path -LiteralPath $candidate).Path)
        }
    }

    $vaultRoot = Split-Path -Path $VaultPath -Parent
    $portableRootCandidates = @()
    if ($vaultRoot) {
        $portableRootCandidates += $PathProvider.CombinePath(@($vaultRoot, 'PSmm.Plugins'))
        $portableRootCandidates += $PathProvider.CombinePath(@($vaultRoot, 'Plugins'))
        $portableRootCandidates += $PathProvider.CombinePath(@($vaultRoot, 'PSmediaManager', 'Plugins'))
    }

    foreach ($portableRoot in ($portableRootCandidates | Select-Object -Unique)) {
        if (-not $FileSystem.TestPath($portableRoot)) {
            continue
        }

        try {
            $items = $FileSystem.GetChildItem($portableRoot, $null, 'Directory')
            $items | Where-Object { $_.Name -match 'KeePassXC' } |
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
        [string]$VaultPath,

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

    $result = [ordered]@{
        Command = $null
        CandidatePaths = @()
        ResolvedExecutable = $null
    }

    if ($Process.TestCommand('keepassxc-cli.exe')) {
        $result.Command = 'keepassxc-cli.exe'
        return [pscustomobject]$result
    }

    $candidatePaths = Get-KeePassCliCandidatePaths -VaultPath $VaultPath -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider
    $result.CandidatePaths = $candidatePaths

    if (-not $candidatePaths) {
        return [pscustomobject]$result
    }

    $exeCandidates = @()
    foreach ($base in $candidatePaths) {
        try {
            $items = $FileSystem.GetChildItem($base, 'keepassxc-cli.exe', $null)
            if ($items) {
                $exeCandidates += $items | Select-Object -ExpandProperty FullName
            }
        }
        catch {
            Write-Verbose "Failed to inspect KeePassXC path $base : $_"
        }
    }

    $resolvedCli = $exeCandidates | Sort-Object -Unique | Select-Object -First 1
    if ($resolvedCli) {
        $resolvedDir = Split-Path -Parent $resolvedCli
        Write-Verbose "Resolved keepassxc-cli.exe at: $resolvedCli"
        $currentPath = $Environment.GetVariable('PATH')
        if ($currentPath -notlike "*${resolvedDir}*") {
            $Environment.AddPathEntry($resolvedDir, $false)
            Write-Verbose 'Added KeePassXC directory to PATH for current session.'

            # Track in config if available (for centralized cleanup)
            if (Get-Command -Name Get-AppConfiguration -ErrorAction SilentlyContinue) {
                try {
                    $config = Get-AppConfiguration
                    if ($config -and $config.PSObject.Properties.Name -contains 'AddedPathEntries') {
                        $existingEntries = $null
                        try { $existingEntries = $config.PSObject.Properties['AddedPathEntries'].Value } catch { $existingEntries = $null }

                        $pathEntries = [System.Collections.ArrayList]::new()
                        if ($null -ne $existingEntries) {
                            if ($existingEntries -is [string]) {
                                $null = $pathEntries.Add($existingEntries)
                            }
                            else {
                                foreach ($entry in @($existingEntries)) {
                                    if ($null -ne $entry) { $null = $pathEntries.Add($entry) }
                                }
                            }
                        }

                        if ($pathEntries -notcontains $resolvedDir) {
                            $null = $pathEntries.Add($resolvedDir)
                            $config.AddedPathEntries = $pathEntries.ToArray()
                            Write-Verbose "Tracked KeePassXC PATH entry for cleanup: $resolvedDir"
                        }
                    }
                }
                catch {
                    Write-Verbose "Could not track PATH entry in config: $_"
                }
            }
        }
        $result.ResolvedExecutable = $resolvedCli
        if ($Process.TestCommand('keepassxc-cli.exe')) {
            $result.Command = 'keepassxc-cli.exe'
        }
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

function Get-ConfigMemberValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary]) {
        try { if ($Object.ContainsKey($Name)) { return $Object[$Name] } } catch { Write-Verbose "Get-ConfigMemberValue: IDictionary.ContainsKey('$Name') failed: $($_.Exception.Message)" }
        try { if ($Object.Contains($Name)) { return $Object[$Name] } } catch { Write-Verbose "Get-ConfigMemberValue: IDictionary.Contains('$Name') failed: $($_.Exception.Message)" }
        try {
            foreach ($k in $Object.Keys) {
                if ($k -eq $Name) { return $Object[$k] }
            }
        }
        catch { Write-Verbose "Get-ConfigMemberValue: IDictionary.Keys enumeration failed: $($_.Exception.Message)" }
        return $Default
    }

    $p = $Object.PSObject.Properties[$Name]
    if ($null -ne $p) {
        return $p.Value
    }

    return $Default
}

function Set-ConfigMemberValue {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        $Value
    )

    if ($null -eq $Object) {
        return
    }

    $target = try { "{0}.{1}" -f $Object.GetType().Name, $Name } catch { $Name }

    if ($Object -is [System.Collections.IDictionary]) {
        if (-not $PSCmdlet.ShouldProcess($target, 'Set config member value')) {
            return
        }
        $Object[$Name] = $Value
        return
    }

    $existing = $null
    try { $existing = $Object.PSObject.Properties[$Name] } catch { $existing = $null }
    if ($null -ne $existing) {
        try {
            if (-not $PSCmdlet.ShouldProcess($target, 'Set config member value')) {
                return
            }
            $Object.$Name = $Value
        } catch {
            Write-Verbose "Set-ConfigMemberValue: property set '$Name' failed: $($_.Exception.Message)"
        }
        return
    }

    try {
        if (-not $PSCmdlet.ShouldProcess($target, 'Add config member value')) {
            return
        }
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
    catch {
        Write-Verbose "Set-ConfigMemberValue: Add-Member '$Name' failed: $($_.Exception.Message)"
    }
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
        [ValidateNotNull()]
        $FileSystem,

        [Parameter()]
        [ValidateNotNull()]
        $Environment,

        [Parameter()]
        [ValidateNotNull()]
        $PathProvider,

        [Parameter()]
        [ValidateNotNull()]
        $Process,

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
                try {
                    $VaultPath = (Get-AppConfiguration).Paths.App.Vault
                }
                catch {
                    Write-Verbose "Could not retrieve vault path from app configuration: $_"
                }
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
        $dbPath = $PathProvider.CombinePath(@($VaultPath, 'PSmm_System.kdbx'))

        # Check if KeePass database exists
        if (-not $FileSystem.TestPath($dbPath)) {
            $errorMsg = "KeePass database not found: $dbPath. Use Initialize-SystemVault to create it."
            if ($Optional) {
                Write-PSmmLog -Level NOTICE -Context 'Get-SystemSecret' -Message $errorMsg -Console -File
                return $null
            }
            Write-PSmmLog -Level ERROR -Context 'Get-SystemSecret' -Message $errorMsg -Console -File
            throw $errorMsg
        }

        Write-Verbose "Retrieving from KeePassXC database: $dbPath"

        $cliResolution = Resolve-KeePassCliCommand -VaultPath $VaultPath -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process
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
            try {
                Write-PSmmHost "Enter vault master password (input hidden):" -ForegroundColor Yellow
                # Prompt user explicitly (KeePassXC would otherwise prompt without context)
                # Wrapped in try-catch to handle console mode initialization errors (e.g., Win32 0x57)
                $masterPw = Read-Host 'Vault Master Password' -AsSecureString -ErrorAction Stop
                # Offer to cache for this session
                $cacheAns = Read-Host 'Cache this master password for this session? [Y/n]' -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($cacheAns) -or $cacheAns.Trim().ToLower() -eq 'y') {
                    $script:_VaultMasterPasswordCache = $masterPw
                    Write-Verbose 'Vault master password cached for this session.'
                }
            }
            catch {
                $readHostError = $_
                $errorMsg = "Failed to read vault master password from console: $($readHostError.Message)"
                if ($Optional) {
                    Write-PSmmLog -Level NOTICE -Context 'Get-SystemSecret' -Message $errorMsg -Console -File
                    Write-Verbose "Skipping vault access because -Optional was specified and console input failed."
                    return $null
                }
                # If console is unavailable and secret is mandatory, throw the error
                throw "Cannot prompt for vault master password due to console mode error: $($readHostError.Message)"
            }
        }
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($masterPw)
        $plainMaster = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        $tmpPw = [System.IO.Path]::GetTempFileName()
        $tmpOut = [System.IO.Path]::GetTempFileName()
        $tmpErr = [System.IO.Path]::GetTempFileName()
        $proc = $null
        try {
            # Resolve KeePassXC CLI path and write master password to temp file for stdin redirection
            [System.IO.File]::WriteAllText($tmpPw, "$plainMaster`n", [System.Text.Encoding]::ASCII)

            # Use Start-Process so we can redirect stdin/stdout/stderr to files
            # Wrapped in try-catch to handle console mode or process execution errors
            $proc = Start-Process -FilePath $cli `
                -ArgumentList 'show','-s','-a','Password',$dbPath,$entry `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardInput $tmpPw `
                -RedirectStandardOutput $tmpOut `
                -RedirectStandardError $tmpErr `
                -ErrorAction Stop

            $secretValue = ''
            if ($proc.ExitCode -eq 0 -and $FileSystem.TestPath($tmpOut)) {
                $secretValue = ($FileSystem.GetContent($tmpOut)).Trim()
            }
            elseif ($proc.ExitCode -ne 0 -and $FileSystem.TestPath($tmpErr)) {
                # Log keepassxc-cli stderr for debugging
                $cliStderr = ($FileSystem.GetContent($tmpErr)).Trim()
                Write-Verbose "KeePassXC CLI stderr: $cliStderr"
            }
        }
        finally {
            try {
                if ($FileSystem -and ($FileSystem.PSObject.Methods.Name -contains 'TestPath')) {
                    if ($FileSystem.TestPath($tmpPw)) {
                        if ($FileSystem.PSObject.Methods.Name -contains 'RemoveItem') { $FileSystem.RemoveItem($tmpPw, $false) } else { Remove-Item -Path $tmpPw -Force -ErrorAction SilentlyContinue }
                    }
                    if ($FileSystem.TestPath($tmpOut)) {
                        if ($FileSystem.PSObject.Methods.Name -contains 'RemoveItem') { $FileSystem.RemoveItem($tmpOut, $false) } else { Remove-Item -Path $tmpOut -Force -ErrorAction SilentlyContinue }
                    }
                    if ($FileSystem.TestPath($tmpErr)) {
                        if ($FileSystem.PSObject.Methods.Name -contains 'RemoveItem') { $FileSystem.RemoveItem($tmpErr, $false) } else { Remove-Item -Path $tmpErr -Force -ErrorAction SilentlyContinue }
                    }
                }
                else {
                    if (Test-Path -Path $tmpPw)   { Remove-Item -Path $tmpPw   -Force -ErrorAction SilentlyContinue }
                    if (Test-Path -Path $tmpOut)  { Remove-Item -Path $tmpOut  -Force -ErrorAction SilentlyContinue }
                    if (Test-Path -Path $tmpErr)  { Remove-Item -Path $tmpErr  -Force -ErrorAction SilentlyContinue }
                }
            }
            finally { $plainMaster = $null }
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
        [string]$VaultPath = 'd:\_mediaManager_\Vault',

        [Parameter()]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter()]
        [ValidateNotNull()]
        $PathProvider,

        [Parameter()]
        [ValidateNotNull()]
        $Environment,

        [Parameter()]
        [ValidateNotNull()]
        $Process
    )

    try {
        $entryMap = @{
            'GitHub-Token' = 'System/GitHub/API-Token'
            'APIKey' = 'System/API/General'
            'Certificate' = 'System/Certificates/SSL'
        }

        $entry = $entryMap[$SecretType]
        $dbPath = $PathProvider.CombinePath(@($VaultPath, 'PSmm_System.kdbx'))

        if (-not $FileSystem.TestPath($dbPath)) {
            throw [ConfigurationException]::new("KeePass database not found", $dbPath)
        }

        if (-not $Process.TestCommand('keepassxc-cli.exe')) {
            # Attempt same auto-resolution strategy
            $pluginsRoot = (Split-Path -Parent $VaultPath)
            $portableDir = $PathProvider.CombinePath(@($pluginsRoot, 'Plugins'))
            if ($FileSystem.TestPath($portableDir)) {
                $items = $FileSystem.GetChildItem($portableDir, $null, 'Directory')
                $kpDir = $items | Where-Object { $_.Name -match 'KeePassXC' } | Select-Object -First 1
                if ($kpDir) {
                    $exeItems = $FileSystem.GetChildItem($kpDir.FullName, 'keepassxc-cli.exe', $null)
                    $exe = $exeItems | Select-Object -First 1
                    if ($exe) {
                        $dir = Split-Path -Parent $exe.FullName
                        $currentPath = $Environment.GetVariable('PATH')
                        if ($currentPath -notlike "*${dir}*") {
                            $Environment.AddPathEntry($dir, $false)

                            # Track in config if available (for centralized cleanup)
                            if (Get-Command -Name Get-AppConfiguration -ErrorAction SilentlyContinue) {
                                try {
                                    $config = Get-AppConfiguration
                                    if ($config) {
                                        $existingEntries = Get-ConfigMemberValue -Object $config -Name 'AddedPathEntries' -Default $null
                                        $pathEntries = [System.Collections.ArrayList]::new()
                                        foreach ($e in @($existingEntries)) {
                                            if ($null -ne $e -and -not [string]::IsNullOrWhiteSpace([string]$e)) {
                                                $null = $pathEntries.Add([string]$e)
                                            }
                                        }
                                        if ($pathEntries -notcontains $dir) {
                                            $null = $pathEntries.Add($dir)
                                            Set-ConfigMemberValue -Object $config -Name 'AddedPathEntries' -Value $pathEntries.ToArray()
                                        }
                                    }
                                }
                                catch {
                                    Write-Verbose "Could not track PATH entry in config: $_"
                                }
                            }
                        }
                    }
                }
            }
        }
        if (-not $Process.TestCommand('keepassxc-cli.exe')) {
            throw [PluginRequirementException]::new('keepassxc-cli.exe not found after auto-resolution attempt', 'KeePassXC')
        }

        if ($AttributeName) {
            # Get specific attribute
            $result = & keepassxc-cli.exe show -s -a "$AttributeName" "$dbPath" "$entry" 2>&1

            if ($LASTEXITCODE -eq 0) {
                return $result
            }
            else {
                $ex = [ProcessException]::new("Failed to retrieve attribute '$AttributeName'", "keepassxc-cli.exe")
                $ex.SetExitCode($LASTEXITCODE)
                throw $ex
            }
        }
        else {
            # List all attributes
            $result = & keepassxc-cli.exe show "$dbPath" "$entry" 2>&1

            if ($LASTEXITCODE -eq 0) {
                return $result
            }
            else {
                $ex = [ProcessException]::new("Failed to retrieve entry information", "keepassxc-cli.exe")
                $ex.SetExitCode($LASTEXITCODE)
                throw $ex
            }
        }
    }
    catch {
        Write-PSmmLog -Level ERROR -Context 'Get-SystemSecretMetadata' `
            -Message "Failed to retrieve metadata for '$SecretType': $_" -Console -File
        throw
    }
}
