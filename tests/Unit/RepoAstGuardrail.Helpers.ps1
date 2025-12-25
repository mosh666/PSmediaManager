 #Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Get-RepoRootFromTestRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TestRoot
    )

    return (Split-Path -Path $TestRoot -Parent | Split-Path -Parent)
}

function Get-RepoPowerShellFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot
    )

    return @(
        Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1'
    )
}

function Get-ParsedAstOrThrow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)

    $blockingErrors = @()
    if ($parseErrors) {
        $blockingErrors = @($parseErrors | Where-Object { $_.ErrorId -ne 'TypeNotFound' })
    }

    if ($blockingErrors.Count -gt 0) {
        throw "Parser errors in ${Path}: $($blockingErrors[0].Message)"
    }

    return $ast
}

function Get-CommandAsts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast] $Ast
    )

    return @(
        $Ast.FindAll({
                param($n)
                ($n -is [System.Management.Automation.Language.CommandAst])
            }, $true)
    )
}

function Get-PipelineAsts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast] $Ast
    )

    return @(
        $Ast.FindAll({
                param($n)
                ($n -is [System.Management.Automation.Language.PipelineAst])
            }, $true)
    )
}
