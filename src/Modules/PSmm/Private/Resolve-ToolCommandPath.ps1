#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Resolve-ToolCommandPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary]$Paths,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CommandName,

        [Parameter()]
        [string]$DefaultCommand,

        [Parameter()]
        $Process
    )

    $commands = Get-OrInitializeToolCommandCache -Paths $Paths
    if ($commands.ContainsKey($CommandName)) {
        return $commands[$CommandName]
    }

    $resolved = Resolve-ToolCommandCandidate -Candidate $CommandName -Paths $Paths -Process $Process

    if (-not $resolved -and -not [string]::IsNullOrWhiteSpace($DefaultCommand)) {
        $resolved = Resolve-ToolCommandCandidate -Candidate $DefaultCommand -Paths $Paths -Process $Process
    }

    if (-not $resolved) {
        throw "Unable to resolve tool command '$CommandName'. Ensure it exists on PATH or provide an absolute path."
    }

    $commands[$CommandName] = $resolved
    return $resolved
}

function Get-OrInitializeToolCommandCache {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Paths
    )

    $commands = $null
    if ($Paths.Contains('Commands')) {
        $commands = $Paths['Commands']
    }

    if (-not ($commands -is [hashtable])) {
        $commands = @{}
        $Paths['Commands'] = $commands
    }

    return $commands
}

function Resolve-ToolCommandCandidate {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Paths,
        $Process
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($Candidate)) {
        if (Test-Path -Path $Candidate -PathType Leaf) {
            return (Resolve-Path -Path $Candidate -ErrorAction Stop).Path
        }
        return $null
    }

    if (Test-ToolProcessCommand -Process $Process -CommandName $Candidate) {
        $cmd = Get-Command -Name $Candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) {
            foreach ($property in 'Source','Path','Definition') {
                if ($cmd.PSObject.Properties.Match($property).Count -gt 0) {
                    $value = $cmd.$property
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        return $value
                    }
                }
            }
        }
    }

    return Find-ToolCommandInRoot -Paths $Paths -CommandName $Candidate
}

function Test-ToolProcessCommand {
    param(
        $Process,
        [Parameter(Mandatory)][string]$CommandName
    )

    if (-not $Process) {
        return $true
    }

    $testMethod = $Process.PSObject.Methods | Where-Object { $_.Name -eq 'TestCommand' }
    if (-not $testMethod) {
        return $true
    }

    try {
        return [bool]$Process.TestCommand.Invoke($CommandName)
    }
    catch {
        return $false
    }
}

function Find-ToolCommandInRoot {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Paths,
        [Parameter(Mandatory)][string]$CommandName
    )

    if (-not ($Paths.Contains('Root') -and -not [string]::IsNullOrWhiteSpace($Paths['Root']))) {
        return $null
    }

    $rootPath = $Paths['Root']
    if (-not (Test-Path -Path $rootPath -PathType Container)) {
        return $null
    }

    $targetName = if ([System.IO.Path]::GetExtension($CommandName)) {
        [System.IO.Path]::GetFileName($CommandName)
    }
    else {
        "$CommandName.exe"
    }

    $candidate = Get-ChildItem -LiteralPath $rootPath -Filter $targetName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) {
        return $candidate.FullName
    }

    return $null
}
