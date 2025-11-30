#Requires -Version 7.5.4

<#!
.SYNOPSIS
    Ensures a WSL distribution is running and executes the Codacy CLI inside it.
.DESCRIPTION
    This helper warms up the requested (or default) WSL distribution, converts the
    repository path to its /mnt/<drive> form, normalizes the Codacy CLI script to
    LF line endings, and finally launches `.codacy/cli.sh` with the supplied
    arguments. It automatically stops if WSL is unavailable or if the CLI exits
    with a non-zero code.
.PARAMETER Distribution
    Optional WSL distribution name (as shown by `wsl.exe -l`). When omitted the
    default distribution is used.
.PARAMETER RepositoryPath
    Windows path to the repository root. Defaults to the parent directory of
    this script (.codacy/..).
.PARAMETER CliArguments
    Arguments to forward to `.codacy/cli.sh`. Defaults to running `analyze`
    against the current working directory using `.codacy/codacy.yaml`.
.PARAMETER WarmupOnly
    When set, the script merely ensures WSL is running without invoking Codacy.
.PARAMETER SkipNormalization
    Skips the line-ending normalization and chmod steps if WSL already has an
    executable CLI wrapper.
.EXAMPLE
    pwsh -File .codacy/Invoke-CodacyWSL.ps1 -Verbose
#>

param(
    [string]$Distribution,
    [string]$RepositoryPath,
    [string[]]$CliArguments = @('analyze'),
    [switch]$WarmupOnly,
    [switch]$SkipNormalization,
    [string]$OutputFormat,
    [string]$OutputFile,
    [string]$SemgrepArgs,
    [switch]$EnableTrivySecrets,
    [string]$TrivyArgs
)

Set-StrictMode -Version Latest

if (-not $RepositoryPath) {
    $RepositoryPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
}

$RepositoryPath = (Resolve-Path -Path $RepositoryPath).ProviderPath
$cliPath = Join-Path -Path $RepositoryPath -ChildPath ".codacy\cli.sh"

if (-not (Get-Command -Name wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl.exe is not available. Please enable the Windows Subsystem for Linux optional feature."
}

if (-not (Test-Path -Path $cliPath -PathType Leaf)) {
    throw "Codacy CLI wrapper not found at $cliPath"
}

# Resolve a friendly distribution name for diagnostics
$resolvedDistributionName = $Distribution
if (-not $resolvedDistributionName) {
    try {
        $listVerbose = & wsl.exe --list --verbose 2>$null
        if ($LASTEXITCODE -eq 0 -and $listVerbose) {
            # Look for the line starting with '*'
            $defaultLine = ($listVerbose -split "`r?`n") | Where-Object { $_.TrimStart().StartsWith('*') } | Select-Object -First 1
            if ($defaultLine) {
                # Format: "* Ubuntu-22.04           Running         2"
                $resolvedDistributionName = ($defaultLine.TrimStart('*').Trim() -split '\s+')[0]
            }
        }
        if (-not $resolvedDistributionName) {
            $list = & wsl.exe --list 2>$null
            if ($LASTEXITCODE -eq 0 -and $list) {
                # Older format marks default with "(Default)"
                $defaultLine = ($list -split "`r?`n") | Where-Object { $_ -match '\(Default\)' } | Select-Object -First 1
                if ($defaultLine) {
                    $resolvedDistributionName = ($defaultLine -replace '\s*\(Default\)\s*','').Trim()
                }
            }
        }
    }
    catch { }
}
if (-not $resolvedDistributionName) { $resolvedDistributionName = '(default)' }
Write-Verbose "Using WSL distribution: $resolvedDistributionName"

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [string]$Distribution
    )

    $arguments = @()
    if ($Distribution) {
        $arguments += @('-d', $Distribution)
    }

    $arguments += @('--', 'bash', '-lc', $Command)

    Write-Verbose "wsl.exe $($arguments -join ' ')"
    & wsl.exe @arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "WSL command failed with exit code $exitCode"
    }
}

