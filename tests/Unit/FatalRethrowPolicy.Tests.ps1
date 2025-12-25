#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Fatal rethrow policy' {

    BeforeAll {
        . "$PSScriptRoot\RepoAstGuardrail.Helpers.ps1"

        function script:Assert-CatchRethrowsPSmmFatalExceptionBeforeInvoke {
            param(
                [Parameter(Mandatory)][System.Management.Automation.Language.CatchClauseAst]$Catch,
                [Parameter(Mandatory)][string]$FilePath
            )

            $invokeFatal = @(Get-CommandAsts -Ast $Catch.Body | Where-Object { $_.GetCommandName() -eq 'Invoke-PSmmFatal' })
            if ($invokeFatal.Count -eq 0) {
                return
            }

            $ifNodes = @($Catch.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true))
            $hasRethrowGuard = $false
            $firstInvokeStart = ($invokeFatal | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1).Extent.StartOffset

            foreach ($ifNode in $ifNodes) {
                if ($ifNode.Extent.StartOffset -ge $firstInvokeStart) {
                    continue
                }

                $text = $ifNode.Extent.Text
                if ($text -match '\[PSmmFatalException\]' -and $text -match '\bthrow\b') {
                    $hasRethrowGuard = $true
                    break
                }
            }

            if (-not $hasRethrowGuard) {
                throw "${FilePath}: catch block invokes Invoke-PSmmFatal without rethrowing PSmmFatalException first."
            }
        }
    }

    It 'PSmediaManager catch blocks rethrow PSmmFatalException before invoking fatal' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $filePath = Join-Path -Path $repoRoot -ChildPath 'src/PSmediaManager.ps1'
        $ast = Get-ParsedAstOrThrow -Path $filePath

        $catchClauses = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CatchClauseAst] }, $true)
        foreach ($c in $catchClauses) {
            Assert-CatchRethrowsPSmmFatalExceptionBeforeInvoke -Catch $c -FilePath $filePath
        }
    }

    It 'Invoke-PSmm outer catch rethrows PSmmFatalException' {
        $repoRoot = Get-RepoRootFromTestRoot -TestRoot $PSScriptRoot
        $filePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/PSmm/Public/Bootstrap/Invoke-PSmm.ps1'
        $ast = Get-ParsedAstOrThrow -Path $filePath

        $catchClauses = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CatchClauseAst] }, $true)
        $found = $false
        foreach ($c in $catchClauses) {
            $text = $c.Body.Extent.Text
            if ($text -match '\[PSmmFatalException\]' -and $text -match '\bthrow\b') {
                $found = $true
                break
            }
        }

        if (-not $found) {
            throw "${filePath}: expected a catch clause that rethrows PSmmFatalException."
        }
    }
}
