#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Install-KeePassXC {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Config,

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
        $Environment,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $PathProvider,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Process
    )

    $pathProviderType = 'PathProvider' -as [type]
    $iPathProviderType = 'IPathProvider' -as [type]
    if ($null -ne $pathProviderType -and $null -ne $iPathProviderType -and $PathProvider -is $iPathProviderType -and -not ($PathProvider -is $pathProviderType)) {
        $PathProvider = $pathProviderType::new([IPathProvider]$PathProvider)
    }

    $pluginsRoot = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths','App','Plugins','Root')
    $pluginsDownloads = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths','App','Plugins','Downloads')
    $pluginsTemp = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths','App','Plugins','Temp')
    $vaultPath = Get-PSmmPluginsConfigNestedValue -Object $Config -Path @('Paths','App','Vault')

    if ([string]::IsNullOrWhiteSpace($pluginsRoot)) {
        throw 'Unable to resolve plugin root path (Config.Paths.App.Plugins.Root).'
    }

    if ([string]::IsNullOrWhiteSpace($pluginsDownloads)) {
        throw 'Unable to resolve plugin downloads path (Config.Paths.App.Plugins.Downloads).'
    }

    if ([string]::IsNullOrWhiteSpace($pluginsTemp)) {
        throw 'Unable to resolve plugin temp path (Config.Paths.App.Plugins.Temp).'
    }

    if ([string]::IsNullOrWhiteSpace($vaultPath)) {
        throw 'Unable to resolve vault path (Config.Paths.App.Vault).'
    }

    $paths = @{
        Root = $pluginsRoot
        _Downloads = $pluginsDownloads
        _Temp = $pluginsTemp
    }

    $pluginsManifest = Resolve-PluginsConfig -Config $Config
    $pluginConfig = $pluginsManifest.c_Misc.KeePassXC
    if (-not $pluginConfig) {
        throw 'KeePassXC plugin configuration is missing from plugin manifest.'
    }

    $plugin = @{
        Key    = 'KeePassXC'
        Config = $pluginConfig
    }

    $state = Get-InstallState -Plugin $plugin -Paths $paths -FileSystem $FileSystem -Process $Process
    if (-not [string]::IsNullOrEmpty($state.CurrentVersion)) {
        Write-PSmmLog -Level INFO -Context 'Install-KeePassXC' -Message "KeePassXC already installed ($($state.CurrentVersion))" -Console -File
        return $state
    }

    Write-PSmmLog -Level NOTICE -Context 'Install-KeePassXC' -Message 'Installing KeePassXC to satisfy secret loading requirements' -Console -File
    Install-Plugin -Plugin $plugin -Paths $paths -Config $Config -Http $Http -Crypto $Crypto `
        -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process

    $state = Get-InstallState -Plugin $plugin -Paths $paths -FileSystem $FileSystem -Process $Process
    if ([string]::IsNullOrEmpty($state.CurrentVersion)) {
        throw 'KeePassXC installation did not produce a usable CLI.'
    }

    $cliResolution = Resolve-KeePassCliCommand -VaultPath $vaultPath -FileSystem $FileSystem -Environment $Environment -PathProvider $PathProvider -Process $Process
    if (-not $cliResolution.Command) {
        $checked = if ($cliResolution.CandidatePaths) { $cliResolution.CandidatePaths -join ', ' } else { 'No candidate locations were discovered' }
        Write-PSmmLog -Level ERROR -Context 'Install-KeePassXC' `
            -Message "KeePassXC installed but keepassxc-cli.exe still missing. Checked: $checked" -Console -File
        throw 'keepassxc-cli.exe could not be resolved after installation.'
    }

    Write-PSmmLog -Level SUCCESS -Context 'Install-KeePassXC' `
        -Message "keepassxc-cli.exe resolved at $($cliResolution.ResolvedExecutable)" -Console -File

    return $state
}
