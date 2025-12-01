# Test helper: stub Write-PSmmLog for tests
# Dot-source this file in tests BeforeAll to enable a lightweight global stub.

# Usage:
#   . $PSScriptRoot/Stub-WritePSmmLog.ps1
#   Enable-TestWritePSmmLogStub
#   ... run code that calls Write-PSmmLog ...
#   $entries = Get-TestWritePSmmLogEntries
#   Clear-TestWritePSmmLogEntries
#   Disable-TestWritePSmmLogStub

function Enable-TestWritePSmmLogStub {
    [CmdletBinding()]
    param()

    $existing = Get-Variable -Name TestWritePSmmLog_Enabled -Scope Global -ErrorAction SilentlyContinue
    if ($existing -and $existing.Value) { return }

    Set-Variable -Name TestWritePSmmLog_Entries -Scope Global -Value @()
    Set-Variable -Name TestWritePSmmLog_Enabled -Scope Global -Value $true

    # Define a global function that records calls. Use ScriptBlock to avoid dot-sourcing issues.
    $sb = {
        param(
            [Parameter(Mandatory)][string]$Level,
            [Parameter(Mandatory)][string]$Message,
            [string]$Body,
            [System.Management.Automation.ErrorRecord]$ErrorRecord,
            [string]$Context,
            [switch]$Console,
            [switch]$File
        )
        $entry = [PSCustomObject]@{
            Timestamp = Get-Date
            Level = $Level
            Message = $Message
            Body = $Body
            ErrorRecord = $ErrorRecord
            Context = $Context
            Console = $Console
            File = $File
        }
        if (-not $Global:TestWritePSmmLog_Entries) { $Global:TestWritePSmmLog_Entries = @() }
        $Global:TestWritePSmmLog_Entries += $entry
    }

    # If a real Write-PSmmLog function already exists, preserve it so we can restore later
    $existingCmd = Get-Command -Name Write-PSmmLog -CommandType Function -ErrorAction SilentlyContinue
    if ($existingCmd) {
        Set-Variable -Name TestWritePSmmLog_Original -Scope Global -Value $existingCmd.ScriptBlock
    }

    Set-Item -Path Function:\Write-PSmmLog -Value $sb -Force
}

function Disable-TestWritePSmmLogStub {
    [CmdletBinding()]
    param()

    $existing = Get-Variable -Name TestWritePSmmLog_Enabled -Scope Global -ErrorAction SilentlyContinue
    if (-not $existing -or -not $existing.Value) { return }

    # If there was an original function, restore it; otherwise remove the stub
    $origVar = Get-Variable -Name TestWritePSmmLog_Original -Scope Global -ErrorAction SilentlyContinue
    if ($origVar -and $origVar.Value) {
        Set-Item -Path Function:\Write-PSmmLog -Value $origVar.Value -Force
        Remove-Variable -Name TestWritePSmmLog_Original -Scope Global -ErrorAction SilentlyContinue
    }
    else {
        Remove-Item -Path Function:\Write-PSmmLog -ErrorAction SilentlyContinue
    }

    Remove-Variable -Name TestWritePSmmLog_Entries -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name TestWritePSmmLog_Enabled -Scope Global -ErrorAction SilentlyContinue
}

function Get-TestWritePSmmLogEntries {
    [CmdletBinding()]
    param()
    if ($null -eq $Global:TestWritePSmmLog_Entries) { return @() }
    return $Global:TestWritePSmmLog_Entries
}

function Clear-TestWritePSmmLogEntries {
    [CmdletBinding()]
    param()
    $Global:TestWritePSmmLog_Entries = @()
}

# Convenience import helper: call this from tests after dot-sourcing this file or
# simply dot-source this file and then call `Import-TestWritePSmmLogStub -RepositoryRoot $repoRoot`.
function Import-TestWritePSmmLogStub {
    [CmdletBinding()]
    param(
        [string]$RepositoryRoot
    )

    # Enable the stub (idempotent)
    Enable-TestWritePSmmLogStub
}