function Assert-WslDistribution {
    $output = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $output) {
        throw "No WSL distributions are registered. Install a distribution with `wsl --install`."
    }

    if ($Distribution -and ($output -split "`n") -notcontains $Distribution) {
        throw "WSL distribution '$Distribution' was not found. Registered distributions: $output"
    }
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -Path $Path).ProviderPath
    if ($resolved -notmatch '^[A-Za-z]:\\') {
        throw "Only Windows-style paths can be converted to WSL mount points."
    }

    $drive = $resolved.Substring(0, 1).ToLowerInvariant()
    $relative = ($resolved.Substring(2) -replace '\\', '/').TrimStart('/')
    return "/mnt/$drive/$relative"
}

function ConvertTo-BashLiteral {
    param([Parameter(Mandatory)][string]$Value)
    $escaped = $Value -replace "'", "'""'""'"
    return "'$escaped'"
}

Assert-WslDistribution
Write-Verbose "WSL distribution check passed."

Invoke-WslCommand -Command "true" -Distribution $Distribution
Write-Verbose "WSL warmup completed."

if ($WarmupOnly) {
    Write-Verbose "Warmup-only flag set. Exiting after ensuring WSL is running."
    return
}

$wslRepoPath = ConvertTo-WslPath -Path $RepositoryPath
$escapedRepo = ConvertTo-BashLiteral -Value $wslRepoPath
$commandParts = @("cd $escapedRepo")
$commandParts += @('export CODACY_CONFIGURATION=.codacy/codacy.yaml')

# Export selection into WSL env for diagnostics
## No explicit export of distro name into WSL to avoid quoting pitfalls

if (-not $SkipNormalization) {
    $commandParts += @("sed -i 's/\r$//' ./.codacy/cli.sh", "chmod +x ./.codacy/cli.sh")
}

if (-not $CliArguments -or $CliArguments.Count -eq 0) {
    throw "CliArguments cannot be empty unless -WarmupOnly is specified."
}

# Emit WSL-side diagnostics in verbose mode to help identify missing tools
$isVerbose = ($PSBoundParameters.ContainsKey('Verbose') -or $VerbosePreference -eq 'Continue')
if ($isVerbose) {
    $commandParts += @(
        'DISTRO_NAME=$(( . /etc/os-release 2>/dev/null; echo "$PRETTY_NAME" ) || uname -a); printf "[WSL] Distribution: %s\\n" "$DISTRO_NAME"',
        'printf "[WSL] PATH=%s\\n" "$PATH"',
        'printf "[WSL] Tool availability:\\n"',
        'command -v docker >/dev/null 2>&1 && docker --version || echo "docker: not found"',
        'command -v trivy >/dev/null 2>&1 && trivy --version || echo "trivy: not found"',
        'command -v semgrep >/dev/null 2>&1 && semgrep --version || echo "semgrep: not found"',
        'command -v java >/dev/null 2>&1 && java -version || echo "java: not found"',
        'command -v python3 >/dev/null 2>&1 && python3 --version || echo "python3: not found"',
        'command -v sed >/dev/null 2>&1 && sed --version | head -n1 || echo "sed: not found"',
        'command -v curl >/dev/null 2>&1 && curl --version | head -n1 || echo "curl: not found"',
        'command -v wget >/dev/null 2>&1 && wget --version | head -n1 || echo "wget: not found"',
        'command -v tar >/dev/null 2>&1 && tar --version | head -n1 || echo "tar: not found"'
    )
}

# Handle optional output capture parameters
if ($OutputFile) {
    # Create parent directory if it does not exist (Windows side before WSL execution)
    $resolvedOutput = $OutputFile
    if (-not [System.IO.Path]::IsPathRooted($resolvedOutput)) {
        $resolvedOutput = Join-Path -Path $RepositoryPath -ChildPath $resolvedOutput
    }
    $outDir = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -Path $outDir -ItemType Directory -Force | Out-Null
    }
}

$argLine = ($CliArguments -join ' ')
# Append Trivy-specific options when requested
if ($argLine -match '(?i)--tool\s+trivy') {
    if ($EnableTrivySecrets) {
        $argLine += ' --scanners secret'
    }
    if ($TrivyArgs) {
        $argLine += " $TrivyArgs"
    }
}
if ($OutputFormat) {
    $argLine += " --format $OutputFormat"
}
if ($OutputFile) {
    $outputForCli = $OutputFile
    if ($OutputFile -match '^[A-Za-z]:\\') {
        $outputForCli = ConvertTo-WslPath -Path $OutputFile
    }
    $argLine += " --output $outputForCli"
}

