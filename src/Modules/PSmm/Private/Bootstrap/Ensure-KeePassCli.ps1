#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Ensure-KeePassCliAvailability {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.CommandInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AppConfiguration]$Config,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Http,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Crypto,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $FileSystem,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Process
    )

    $resolution = Resolve-KeePassCliCommand -VaultPath $Config.Paths.App.Vault
    if ($resolution.Command) {
        return $resolution.Command
    }

    Write-PSmmLog -Level WARNING -Context 'Ensure-KeePassCli' `
        -Message 'keepassxc-cli.exe not found; attempting automatic KeePassXC installation (Option A)' -Console -File

    if (-not (Get-Command -Name Install-KeePassXC -ErrorAction SilentlyContinue)) {
        throw 'Install-KeePassXC is not available from PSmm.Plugins. Ensure the module is imported.'
    }

    $null = Install-KeePassXC -Config $Config -Http $Http -Crypto $Crypto -FileSystem $FileSystem -Process $Process

    $postResolution = Resolve-KeePassCliCommand -VaultPath $Config.Paths.App.Vault
    if (-not $postResolution.Command) {
        $searched = if ($postResolution.CandidatePaths) { $postResolution.CandidatePaths -join ', ' } else { 'No candidate directories discovered' }
        $message = "Automatic KeePassXC installation completed but keepassxc-cli.exe is still missing. Checked paths: $searched"
        Write-PSmmLog -Level ERROR -Context 'Ensure-KeePassCli' -Message $message -Console -File
        throw $message
    }

    Write-PSmmLog -Level SUCCESS -Context 'Ensure-KeePassCli' `
        -Message 'keepassxc-cli.exe available after automatic installation' -Console -File

    return $postResolution.Command
}
