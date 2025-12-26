#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Import-PSmmModuleOrFatal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FatalErrorUi,

        [Parameter()]
        [bool]$NonInteractive = $false
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        Invoke-PSmmFatal -Context 'ModuleImport' -Message "Module manifest not found: $ManifestPath" -ExitCode 1 -NonInteractive:$NonInteractive -FatalErrorUi $FatalErrorUi
        return
    }

    try {
        Import-Module -Name $ManifestPath -Force -Global -ErrorAction Stop -Verbose:($VerbosePreference -eq 'Continue')
    }
    catch {
        Invoke-PSmmFatal -Context 'ModuleImport' -Message "Failed to import module '$ModuleName'" -ErrorObject $_ -ExitCode 1 -NonInteractive:$NonInteractive -FatalErrorUi $FatalErrorUi
    }
}