# If Dockerfile exists and we're performing an analyze, schedule image scan AFTER Codacy CLI
$dockerfilePath = Join-Path -Path $RepositoryPath -ChildPath 'Dockerfile'
$shouldImageScan = (Test-Path -LiteralPath $dockerfilePath) -and ($CliArguments -contains 'analyze') -and ($argLine -notmatch '(?i)--image')

# Tool-specific passthrough: allow Semgrep verbosity/output when running only Semgrep
# Detect Semgrep-only execution and bypass codacy-cli to allow tool-specific flags
$isSemgrepOnly = ($CliArguments -join ' ') -match "(?i)-t\s+semgrep"
if ($isSemgrepOnly) {
    # Build Semgrep command
    $semgrepCmd = "semgrep --config .semgrep.yml"
    if ($SemgrepArgs) {
        $semgrepCmd += " $SemgrepArgs"
    }
    if ($OutputFormat) {
        switch ($OutputFormat.ToLowerInvariant()) {
            'sarif' { $semgrepCmd += ' --sarif' }
            'json'  { $semgrepCmd += ' --json' }
            default { }
        }
    }
    if ($OutputFile) {
        $outForSemgrep = $OutputFile
        if ($OutputFile -match '^[A-Za-z]:\\') {
            $outForSemgrep = ConvertTo-WslPath -Path $OutputFile
        }
        $semgrepCmd += " --output $outForSemgrep"
    }
    $commandParts += $semgrepCmd
} else {
    # Tool-specific passthrough: allow Trivy direct execution for secrets scanning
    $isTrivyOnly = ($CliArguments -join ' ') -match "(?i)-t\s+trivy"
    if ($isTrivyOnly) {
        # Default to filesystem scan at repo root
        $trivyCmd = "trivy fs"
        # Prefer new flag; fall back to deprecated if needed
        $trivyCmd += " --scanners secret"

        # Map output format if provided
        if ($OutputFormat) {
            switch ($OutputFormat.ToLowerInvariant()) {
                'sarif' { $trivyCmd += ' --format sarif' }
                'json'  { $trivyCmd += ' --format json' }
                default { }
            }
        }

        # Map output file, convert Windows path to WSL if necessary
        if ($OutputFile) {
            $outForTrivy = $OutputFile
            if ($OutputFile -match '^[A-Za-z]:\\') {
                $outForTrivy = ConvertTo-WslPath -Path $OutputFile
            }
            $trivyCmd += " --output $outForTrivy"
        }

        # Append any extra Trivy args provided by caller
        if ($TrivyArgs) {
            $trivyCmd += " $TrivyArgs"
        }

        # Target current repo directory
        $trivyCmd += " ."

        $commandParts += $trivyCmd
    } else {
    # Default path: run codacy cli wrapper
    $commandParts += "./.codacy/cli.sh $argLine"
    }
}

# Append optional Docker image build + Trivy image scan AFTER the CLI, guarded by tool presence
if ($shouldImageScan -and -not $isSemgrepOnly -and -not $isTrivyOnly) {
    Write-Verbose 'Dockerfile detected; scheduling image build and Trivy scan after Codacy CLI.'
    $dockerGuard = @(
        'if command -v docker >/dev/null 2>&1; then',
        '  printf "[WSL] Docker available; building psmediamanager:scan image\\n";',
        '  docker build -t psmediamanager:scan . &&',
        '  if command -v trivy >/dev/null 2>&1; then',
        '    printf "[WSL] Running Trivy image scan\\n";',
        '    trivy image psmediamanager:scan || true;',
        '  else',
        '    printf "[WSL] Skipping Trivy image scan: trivy not found\\n";',
        '  fi;',
        'else',
        '  printf "[WSL] Skipping Docker image build: docker not found\\n";',
        'fi'
    ) -join ' '
    $commandParts += $dockerGuard
}

$finalCommand = $commandParts -join ' && '
Write-Verbose ("WSL command: " + $finalCommand)
Invoke-WslCommand -Command $finalCommand -Distribution $Distribution
Write-Verbose "Codacy CLI completed successfully."
