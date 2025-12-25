#Requires -Version 7.5.4
Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent

    function script:Write-PSmmHost { param([Parameter(ValueFromRemainingArguments = $true)]$Args) }
    function script:Write-PSmmLog { param([Parameter(ValueFromRemainingArguments = $true)]$Args) }
    function script:Confirm-Storage { param([Parameter(ValueFromRemainingArguments = $true)]$Args) }
    function script:Show-Header { param([Parameter(ValueFromRemainingArguments = $true)]$Args) }

    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Classes/Exceptions.ps1')

    # PSmm public helpers we want to validate
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Public/Invoke-PSmmFatal.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Public/Import-PSmmModuleOrFatal.ps1')

    # UI config helper + UI entrypoint
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.UI/Private/ConfigMemberAccessHelpers.ps1')
    . (Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm.UI/Public/Invoke-PSmmUI.ps1')
}

class CountingFatal {
    [int]$Count = 0

    [void] InvokeFatal([string]$Context, [string]$Message, [object]$Error, [int]$ExitCode, [bool]$NonInteractive) {
        $this.Count++
        $fatalType = 'PSmmFatalException' -as [type]
        if ($null -eq $fatalType) {
            throw "Unable to resolve PSmmFatalException type; ensure Exceptions.ps1 is loaded."
        }
        throw ($fatalType::new($Message, $Context, $ExitCode, $NonInteractive))
    }
}

class TestServiceContainer {
    [object]$Fatal
    [object]$Process
    [object]$FileSystem
    [object]$PathProvider

    TestServiceContainer([object]$fatal) {
        $this.Fatal = $fatal
        $this.Process = [pscustomobject]@{}
        $this.FileSystem = [pscustomobject]@{}
        $this.PathProvider = [pscustomobject]@{}
    }

    [object] Resolve([string]$name) {
        if ($name -eq 'FatalErrorUi') {
            return $this.Fatal
        }
        if ($name -eq 'Process') { return $this.Process }
        if ($name -eq 'FileSystem') { return $this.FileSystem }
        if ($name -eq 'PathProvider') { return $this.PathProvider }
        throw "Service '$name' is not registered."
    }
}

# Minimal config type required by Invoke-PSmmUI (tests intentionally avoid loading full PSmm class graph)
class AppConfiguration {
    [hashtable]$Parameters
    [hashtable]$Storage

    AppConfiguration() {
        $this.Parameters = @{ Debug = $false; Dev = $false }
        $this.Storage = @{ Group1 = @{} }
    }
}

Describe 'Fatal invocation semantics' {
    It 'Calls fatal exactly once for missing module manifest' {
        $fatal = [CountingFatal]::new()

        try {
            Import-PSmmModuleOrFatal -ModuleName 'DoesNotExist' -ManifestPath 'Z:\nope\missing.psd1' -FatalErrorUi $fatal -NonInteractive:$true
            throw 'Expected fatal exception'
        }
        catch {
            $fatal.Count | Should -Be 1
        }
    }
}
