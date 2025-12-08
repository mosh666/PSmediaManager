Set-StrictMode -Version Latest

function Register-GlobalFilesystemGuards {
    [CmdletBinding()]
    param()

        # Ensure TestDrive is available; if not, skip registration to avoid container discovery failures
        $testDriveVar = Get-Variable -Name TestDrive -Scope Global -ErrorAction SilentlyContinue
        if (-not $testDriveVar) { return }

        $safeRoot = Join-Path -Path $TestDrive -ChildPath 'PSmmSandbox'
    if (-not (Test-Path -Path $safeRoot)) { $null = New-Item -Path $safeRoot -ItemType Directory -Force }

    $redirect = {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
        if ($Path -match '^(?i)c:\\psmm(\.|$)') {
            $leaf = Split-Path -Path $Path -Leaf
            return (Join-Path -Path $safeRoot -ChildPath $leaf)
        }
        return $Path
    }

    Mock -CommandName New-Item -MockWith {
        param([string]$Path,[string]$ItemType)
        $target = & $redirect $Path
        Microsoft.PowerShell.Management\New-Item -Path $target -ItemType $ItemType -Force
    } -Verifiable:$false -ParameterFilter { $Path -match '^(?i)c:\\psmm(\.|$)' }

    Mock -CommandName Set-Content -MockWith {
        param([string]$Path,$Value)
        $target = & $redirect $Path
        Microsoft.PowerShell.Management\Set-Content -Path $target -Value $Value -Force
    } -Verifiable:$false -ParameterFilter { $Path -match '^(?i)c:\\psmm(\.|$)' }

    Mock -CommandName Copy-Item -MockWith {
        param([string]$Path,[string]$Destination)
        $dest = & $redirect $Destination
        Microsoft.PowerShell.Management\Copy-Item -Path $Path -Destination $dest -Force
    } -Verifiable:$false -ParameterFilter { $Destination -match '^(?i)c:\\psmm(\.|$)' }

    return $safeRoot
}
