<#
.SYNOPSIS
    Exports a sanitized (safe) snapshot of the current AppConfiguration to a PSD1 file.

.DESCRIPTION
    Creates a reduced configuration export that omits sensitive data (secrets, master password,
    transient caches) while retaining diagnostic and structural information useful for support,
    logging and post-run analysis. The resulting file is a PowerShell data file (*.psd1).

    Sanitization rules:
      - Secret values are never written; only presence flags and entry paths.
      - Master password cache indicators removed.
    - Plugin paths retained (non-secret) for diagnostics.
      - Storage status retained.
      - Parameters retained (Dev/Verbose/Update/etc.).

.PARAMETER Configuration
    The live [AppConfiguration] object.

.PARAMETER Path
    Destination .psd1 file path. Parent directory will be created if missing.

.PARAMETER ServiceContainer
    ServiceContainer instance for accessing FileSystem service. If omitted, falls back to native cmdlets.

.EXAMPLE
    Export-SafeConfiguration -Configuration $appConfig -Path (Join-Path -Path $appConfig.Paths.Log -ChildPath 'PSmediaManager-Run.psd1') -ServiceContainer $ServiceContainer

.OUTPUTS
    String (path) - Returns the path written on success.

.NOTES
    This function intentionally does NOT round-trip the full configuration. It is a diagnostic artifact.
    If shape changes, extend the sanitization helper instead of writing raw object.

    BREAKING CHANGE (v0.2.0): Replaced -FileSystem parameter with -ServiceContainer parameter.
#>

#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function Export-SafeConfiguration {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [Alias('Config')]
        [object]$Configuration,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [object]$ServiceContainer
    )

    try {
        Write-Verbose "[SafeExport] BEGIN -> $Path"

        # Helper: Normalize scalars that otherwise expand into deep graphs when reflected (DateTime/TimeSpan/enums)
        function _ToSafeScalar([object]$x) {
            if ($null -eq $x) { return $null }
            if ($x -is [datetime]) { return $x.ToString('o') }
            if ($x -is [System.DateTimeOffset]) { return $x.ToString('o') }
            if ($x -is [timespan]) { return $x.ToString('c') }
            try {
                if ($x.GetType().IsEnum) { return $x.ToString() }
            } catch {
                Write-Verbose "[SafeExport] _ToSafeScalar enum detection failed: $($_.Exception.Message)"
            }
            return $x
        }

        function _NormalizeModuleDescriptorValue {
            param([Parameter()][AllowNull()]$Value)

            if ($null -eq $Value) { return $null }

            $safe = _ToSafeScalar $Value

            if ($safe -is [System.Collections.IDictionary]) {
                $ht = @{}
                foreach ($key in $safe.Keys) {
                    $ht[$key] = _NormalizeModuleDescriptorValue $safe[$key]
                }
                return $ht
            }

            if ($safe -is [System.Collections.IEnumerable] -and $safe -isnot [string]) {
                $arr = @()
                foreach ($item in $safe) { $arr += _NormalizeModuleDescriptorValue $item }
                return $arr
            }

            if ($safe -is [string]) { return $safe.Trim() }
            if ($safe -is [ValueType]) { return $safe }

            try { return $safe.ToString().Trim() }
            catch { return $safe }
        }

        function _NormalizeModuleDescriptor {
            param([Parameter()][AllowNull()]$Module)

            if ($null -eq $Module) { return $null }

            if ($Module -is [System.Collections.IDictionary]) {
                $ht = @{}
                foreach ($key in $Module.Keys) {
                    $ht[$key] = _NormalizeModuleDescriptorValue $Module[$key]
                }
                return $ht
            }

            if ($Module | Get-Member -MemberType Properties -ErrorAction SilentlyContinue) {
                $ht = @{}
                $props = $Module | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                foreach ($prop in $props) {
                    try { $ht[$prop] = _NormalizeModuleDescriptorValue ($Module.$prop) }
                    catch { $ht[$prop] = $null }
                }
                return $ht
            }

            if ($Module -is [string]) {
                $name = $Module.Trim()
                return @{ Name = $name }
            }

            try { return @{ Name = ($Module.ToString().Trim()) } }
            catch { return @{ } }
        }

        function _NormalizeModuleDescriptorList {
            param([Parameter()][AllowNull()]$Modules)

            if ($null -eq $Modules) { return $null }

            $collection = $Modules
            if ($collection -isnot [System.Collections.IEnumerable] -or $collection -is [string]) {
                $collection = @($Modules)
            }

            $result = @()
            foreach ($module in $collection) {
                $descriptor = _NormalizeModuleDescriptor $module
                if ($null -ne $descriptor) { $result += , $descriptor }
            }

            if ($result.Count -eq 0) { return @() }
            return $result
        }

        # Build a plain hashtable snapshot from typed AppConfiguration to preserve structure deterministically
        function Build-SafeSnapshot {
            param(
                [Parameter(Mandatory)][ValidateNotNull()][object]$Configuration
            )

            # Helper: copy arbitrary object graph (hashtable/collection/property bag) while
            # normalizing simple scalars. Allows graceful handling of loose hashtables used by
            # integration tests that do not populate a full AppConfiguration instance.
            function _CloneGeneric {
                param(
                    [Parameter()][AllowNull()]$Value,
                    [int]$Level = 0,
                    [int]$MaxDepth = 20,
                    [Parameter()][hashtable]$Visited
                )

                if ($null -eq $Value) { return $null }
                if ($Level -gt $MaxDepth) { return '[MaxDepth]' }

                if ($null -eq $Visited) { $Visited = @{} }

                $normalized = _ToSafeScalar $Value
                $isPrimitive = $Value -is [ValueType] -or $Value -is [string]
                if ($isPrimitive -or $normalized -ne $Value) { return $normalized }

                $objId = $null
                try { $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Value) }
                catch { $objId = $null }
                if ($null -ne $objId) {
                    if ($Visited.ContainsKey($objId)) { return '[CyclicRef]' }
                    $Visited[$objId] = $true
                }

                if ($Value -is [System.Collections.IDictionary]) {
                    $dictCopy = @{}
                    foreach ($key in $Value.Keys) {
                        $dictCopy[$key] = _CloneGeneric -Value $Value[$key] -Level ($Level + 1) -MaxDepth $MaxDepth -Visited $Visited
                    }
                    return $dictCopy
                }

                if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
                    $arrCopy = @()
                    foreach ($item in $Value) {
                        $arrCopy += _CloneGeneric -Value $item -Level ($Level + 1) -MaxDepth $MaxDepth -Visited $Visited
                    }
                    return $arrCopy
                }

                if ($Value -isnot [string] -and $Value -isnot [System.Collections.IEnumerable] -and ($Value | Get-Member -MemberType Properties -ErrorAction SilentlyContinue)) {
                    $propCopy = @{}
                    $props = $Value | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                    foreach ($p in $props) {
                        try {
                            $propCopy[$p] = _CloneGeneric -Value ($Value.$p) -Level ($Level + 1) -MaxDepth $MaxDepth -Visited $Visited
                        }
                        catch {
                            $propCopy[$p] = $null
                        }
                    }
                    return $propCopy
                }

                return $Value
            }

            # Helper: copy StorageDriveConfig -> hashtable
            function _DriveToHash([object]$d) {
                if ($null -eq $d) { return $null }
                return @{
                    Label = $d.Label
                    SerialNumber = $d.SerialNumber
                    DriveLetter = $d.DriveLetter
                    Path = $d.Path
                    IsAvailable = $d.IsAvailable
                    FreeSpaceGB = $d.FreeSpaceGB
                    TotalSpaceGB = $d.TotalSpaceGB
                }
            }

            # Helper: convert generic Dictionary[string,object] to hashtable with projection
            function _DictToHash([object]$dict, [scriptblock]$projector) {
                $h = @{}
                if ($null -eq $dict) { return $h }
                foreach ($k in $dict.Keys) { $h[$k] = & $projector $dict[$k] }
                return $h
            }

            function _GetMemberValue {
                param(
                    [Parameter()][AllowNull()]$InputObject,
                    [Parameter()][ValidateNotNullOrEmpty()][string]$Name
                )

                if ($null -eq $InputObject) { return $null }

                $value = $null
                $hasConfigMemberAccess = $false
                try {
                    $hasConfigMemberAccess = ($null -ne ('ConfigMemberAccess' -as [type]))
                }
                catch {
                    $hasConfigMemberAccess = $false
                }

                if ($hasConfigMemberAccess) {
                    try {
                        if ([ConfigMemberAccess]::TryGetMemberValue($InputObject, $Name, [ref]$value)) {
                            return $value
                        }
                        return $null
                    }
                    catch {
                        Write-Verbose "[SafeExport] _GetMemberValue ConfigMemberAccess lookup failed: $($_.Exception.Message)"
                        return $null
                    }
                }

                if ($InputObject -is [System.Collections.IDictionary]) {
                    try {
                        if ($InputObject.ContainsKey($Name)) { return $InputObject[$Name] }
                    }
                    catch {
                        Write-Verbose "[SafeExport] _GetMemberValue IDictionary.ContainsKey lookup failed: $($_.Exception.Message)"
                    }
                    try {
                        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
                    }
                    catch {
                        Write-Verbose "[SafeExport] _GetMemberValue IDictionary.Contains lookup failed: $($_.Exception.Message)"
                    }

                    try {
                        foreach ($k in $InputObject.Keys) {
                            if ($k -eq $Name) { return $InputObject[$k] }
                        }
                    }
                    catch {
                        Write-Verbose "[SafeExport] _GetMemberValue IDictionary.Keys lookup failed: $($_.Exception.Message)"
                    }
                    return $null
                }

                # Prefer property access for typed objects/PSCustomObjects
                try {
                    return $InputObject.$Name
                }
                catch {
                    $null = $_
                    # Ignore
                }

                try {
                    if ($InputObject.ContainsKey($Name)) { return $InputObject[$Name] }
                }
                catch {
                    Write-Verbose "[SafeExport] _GetMemberValue ContainsKey lookup failed: $($_.Exception.Message)"
                }
                try {
                    return $InputObject[$Name]
                }
                catch {
                    Write-Verbose "[SafeExport] _GetMemberValue indexer lookup failed: $($_.Exception.Message)"
                }

                return $null
            }

            function _HasMember {
                param(
                    [Parameter()][AllowNull()]$InputObject,
                    [Parameter()][ValidateNotNullOrEmpty()][string]$Name
                )

                if ($null -eq $InputObject) { return $false }

                $value = $null
                $hasConfigMemberAccess = $false
                try {
                    $hasConfigMemberAccess = ($null -ne ('ConfigMemberAccess' -as [type]))
                }
                catch {
                    $hasConfigMemberAccess = $false
                }

                if ($hasConfigMemberAccess) {
                    try {
                        return [ConfigMemberAccess]::TryGetMemberValue($InputObject, $Name, [ref]$value)
                    }
                    catch {
                        Write-Verbose "[SafeExport] _HasMember ConfigMemberAccess lookup failed: $($_.Exception.Message)"
                        return $false
                    }
                }

                try { $null = $InputObject.$Name; return $true } catch { $null = $_ }
                try { $null = $InputObject[$Name]; return $true } catch { $null = $_ }
                return $false
            }

            function _GetDictionaryKeys {
                param([Parameter()][AllowNull()]$Dictionary)

                if ($null -eq $Dictionary) { return @() }

                if ($Dictionary -is [System.Collections.IDictionary]) {
                    return @($Dictionary.Keys)
                }

                try { return @($Dictionary.Keys) } catch { return @() }
            }

            $typeNames = @($Configuration.PSObject.TypeNames)
            $configTypeName = $null
            try {
                $configTypeName = $Configuration.GetType().FullName
            }
            catch {
                $configTypeName = $null
            }

            $isAppConfiguration = $false
            if ($configTypeName -and ($configTypeName -eq 'AppConfiguration' -or $configTypeName -like '*.AppConfiguration')) {
                $isAppConfiguration = $true
            }
            elseif ($typeNames -contains 'AppConfiguration') {
                $isAppConfiguration = $true
            }
            $hasPathsProperty = _HasMember -InputObject $Configuration -Name 'Paths'
            $hasStorageProperty = _HasMember -InputObject $Configuration -Name 'Storage'
            $looksTyped = $isAppConfiguration -or ($hasPathsProperty -and $hasStorageProperty)

            if (-not $looksTyped) {
                return _CloneGeneric -Value $Configuration
            }

            # Paths snapshot (typed AppPaths -> nested hashtables)
            $paths = $null
            $p = _GetMemberValue -InputObject $Configuration -Name 'Paths'
            if ($null -ne $p) {
                $appNode = _GetMemberValue -InputObject $p -Name 'App'

                $plugins = $null
                $pluginsNode = _GetMemberValue -InputObject $appNode -Name 'Plugins'
                if ($null -ne $pluginsNode) {
                    $plugins = @{
                        Root = _GetMemberValue -InputObject $pluginsNode -Name 'Root'
                        Downloads = _GetMemberValue -InputObject $pluginsNode -Name 'Downloads'
                        Temp = _GetMemberValue -InputObject $pluginsNode -Name 'Temp'
                    }
                }

                $appPaths = $null
                if ($null -ne $appNode) {
                    $appPaths = @{
                        Root = _GetMemberValue -InputObject $appNode -Name 'Root'
                        Config = _GetMemberValue -InputObject $appNode -Name 'Config'
                        ConfigDigiKam = _GetMemberValue -InputObject $appNode -Name 'ConfigDigiKam'
                        Modules = _GetMemberValue -InputObject $appNode -Name 'Modules'
                        Plugins = $plugins
                        Vault = _GetMemberValue -InputObject $appNode -Name 'Vault'
                    }
                }

                $paths = @{
                    Root = _GetMemberValue -InputObject $p -Name 'Root'
                    Log = _GetMemberValue -InputObject $p -Name 'Log'
                    App = $appPaths
                }
            }

            # Logging snapshot
            $logging = $null
            $l = _GetMemberValue -InputObject $Configuration -Name 'Logging'
            if ($null -ne $l) {
                try {
                    if ($l -and ($l | Get-Member -Name 'ToHashtable' -MemberType Method -ErrorAction SilentlyContinue)) {
                        $logging = $l.ToHashtable()
                    }
                }
                catch {
                    $logging = $null
                }

                if ($null -eq $logging) {
                    $logging = @{
                        Path = _GetMemberValue -InputObject $l -Name 'Path'
                        Level = _GetMemberValue -InputObject $l -Name 'Level'
                        DefaultLevel = _GetMemberValue -InputObject $l -Name 'DefaultLevel'
                        Format = _GetMemberValue -InputObject $l -Name 'Format'
                        EnableConsole = _GetMemberValue -InputObject $l -Name 'EnableConsole'
                        EnableFile = _GetMemberValue -InputObject $l -Name 'EnableFile'
                        MaxFileSizeMB = _GetMemberValue -InputObject $l -Name 'MaxFileSizeMB'
                        MaxLogFiles = _GetMemberValue -InputObject $l -Name 'MaxLogFiles'
                    }
                }
            }

            # Parameters snapshot
            $parameters = $null
            $pr = _GetMemberValue -InputObject $Configuration -Name 'Parameters'
            if ($null -ne $pr) {
                try {
                    if ($pr -and ($pr | Get-Member -Name 'ToHashtable' -MemberType Method -ErrorAction SilentlyContinue)) {
                        $parameters = $pr.ToHashtable()
                    }
                }
                catch {
                    $parameters = $null
                }

                if ($null -eq $parameters) {
                    $parameters = @{
                        Debug = _GetMemberValue -InputObject $pr -Name 'Debug'
                        Verbose = _GetMemberValue -InputObject $pr -Name 'Verbose'
                        Dev = _GetMemberValue -InputObject $pr -Name 'Dev'
                        Update = _GetMemberValue -InputObject $pr -Name 'Update'
                    }
                }
            }

            # Storage snapshot
            $storage = @{}
            $storageSource = _GetMemberValue -InputObject $Configuration -Name 'Storage'
            if ($null -ne $storageSource) {
                foreach ($gid in (_GetDictionaryKeys $storageSource)) {
                    $sg = _GetMemberValue -InputObject $storageSource -Name $gid
                    if ($null -eq $sg) { continue }

                    $masterObj = _GetMemberValue -InputObject $sg -Name 'Master'
                    $backupsObj = _GetMemberValue -InputObject $sg -Name 'Backups'

                    # Ensure nested backups directly on the Master object (runtime augmentation, idempotent)
                    try {
                        if ($masterObj -and $backupsObj -and (-not (_HasMember -InputObject $masterObj -Name 'Backups'))) {
                            $masterObj | Add-Member -MemberType NoteProperty -Name Backups -Value $backupsObj -Force
                        }
                    }
                    catch {
                        Write-Verbose "[SafeExport] Failed to augment master with backups for group '$gid': $($_.Exception.Message)"
                    }

                    # Build nested representation: Master contains Drive + Backups
                    $nestedMaster = @{
                        Drive = _DriveToHash $masterObj
                        Backups = _DictToHash -dict $backupsObj -projector { param($x) (_DriveToHash $x) }
                    }

                    $storage[$gid] = @{
                        GroupId = _GetMemberValue -InputObject $sg -Name 'GroupId'
                        Master = $nestedMaster
                        Paths = _DictToHash -dict (_GetMemberValue -InputObject $sg -Name 'Paths') -projector { param($v) $v }
                    }
                }
            }

            # StorageRegistry snapshot (restructured to nested layout mirroring Storage)
            $storageRegistry = $null
            $reg = _GetMemberValue -InputObject $Configuration -Name 'StorageRegistry'
            $flatDrivesSource = _GetMemberValue -InputObject $reg -Name 'Drives'
            $flatDrives = if ($null -ne $flatDrivesSource) { $flatDrivesSource } else { @{} }

            $nestedDrives = @{}

            $storageSourceForRegistry = if ($null -ne $storageSource) { $storageSource } else { _GetMemberValue -InputObject $Configuration -Name 'Storage' }

            if ($null -ne $storageSourceForRegistry) {
                # First, iterate storage groups to build master->backups mapping
                foreach ($gid in (_GetDictionaryKeys $storageSourceForRegistry)) {
                    $sg = _GetMemberValue -InputObject $storageSourceForRegistry -Name $gid
                    if ($null -eq $sg) { continue }
                    $masterConfig = _GetMemberValue -InputObject $sg -Name 'Master'
                    if (-not $masterConfig) { continue }
                    $msn = _GetMemberValue -InputObject $masterConfig -Name 'SerialNumber'
                    if ([string]::IsNullOrWhiteSpace($msn)) { continue }
                    if (-not $nestedDrives.ContainsKey($msn)) {
                        $masterReg = $null
                        $src = if ($flatDrives) { _GetMemberValue -InputObject $flatDrives -Name $msn } else { $null }
                        if ($null -ne $src) {
                            $masterReg = @{
                                SerialNumber = _GetMemberValue -InputObject $src -Name 'SerialNumber'
                                DriveLetter = _GetMemberValue -InputObject $src -Name 'DriveLetter'
                                Label = _GetMemberValue -InputObject $src -Name 'Label'
                                HealthStatus = _GetMemberValue -InputObject $src -Name 'HealthStatus'
                                PartitionKind = _GetMemberValue -InputObject $src -Name 'PartitionKind'
                                FreeSpace = _GetMemberValue -InputObject $src -Name 'FreeSpace'
                                TotalSpace = _GetMemberValue -InputObject $src -Name 'TotalSpace'
                                UsedSpace = _GetMemberValue -InputObject $src -Name 'UsedSpace'
                                FileSystem = _GetMemberValue -InputObject $src -Name 'FileSystem'
                                Manufacturer = _GetMemberValue -InputObject $src -Name 'Manufacturer'
                                Model = _GetMemberValue -InputObject $src -Name 'Model'
                                Number = _GetMemberValue -InputObject $src -Name 'Number'
                            }
                        } else {
                            # Fallback to minimal info from configured Master when registry info is missing
                            $masterReg = @{
                                SerialNumber = _GetMemberValue -InputObject $masterConfig -Name 'SerialNumber'
                                DriveLetter = _GetMemberValue -InputObject $masterConfig -Name 'DriveLetter'
                                Label = _GetMemberValue -InputObject $masterConfig -Name 'Label'
                            }
                        }
                        $nestedDrives[$msn] = @{ Master = $masterReg; Backups = @{} }
                    }

                    $backupsCollection = _GetMemberValue -InputObject $sg -Name 'Backups'
                    foreach ($bk in (_GetDictionaryKeys $backupsCollection)) {
                        $bDrive = _GetMemberValue -InputObject $backupsCollection -Name $bk
                        if ($null -eq $bDrive) { continue }
                        $bsn = _GetMemberValue -InputObject $bDrive -Name 'SerialNumber'
                        if ([string]::IsNullOrWhiteSpace($bsn)) { continue }
                        $srcB = if ($flatDrives) { _GetMemberValue -InputObject $flatDrives -Name $bsn } else { $null }
                        if ($null -ne $srcB) {
                            $nestedDrives[$msn].Backups[$bsn] = @{
                                SerialNumber = _GetMemberValue -InputObject $srcB -Name 'SerialNumber'
                                DriveLetter = _GetMemberValue -InputObject $srcB -Name 'DriveLetter'
                                Label = _GetMemberValue -InputObject $srcB -Name 'Label'
                                HealthStatus = _GetMemberValue -InputObject $srcB -Name 'HealthStatus'
                                PartitionKind = _GetMemberValue -InputObject $srcB -Name 'PartitionKind'
                                FreeSpace = _GetMemberValue -InputObject $srcB -Name 'FreeSpace'
                                TotalSpace = _GetMemberValue -InputObject $srcB -Name 'TotalSpace'
                                UsedSpace = _GetMemberValue -InputObject $srcB -Name 'UsedSpace'
                                FileSystem = _GetMemberValue -InputObject $srcB -Name 'FileSystem'
                                Manufacturer = _GetMemberValue -InputObject $srcB -Name 'Manufacturer'
                                Model = _GetMemberValue -InputObject $srcB -Name 'Model'
                                Number = _GetMemberValue -InputObject $srcB -Name 'Number'
                            }
                        } else {
                            # Fallback to minimal info from configured backup drive
                            $nestedDrives[$msn].Backups[$bsn] = @{
                                SerialNumber = _GetMemberValue -InputObject $bDrive -Name 'SerialNumber'
                                DriveLetter = _GetMemberValue -InputObject $bDrive -Name 'DriveLetter'
                                Label = _GetMemberValue -InputObject $bDrive -Name 'Label'
                            }
                        }
                    }
                }
            }

            # Include any registry drives not referenced by configured storage (orphans)
            foreach ($sn in (_GetDictionaryKeys $flatDrives)) {
                if (-not $nestedDrives.ContainsKey($sn)) {
                    # Treat as standalone master with no backups
                    $srcO = _GetMemberValue -InputObject $flatDrives -Name $sn
                    $orphanMaster = @{
                        SerialNumber = _GetMemberValue -InputObject $srcO -Name 'SerialNumber'
                        DriveLetter = _GetMemberValue -InputObject $srcO -Name 'DriveLetter'
                        Label = _GetMemberValue -InputObject $srcO -Name 'Label'
                        HealthStatus = _GetMemberValue -InputObject $srcO -Name 'HealthStatus'
                        PartitionKind = _GetMemberValue -InputObject $srcO -Name 'PartitionKind'
                        FreeSpace = _GetMemberValue -InputObject $srcO -Name 'FreeSpace'
                        TotalSpace = _GetMemberValue -InputObject $srcO -Name 'TotalSpace'
                        UsedSpace = _GetMemberValue -InputObject $srcO -Name 'UsedSpace'
                        FileSystem = _GetMemberValue -InputObject $srcO -Name 'FileSystem'
                        Manufacturer = _GetMemberValue -InputObject $srcO -Name 'Manufacturer'
                        Model = _GetMemberValue -InputObject $srcO -Name 'Model'
                        Number = _GetMemberValue -InputObject $srcO -Name 'Number'
                    }
                    $nestedDrives[$sn] = @{ Master = $orphanMaster; Backups = @{} }
                }
            }

            $hasNestedDrives = $nestedDrives -and @($nestedDrives.Keys).Count -gt 0
            $hasFlatDrives = @(_GetDictionaryKeys $flatDrives).Count -gt 0
            if ($reg -or $hasNestedDrives -or $hasFlatDrives) {
                $registryLastScanned = $null
                if ($reg) { $registryLastScanned = _GetMemberValue -InputObject $reg -Name 'LastScanned' }

                # Ensure a timestamp exists
                if ($null -eq $registryLastScanned -or ($registryLastScanned -is [string] -and [string]::IsNullOrWhiteSpace($registryLastScanned)) -or (
                        $registryLastScanned -is [datetime] -and $registryLastScanned -eq [datetime]::MinValue)) {
                    $registryLastScanned = Get-Date
                }

                $registryLastScanned = _ToSafeScalar $registryLastScanned

                $storageRegistry = @{
                    LastScanned = $registryLastScanned
                    Drives = if ($nestedDrives -and @($nestedDrives.Keys).Count -gt 0) { $nestedDrives } else { @{} }
                }
            }

            # Error messages dictionary (string->string)
            $errors = @{}
            $errorMessagesSource = _GetMemberValue -InputObject $Configuration -Name 'ErrorMessages'
            if ($null -ne $errorMessagesSource) {
                foreach ($ek in (_GetDictionaryKeys $errorMessagesSource)) {
                    $errors[$ek] = _GetMemberValue -InputObject $errorMessagesSource -Name $ek
                }
            }

            # Projects block: flatten to plain hashtable to avoid back-references and deep graphs
            $projects = $null
            $projectsSource = _GetMemberValue -InputObject $Configuration -Name 'Projects'
            if ($null -ne $projectsSource) {
                $projectsToClone = $projectsSource
                try {
                    $projectsToClone = $projectsSource.ToHashtable()
                }
                catch {
                    $projectsToClone = $projectsSource
                }
                $plainVisited = @{}
                function _PlainCopy {
                    param(
                        [Parameter()][AllowNull()]$Obj,
                        [int]$Level = 0,
                        [int]$MaxDepth = 12
                    )
                    if ($null -eq $Obj) { return $null }
                    if ($Level -gt $MaxDepth) { return '[MaxDepth]' }

                    # Normalize well-known scalars (DateTime/Offset/TimeSpan/enums)
                    $safeScalar = _ToSafeScalar $Obj
                    $isPrimitive = $Obj -is [ValueType] -or $Obj -is [string]
                    if ($isPrimitive -or $safeScalar -ne $Obj) { return $safeScalar }

                    # Cycle guard
                    $objId = $null
                    try { $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Obj) } catch { $objId = $null }
                    if ($null -ne $objId) {
                        if ($plainVisited.ContainsKey($objId)) { return '[CyclicRef]' }
                        $plainVisited[$objId] = $true
                    }

                    if ($Obj -is [System.Collections.IDictionary]) {
                        $h = @{}
                        foreach ($k in $Obj.Keys) { $h[$k] = _PlainCopy -Obj $Obj[$k] -Level ($Level + 1) -MaxDepth $MaxDepth }
                        return $h
                    }

                    if ($Obj -is [System.Collections.IEnumerable] -and $Obj -isnot [string]) {
                        $arr = @(); $count = 0
                        foreach ($i in $Obj) {
                            $arr += (_PlainCopy -Obj $i -Level ($Level + 1) -MaxDepth $MaxDepth)
                            $count++
                            if ($count -ge 500) { $arr += '[Truncated]'; break }
                        }
                        return $arr
                    }

                    # Object with properties -> hashtable with filtered props to avoid back-refs
                    $res = @{}
                    $props = $Obj | Get-Member -MemberType Properties -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
                    foreach ($p in $props) {
                        if ($p -match '(?i)^(Config|Configuration|Owner|Parent|AppConfig|Host)$') { continue }
                        try { $val = $Obj.$p } catch { $val = $null }
                        # Normalize property scalars before recursion to avoid expanding Date/Time types
                        $res[$p] = _PlainCopy -Obj (_ToSafeScalar $val) -Level ($Level + 1) -MaxDepth $MaxDepth
                    }
                    return $res
                }

                $projects = _PlainCopy -Obj $projectsToClone

                # Omit per-drive Projects arrays from Projects.Registry in safe export
                # Requirement: When Config is exported the Projects inside the Drives in Registry must be omitted.
                try {
                    $hasRegistry = $false
                    if ($projects -is [System.Collections.IDictionary]) {
                        try { $hasRegistry = $projects.ContainsKey('Registry') } catch { $hasRegistry = $false }
                        if (-not $hasRegistry) { try { $hasRegistry = $projects.Contains('Registry') } catch { $hasRegistry = $false } }
                        if (-not $hasRegistry) {
                            try {
                                foreach ($k in $projects.Keys) {
                                    if ($k -eq 'Registry') { $hasRegistry = $true; break }
                                }
                            }
                            catch {
                                Write-Verbose "[SafeExport] Unable to enumerate Projects keys for Registry detection: $($_.Exception.Message)"
                                $hasRegistry = $false
                            }
                        }
                    }

                    if ($projects -is [System.Collections.IDictionary] -and
                        $hasRegistry -and
                        $projects.Registry -is [System.Collections.IDictionary]) {
                        foreach ($kind in @('Master', 'Backup')) {
                            $hasKind = $false
                            try { $hasKind = $projects.Registry.ContainsKey($kind) } catch { $hasKind = $false }
                            if (-not $hasKind) { try { $hasKind = $projects.Registry.Contains($kind) } catch { $hasKind = $false } }
                            if (-not $hasKind) {
                                try {
                                    foreach ($k in $projects.Registry.Keys) {
                                        if ($k -eq $kind) { $hasKind = $true; break }
                                    }
                                }
                                catch {
                                    Write-Verbose "[SafeExport] Unable to enumerate Projects.Registry keys for '$kind' detection: $($_.Exception.Message)"
                                    $hasKind = $false
                                }
                            }

                            if ($hasKind -and ($projects.Registry.$kind -is [System.Collections.IDictionary])) {
                                foreach ($label in @($projects.Registry.$kind.Keys)) {
                                    $drive = $projects.Registry.$kind[$label]
                                    $hasProjectsKey = $false
                                    if ($drive -is [System.Collections.IDictionary]) {
                                        try { $hasProjectsKey = $drive.ContainsKey('Projects') } catch { $hasProjectsKey = $false }
                                        if (-not $hasProjectsKey) { try { $hasProjectsKey = $drive.Contains('Projects') } catch { $hasProjectsKey = $false } }
                                        if (-not $hasProjectsKey) {
                                            try {
                                                foreach ($k in $drive.Keys) {
                                                    if ($k -eq 'Projects') { $hasProjectsKey = $true; break }
                                                }
                                            }
                                            catch {
                                                Write-Verbose "[SafeExport] Unable to enumerate drive keys for Projects pruning: $($_.Exception.Message)"
                                                $hasProjectsKey = $false
                                            }
                                        }
                                    }

                                    if ($drive -is [System.Collections.IDictionary] -and $hasProjectsKey) {
                                        [void]$drive.Remove('Projects')
                                    }
                                }
                            }
                        }
                    }
                }
                catch {
                    Write-Verbose "[SafeExport] Failed to prune Projects from Projects.Registry: $($_.Exception.Message)"
                }
            }

            # UI block (prefer hashtable for safe export)
            $ui = $null
            $uiSource = _GetMemberValue -InputObject $Configuration -Name 'UI'
            if ($null -ne $uiSource) {
                $uiToClone = $uiSource
                try {
                    $uiToClone = $uiSource.ToHashtable()
                }
                catch {
                    $uiToClone = $uiSource
                }

                $ui = _CloneGeneric -Value $uiToClone
            }

            # Requirements
            $requirements = $null
            $requirementsSource = _GetMemberValue -InputObject $Configuration -Name 'Requirements'
            $requirementsModules = $null
            $requirementsPowerShellModules = $null
            if ($null -ne $requirementsSource) {
                $requirements = _CloneGeneric -Value $requirementsSource

                $moduleSource = _GetMemberValue -InputObject $requirementsSource -Name 'PSModules'
                if ($null -ne $moduleSource) {
                    if ($moduleSource -is [System.Collections.IEnumerable] -and $moduleSource -isnot [string]) {
                        $requirementsModules = @()
                        foreach ($module in $moduleSource) {
                            if ($null -eq $module) { $requirementsModules += '' }
                            else { $requirementsModules += ($module.ToString().Trim()) }
                        }
                    }
                    elseif ($moduleSource -is [string]) {
                        $requirementsModules = @($moduleSource.Trim())
                    }
                }

                $powerShellSource = _GetMemberValue -InputObject $requirementsSource -Name 'PowerShell'
                if ($null -ne $powerShellSource) {
                    $powerShellModulesSource = _GetMemberValue -InputObject $powerShellSource -Name 'Modules'
                    if ($null -ne $powerShellModulesSource) {
                        $requirementsPowerShellModules = _NormalizeModuleDescriptorList $powerShellModulesSource
                    }
                }
            }
            try {
                $modulesValue = _GetMemberValue -InputObject $requirements -Name 'PSModules'
                if ($null -ne $modulesValue -and $modulesValue -is [System.Collections.IEnumerable] -and $modulesValue -isnot [string]) {
                    $normalizedModules = @()
                    foreach ($module in $modulesValue) {
                        if ($null -eq $module) {
                            $normalizedModules += ''
                        } else {
                            $normalizedModules += ($module.ToString().Trim())
                        }
                    }

                    if ($requirements -is [System.Collections.IDictionary]) {
                        $requirements['PSModules'] = $normalizedModules
                    }
                    else {
                        try { $requirements.PSModules = $normalizedModules }
                        catch { Write-Verbose "[SafeExport] Unable to assign normalized PSModules: $($_.Exception.Message)" }
                    }
                }
                elseif ($requirementsModules) {
                    if ($requirements -is [System.Collections.IDictionary]) {
                        $requirements['PSModules'] = $requirementsModules
                    }
                    else {
                        try { $requirements.PSModules = $requirementsModules }
                        catch { Write-Verbose "[SafeExport] Unable to assign captured PSModules: $($_.Exception.Message)" }
                    }
                }
            }
            catch {
                Write-Verbose "[SafeExport] Failed to normalize PSModules: $($_.Exception.Message)"
            }

            try {
                $psRequirementsValue = $null
                if ($requirements -is [System.Collections.IDictionary]) {
                    $hasPowerShell = $false
                    try { $hasPowerShell = $requirements.ContainsKey('PowerShell') } catch { $hasPowerShell = $false }
                    if (-not $hasPowerShell) { try { $hasPowerShell = $requirements.Contains('PowerShell') } catch { $hasPowerShell = $false } }
                    if (-not $hasPowerShell) {
                        try {
                            foreach ($k in $requirements.Keys) {
                                if ($k -eq 'PowerShell') { $hasPowerShell = $true; break }
                            }
                        }
                        catch {
                            Write-Verbose "[SafeExport] Unable to enumerate Requirements keys for PowerShell detection: $($_.Exception.Message)"
                            $hasPowerShell = $false
                        }
                    }
                    if ($hasPowerShell) { $psRequirementsValue = $requirements['PowerShell'] }
                }
                elseif ($null -ne $requirements) {
                    try { $psRequirementsValue = $requirements.PowerShell }
                    catch { $psRequirementsValue = $null }
                }

                if ($null -ne $psRequirementsValue) {
                    $modulesDescriptor = $null
                    if ($psRequirementsValue -is [System.Collections.IDictionary]) {
                        $hasModules = $false
                        try { $hasModules = $psRequirementsValue.ContainsKey('Modules') } catch { $hasModules = $false }
                        if (-not $hasModules) { try { $hasModules = $psRequirementsValue.Contains('Modules') } catch { $hasModules = $false } }
                        if (-not $hasModules) {
                            try {
                                foreach ($k in $psRequirementsValue.Keys) {
                                    if ($k -eq 'Modules') { $hasModules = $true; break }
                                }
                            }
                            catch {
                                Write-Verbose "[SafeExport] Unable to enumerate PowerShell Requirements keys for Modules detection: $($_.Exception.Message)"
                                $hasModules = $false
                            }
                        }
                        if ($hasModules) { $modulesDescriptor = $psRequirementsValue['Modules'] }
                    }
                    else {
                        try { $modulesDescriptor = $psRequirementsValue.Modules }
                        catch { $modulesDescriptor = $null }
                    }

                    if ($null -ne $modulesDescriptor -and $modulesDescriptor -is [System.Collections.IEnumerable] -and $modulesDescriptor -isnot [string]) {
                        $normalizedDescriptors = _NormalizeModuleDescriptorList $modulesDescriptor
                        if ($psRequirementsValue -is [System.Collections.IDictionary]) {
                            $psRequirementsValue['Modules'] = $normalizedDescriptors
                        }
                        else {
                            try { $psRequirementsValue.Modules = $normalizedDescriptors }
                            catch { Write-Verbose "[SafeExport] Unable to assign normalized PowerShell modules: $($_.Exception.Message)" }
                        }
                    }
                    elseif ($null -ne $requirementsPowerShellModules) {
                        if ($psRequirementsValue -is [System.Collections.IDictionary]) {
                            $psRequirementsValue['Modules'] = $requirementsPowerShellModules
                        }
                        else {
                            try { $psRequirementsValue.Modules = $requirementsPowerShellModules }
                            catch { Write-Verbose "[SafeExport] Unable to assign captured PowerShell modules: $($_.Exception.Message)" }
                        }
                    }
                }
            }
            catch {
                Write-Verbose "[SafeExport] Failed to normalize PowerShell module descriptors: $($_.Exception.Message)"
            }

            $appName = _GetMemberValue -InputObject $Configuration -Name 'InternalName'
            $appVersionValue = _GetMemberValue -InputObject $Configuration -Name 'AppVersion'

            # Plugins block: capture resolved plugins manifest and paths
            $plugins = $null
            $pluginsSource = _GetMemberValue -InputObject $Configuration -Name 'Plugins'
            if ($null -ne $pluginsSource) {
                $plugins = @{}
                if ($pluginsSource -is [System.Collections.IDictionary]) {
                    foreach ($pk in @('Global', 'Project', 'Resolved', 'Paths')) {
                        $hasKey = $false
                        try { $hasKey = $pluginsSource.ContainsKey($pk) } catch { $hasKey = $false }
                        if (-not $hasKey) { try { $hasKey = $pluginsSource.Contains($pk) } catch { $hasKey = $false } }
                        if (-not $hasKey) {
                            try {
                                foreach ($k in $pluginsSource.Keys) {
                                    if ($k -eq $pk) { $hasKey = $true; break }
                                }
                            }
                            catch {
                                Write-Verbose "[SafeExport] Unable to enumerate Plugins keys for '$pk' detection: $($_.Exception.Message)"
                                $hasKey = $false
                            }
                        }
                        if ($hasKey) {
                            $plugins[$pk] = _PlainCopy -Obj $pluginsSource[$pk]
                        }
                    }
                } else {
                    foreach ($pk in @('Global', 'Project', 'Resolved', 'Paths')) {
                        $val = $null
                        try { $val = $pluginsSource.$pk } catch { $val = $null }
                        if ($null -ne $val) { $plugins[$pk] = _PlainCopy -Obj $val }
                    }
                }
            }

            # Compose snapshot
            return @{
                App = @{
                    Name = $appName
                    AppVersion = $appVersionValue
                }
                Paths = $paths
                Logging = $logging
                Parameters = $parameters
                Storage = $storage
                StorageRegistry = $storageRegistry
                Projects = $projects
                Plugins = $plugins
                UI = $ui
                Requirements = $requirements
                ErrorMessages = $errors
                Timestamp = (Get-Date).ToString('o')
            }
        }

        # Prepare a single visited map for cycle detection across the entire traversal
        $visitedMap = @{}

        # Track GitHub token occurrences so we can preserve ghp_/etc. prefixes even for secret keys
        function _CollectGitHubTokenPaths {
            param(
                [Parameter()][AllowNull()]$Data,
                [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$Results,
                [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.ArrayList]$PathStack,
                [Parameter(Mandatory)][hashtable]$Visited
            )

            if ($null -eq $Data) { return }

            if ($Data -is [string]) {
                $maskedCandidate = $Data -replace '(?i)(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9]{36,}', '$1****************'
                if ($maskedCandidate -ne $Data -and -not [string]::IsNullOrWhiteSpace($maskedCandidate)) {
                    $null = $Results.Add([pscustomobject]@{
                        Path = $PathStack.ToArray()
                        MaskedValue = $maskedCandidate
                    })
                }
                return
            }

            $isPrimitive = $Data -is [ValueType]
            if (-not $isPrimitive) {
                try { $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Data) }
                catch { $objId = $null }
                if ($null -ne $objId) {
                    if ($Visited.ContainsKey($objId)) { return }
                    $Visited[$objId] = $true
                }
            }

            if ($Data -is [System.Collections.IDictionary]) {
                foreach ($key in $Data.Keys) {
                    $PathStack.Add($key) | Out-Null
                    _CollectGitHubTokenPaths -Data $Data[$key] -Results $Results -PathStack $PathStack -Visited $Visited
                    $PathStack.RemoveAt($PathStack.Count - 1)
                }
                return
            }

            if ($Data -is [System.Collections.IEnumerable] -and $Data -isnot [string]) {
                $index = 0
                foreach ($item in $Data) {
                    $PathStack.Add($index) | Out-Null
                    _CollectGitHubTokenPaths -Data $item -Results $Results -PathStack $PathStack -Visited $Visited
                    $PathStack.RemoveAt($PathStack.Count - 1)
                    $index++
                }
            }
        }

        function _ApplyGitHubTokenMasks {
            param(
                [Parameter()][AllowNull()]$Data,
                [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.IEnumerable]$Locations
            )

            if ($null -eq $Data) { return }

            foreach ($location in $Locations) {
                if ($null -eq $location.Path -or $location.Path.Length -eq 0) { continue }

                $current = $Data
                $segments = $location.Path
                for ($i = 0; $i -lt ($segments.Length - 1); $i++) {
                    $segment = $segments[$i]
                    if ($current -is [System.Collections.IDictionary]) {
                        $hasSegment = $false
                        try { $hasSegment = $current.ContainsKey($segment) } catch { $hasSegment = $false }
                        if (-not $hasSegment) { try { $hasSegment = $current.Contains($segment) } catch { $hasSegment = $false } }
                        if (-not $hasSegment) {
                            try {
                                foreach ($k in $current.Keys) {
                                    if ($k -eq $segment) { $hasSegment = $true; break }
                                }
                            }
                            catch {
                                Write-Verbose "[SafeExport] Unable to enumerate dictionary keys while locating masked token path segment '$segment': $($_.Exception.Message)"
                                $hasSegment = $false
                            }
                        }

                        if ($hasSegment) { $current = $current[$segment] }
                        else { $current = $null; break }
                    }
                    elseif ($current -is [System.Collections.IList]) {
                        if ($segment -is [int] -and $segment -ge 0 -and $segment -lt $current.Count) {
                            $current = $current[$segment]
                        }
                        else {
                            $current = $null; break
                        }
                    }
                    else {
                        $current = $null; break
                    }
                }

                if ($null -eq $current) { continue }

                $lastSegment = $segments[$segments.Length - 1]
                if ($current -is [System.Collections.IDictionary]) {
                    $hasKey = $false
                    try { $hasKey = $current.ContainsKey($lastSegment) } catch { $hasKey = $false }
                    if (-not $hasKey) { try { $hasKey = $current.Contains($lastSegment) } catch { $hasKey = $false } }
                    if (-not $hasKey) {
                        try {
                            foreach ($k in $current.Keys) {
                                if ($k -eq $lastSegment) { $hasKey = $true; break }
                            }
                        }
                        catch {
                            Write-Verbose "[SafeExport] Unable to enumerate dictionary keys while locating masked token key '$lastSegment': $($_.Exception.Message)"
                            $hasKey = $false
                        }
                    }
                    if (-not $hasKey) { continue }
                    $candidate = $current[$lastSegment]
                    if ($candidate -is [string] -and $candidate -eq '********') {
                        $current[$lastSegment] = $location.MaskedValue
                    }
                }
                elseif ($current -is [System.Collections.IList]) {
                    if ($lastSegment -isnot [int]) { continue }
                    if ($lastSegment -lt 0 -or $lastSegment -ge $current.Count) { continue }
                    $candidate = $current[$lastSegment]
                    if ($candidate -is [string] -and $candidate -eq '********') {
                        $current[$lastSegment] = $location.MaskedValue
                    }
                }
            }
        }

        # Sanitizer: masks sensitive keys and token-like strings; preserves structure
        function _Sanitize {
            param(
                [Parameter()][AllowNull()]$Data,
                [Parameter()][hashtable]$Visited,
                [int]$Level = 0,
                [int]$MaxDepth = 40
            )
            if ($null -eq $Data) { return $null }

            if ($Level -gt $MaxDepth) { return '[MaxDepth]' }

            # Initialize visited map on first call
            if ($null -eq $Visited) { $Visited = $visitedMap }

            # Normalize common scalars first (prevents DateTime/TimeSpan object graph expansion)
            if ($Data -is [datetime]) { return $Data.ToString('o') }
            if ($Data -is [System.DateTimeOffset]) { return $Data.ToString('o') }
            if ($Data -is [timespan]) { return $Data.ToString('c') }
            try { if ($Data.GetType().IsEnum) { return $Data.ToString() } } catch { Write-Verbose "[SafeExport] Enum check failed: $($_.Exception.Message)" }

            # Primitive / value types do not need cycle tracking
            $isPrimitive = $Data -is [ValueType] -or $Data -is [string]
            if (-not $isPrimitive) {
                # Use runtime hashcode for identity (works for PSObjects, reference types)
                try {
                    $objId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Data)
                } catch { $objId = $null }
                if ($null -ne $objId) {
                    if ($Visited.ContainsKey($objId)) {
                        return '[CyclicRef]'
                    } else {
                        $Visited[$objId] = $true
                    }
                }
            }

            # GitHub token patterns gh[pousr]_ + 36+ chars
            $maskString = {
                param([string]$s)
                if ($null -eq $s) { return $null }
                $s -replace '(?i)(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9]{36,}', '$1****************'
            }

            # Hashtable / IDictionary
            if ($Data -is [System.Collections.IDictionary]) {
                $res = @{}
                foreach ($k in $Data.Keys) {
                    if ($k -match '(?i)(Token|Password|Secret|ApiKey|Credential|Pwd)') {
                        $res[$k] = '********'
                    } else {
                        $res[$k] = _Sanitize -Data $Data[$k] -Visited $Visited -Level ($Level + 1) -MaxDepth $MaxDepth
                    }
                }
                return $res
            }

            # Enumerable (arrays etc.) but not string
            if ($Data -is [System.Collections.IEnumerable] -and $Data -isnot [string]) {
                $arr = @()
                foreach ($i in $Data) { $arr += _Sanitize -Data $i -Visited $Visited -Level ($Level + 1) -MaxDepth $MaxDepth }
                return $arr
            }

            # PSCustomObject or other object with properties
            if ($Data -isnot [string] -and ($Data | Get-Member -MemberType Properties -ErrorAction SilentlyContinue)) {
                $res = @{}
                $props = $Data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                foreach ($p in $props) {
                    if ($p -match '(?i)(Token|Password|Secret|ApiKey|Credential|Pwd)') {
                        $res[$p] = '********'
                    } else {
                        try { $val = $Data.$p } catch { $val = $null }
                        # Normalize scalars before recursing
                        $res[$p] = _Sanitize -Data (_ToSafeScalar $val) -Visited $Visited -Level ($Level + 1) -MaxDepth $MaxDepth
                    }
                }
                return $res
            }

            # String masking
            if ($Data -is [string]) { return & $maskString $Data }

            # Primitive
            return $Data
        }

        # Serialize to PSD1
        function _ToPsd1 {
            param([Parameter()][AllowNull()][object]$Data, [int]$Level = 0)
            $indent = ' ' * ($Level * 4)
            # Requirement: All config export VALUES must be single-quoted and trimmed.
            # We interpret this to mean all scalar values (string/bool/numeric/etc.) are rendered
            # as trimmed invariant-culture strings wrapped in single quotes. Complex types (@{ } / @())
            # are still emitted in native PSD1 form so they remain importable as structured data.
            if ($null -eq $Data) { return "''" }  # Represent null as empty quoted string

            # Helper to turn ANY scalar into a trimmed, single-quoted string with escaped single quotes
            function _ScalarToQuoted([object]$x) {
                if ($null -eq $x) { return "''" }
                $s = switch -Exact ($x.GetType().FullName) {
                    'System.Boolean' { if ($x) { 'True' } else { 'False' }; break }
                    'System.Int32' { $x.ToString([System.Globalization.CultureInfo]::InvariantCulture); break }
                    'System.Int64' { $x.ToString([System.Globalization.CultureInfo]::InvariantCulture); break }
                    'System.Double' { $x.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture); break }
                    'System.Decimal' { $x.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture); break }
                    'System.Single' { $x.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture); break }
                    default { $x.ToString() }
                }
                # Trim whitespace (leading/trailing) per requirement
                $s = $s.Trim()
                # Escape embedded single quotes by doubling them
                return "'$($s -replace "'", "''")'"
            }

            # Treat strings & primitives immediately
            if ($Data -is [string] -or $Data -is [ValueType]) { return _ScalarToQuoted $Data }

            # If object is known date/time/timespan (may arrive as PSCustomObject already stringified) handle explicitly
            if ($Data -is [datetime] -or $Data -is [System.DateTimeOffset] -or $Data -is [timespan]) { return _ScalarToQuoted $Data }

            if ($Data -is [System.Collections.IDictionary]) {
                function _FormatKey([object]$Key) {
                    if ($null -eq $Key) { return "''" }
                    if ($Key -is [int] -or $Key -is [long]) { return $Key.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
                    $s = $Key.ToString()
                    if ($Key -is [string] -and ($s -match '^[A-Za-z_][A-Za-z0-9_]*$')) { return $s }
                    return "'$($s -replace "'", "''")'"
                }
                $sb = [System.Text.StringBuilder]::new(); $null = $sb.AppendLine('@{')
                foreach ($k in $Data.Keys) {
                    $v = _ToPsd1 -Data $Data[$k] -Level ($Level + 1)
                    $kRepr = _FormatKey -Key $k
                    $null = $sb.AppendLine("$indent    $kRepr = $v")
                }
                $null = $sb.Append("$indent}")
                return $sb.ToString()
            }
            if ($Data -is [System.Collections.IEnumerable]) {
                $items = @(); foreach ($i in $Data) {
                    if ($i -is [string] -or $i -is [ValueType]) { $items += (_ScalarToQuoted $i) } else { $items += (_ToPsd1 -Data $i -Level ($Level + 1)) }
                }
                return "@(" + ($items -join ', ') + ")"
            }
            # Fallback: treat object.ToString() as scalar representation
            return _ScalarToQuoted $Data
        }

        # Sanitize input configuration (support hashtable, custom object, AppConfiguration, etc.)
        # Build rich snapshot first so generic dictionaries and typed objects are represented as hashtables
        $snapshot = Build-SafeSnapshot -Configuration $Configuration

        $gitHubTokenLocations = New-Object System.Collections.ArrayList
        _CollectGitHubTokenPaths -Data $snapshot -Results $gitHubTokenLocations -PathStack (New-Object System.Collections.ArrayList) -Visited @{}

        # Note: Omit Environment and KeysTest from export to maximize PSD1 import compatibility

        # Now sanitize snapshot (will also mask any secrets inside Environment.Modules etc.)
        $sanitized = _Sanitize -Data $snapshot -Visited $visitedMap

        # Helper: Recursively convert all LEAF values to trimmed strings so the final PSD1
        # persists every value inside single quotes, regardless of original type.
        function _StringifyValues {
            param([Parameter()][AllowNull()]$Data)

            if ($null -eq $Data) { return '' } # null -> empty string (will serialize as '')

            # Treat strings and primitives as scalars -> invariant string + trim
            if ($Data -is [string]) { return ($Data.Trim()) }
            if ($Data -is [ValueType]) {
                switch ($Data.GetType().FullName) {
                    'System.Boolean' { if ($Data) { return 'True' } else { return 'False' } }
                    'System.Double' { return $Data.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture) }
                    'System.Decimal' { return $Data.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture) }
                    'System.Single' { return $Data.ToString('0.###############', [System.Globalization.CultureInfo]::InvariantCulture) }
                    default { return $Data.ToString([System.IFormatProvider]([System.Globalization.CultureInfo]::InvariantCulture)) }
                }
            }

            # Normalize well-known scalars possibly arriving as reference types
            if ($Data -is [datetime]) { return $Data.ToString('o') }
            if ($Data -is [System.DateTimeOffset]) { return $Data.ToString('o') }
            if ($Data -is [timespan]) { return $Data.ToString('c') }
            try {
                if ($Data.GetType().IsEnum) { return $Data.ToString() }
            }
            catch {
                Write-Verbose "[SafeExport] Enum stringify failed: $($_.Exception.Message)"
            }

            # IDictionary -> recurse value-wise
            if ($Data -is [System.Collections.IDictionary]) {
                $h = @{}
                foreach ($k in $Data.Keys) { $h[$k] = _StringifyValues $Data[$k] }
                return $h
            }

            # IEnumerable (non-string) -> map elements
            if ($Data -is [System.Collections.IEnumerable] -and $Data -isnot [string]) {
                $arr = @(); foreach ($i in $Data) { $arr += (_StringifyValues $i) }; return $arr
            }

            # PSCustomObject or other prop-bag -> convert to hashtable then recurse
            if ($Data -isnot [string] -and ($Data | Get-Member -MemberType Properties -ErrorAction SilentlyContinue)) {
                $props = $Data | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
                $h2 = @{}
                foreach ($p in $props) {
                    try { $h2[$p] = _StringifyValues ($Data.$p) } catch { $h2[$p] = '' }
                }
                return $h2
            }

            # Fallback: ToString() then trim
            return ($Data.ToString().Trim())
        }

        # Ensure we convert any PSCustomObjects to pure hashtables for downstream Save helper
        if ($sanitized -isnot [System.Collections.IDictionary]) {
            # Wrap non-hashtable root into hashtable under 'Data' key
            $sanitized = @{ Data = $sanitized }
        }

        # Capture original modules list for preservation during serialization
        $originalModules = $null
        $originalPowerShellModules = $null
        $hasOriginalPowerShellModules = $false
        try {
            $reqSourceOriginal = $null
            if ($Configuration -is [System.Collections.IDictionary]) {
                $hasRequirements = $false
                try { $hasRequirements = $Configuration.ContainsKey('Requirements') } catch { $hasRequirements = $false }
                if (-not $hasRequirements) {
                    try { $hasRequirements = $Configuration.Contains('Requirements') } catch { $hasRequirements = $false }
                }
                if (-not $hasRequirements) {
                    try {
                        foreach ($k in $Configuration.Keys) {
                            if ($k -eq 'Requirements') { $hasRequirements = $true; break }
                        }
                    }
                    catch {
                        Write-Verbose "[SafeExport] Unable to enumerate Configuration keys for Requirements detection: $($_.Exception.Message)"
                        $hasRequirements = $false
                    }
                }
                if ($hasRequirements) { $reqSourceOriginal = $Configuration['Requirements'] }
            }
            else {
                $reqSourceOriginal = _GetMemberValue -InputObject $Configuration -Name 'Requirements'
            }

            if ($null -ne $reqSourceOriginal) {
                $modulesCandidate = $null
                if ($reqSourceOriginal -is [System.Collections.IDictionary]) {
                    $hasPSModules = $false
                    try { $hasPSModules = $reqSourceOriginal.ContainsKey('PSModules') } catch { $hasPSModules = $false }
                    if (-not $hasPSModules) {
                        try { $hasPSModules = $reqSourceOriginal.Contains('PSModules') } catch { $hasPSModules = $false }
                    }
                    if (-not $hasPSModules) {
                        try {
                            foreach ($k in $reqSourceOriginal.Keys) {
                                if ($k -eq 'PSModules') { $hasPSModules = $true; break }
                            }
                        }
                        catch {
                            Write-Verbose "[SafeExport] Unable to enumerate Requirements keys for PSModules capture: $($_.Exception.Message)"
                            $hasPSModules = $false
                        }
                    }
                    if ($hasPSModules) { $modulesCandidate = $reqSourceOriginal['PSModules'] }
                }
                else {
                    $modulesCandidate = _GetMemberValue -InputObject $reqSourceOriginal -Name 'PSModules'
                }

                if ($null -ne $modulesCandidate) {
                    if ($modulesCandidate -is [System.Collections.IEnumerable] -and $modulesCandidate -isnot [string]) {
                        $originalModules = @()
                        foreach ($moduleName in $modulesCandidate) {
                            if ($null -eq $moduleName) { $originalModules += '' }
                            else { $originalModules += ($moduleName.ToString().Trim()) }
                        }
                    }
                    elseif ($modulesCandidate -is [string]) {
                        $originalModules = @($modulesCandidate.Trim())
                    }
                }

                $powerShellCandidate = $null
                if ($reqSourceOriginal -is [System.Collections.IDictionary]) {
                    $hasPowerShell = $false
                    try { $hasPowerShell = $reqSourceOriginal.ContainsKey('PowerShell') } catch { $hasPowerShell = $false }
                    if (-not $hasPowerShell) {
                        try { $hasPowerShell = $reqSourceOriginal.Contains('PowerShell') } catch { $hasPowerShell = $false }
                    }
                    if (-not $hasPowerShell) {
                        try {
                            foreach ($k in $reqSourceOriginal.Keys) {
                                if ($k -eq 'PowerShell') { $hasPowerShell = $true; break }
                            }
                        }
                        catch {
                            Write-Verbose "[SafeExport] Unable to enumerate Requirements keys for PowerShell capture: $($_.Exception.Message)"
                            $hasPowerShell = $false
                        }
                    }
                    if ($hasPowerShell) { $powerShellCandidate = $reqSourceOriginal['PowerShell'] }
                }
                else {
                    $powerShellCandidate = _GetMemberValue -InputObject $reqSourceOriginal -Name 'PowerShell'
                }

                if ($null -ne $powerShellCandidate) {
                    $powerShellModulesCandidate = $null
                    if ($powerShellCandidate -is [System.Collections.IDictionary]) {
                        $hasModules = $false
                        try { $hasModules = $powerShellCandidate.ContainsKey('Modules') } catch { $hasModules = $false }
                        if (-not $hasModules) {
                            try { $hasModules = $powerShellCandidate.Contains('Modules') } catch { $hasModules = $false }
                        }
                        if (-not $hasModules) {
                            try {
                                foreach ($k in $powerShellCandidate.Keys) {
                                    if ($k -eq 'Modules') { $hasModules = $true; break }
                                }
                            }
                            catch {
                                Write-Verbose "[SafeExport] Unable to enumerate PowerShell requirement keys for Modules capture: $($_.Exception.Message)"
                                $hasModules = $false
                            }
                        }
                        if ($hasModules) { $powerShellModulesCandidate = $powerShellCandidate['Modules'] }
                    }
                    else {
                        $powerShellModulesCandidate = _GetMemberValue -InputObject $powerShellCandidate -Name 'Modules'
                    }

                    if ($null -ne $powerShellModulesCandidate) {
                        $normalizedDescriptors = _NormalizeModuleDescriptorList $powerShellModulesCandidate
                        if ($null -eq $normalizedDescriptors) { $normalizedDescriptors = @() }
                        $originalPowerShellModules = $normalizedDescriptors
                        $hasOriginalPowerShellModules = $true
                    }
                    else {
                        $hasOriginalPowerShellModules = $true
                        $originalPowerShellModules = @()
                    }
                }
            }
        }
        catch {
            Write-Verbose "[SafeExport] Failed to capture original PSModules: $($_.Exception.Message)"
        }

        # Convert all leaves to trimmed strings for uniform single-quoted serialization
        $stringified = _StringifyValues $sanitized
        if ($gitHubTokenLocations.Count -gt 0) {
            _ApplyGitHubTokenMasks -Data $stringified -Locations $gitHubTokenLocations
        }

        if ($originalModules) {
            try {
                if ($stringified -is [System.Collections.IDictionary]) {
                    $hasRequirementsKey = $false
                    try { $hasRequirementsKey = $stringified.ContainsKey('Requirements') } catch { $hasRequirementsKey = $false }
                    if (-not $hasRequirementsKey) { try { $hasRequirementsKey = $stringified.Contains('Requirements') } catch { $hasRequirementsKey = $false } }
                    if (-not $hasRequirementsKey) {
                        try {
                            foreach ($k in $stringified.Keys) {
                                if ($k -eq 'Requirements') { $hasRequirementsKey = $true; break }
                            }
                        }
                        catch {
                            Write-Verbose "[SafeExport] Unable to enumerate serialized output keys for Requirements restore: $($_.Exception.Message)"
                            $hasRequirementsKey = $false
                        }
                    }

                    if ($hasRequirementsKey) {
                        $reqTarget = $stringified['Requirements']
                        if ($reqTarget -isnot [System.Collections.IDictionary]) { $reqTarget = @{}; $stringified['Requirements'] = $reqTarget }
                        $reqTarget['PSModules'] = @($originalModules)
                    }

                    $hasAppKey = $false
                    try { $hasAppKey = $stringified.ContainsKey('App') } catch { $hasAppKey = $false }
                    if (-not $hasAppKey) { try { $hasAppKey = $stringified.Contains('App') } catch { $hasAppKey = $false } }
                    if (-not $hasAppKey) {
                        try {
                            foreach ($k in $stringified.Keys) {
                                if ($k -eq 'App') { $hasAppKey = $true; break }
                            }
                        }
                        catch {
                            Write-Verbose "[SafeExport] Unable to enumerate serialized output keys for App restore: $($_.Exception.Message)"
                            $hasAppKey = $false
                        }
                    }

                    if ($hasAppKey) {
                        $appTarget = $stringified['App']
                        $hasAppRequirementsKey = $false
                        if ($appTarget -is [System.Collections.IDictionary]) {
                            try { $hasAppRequirementsKey = $appTarget.ContainsKey('Requirements') } catch { $hasAppRequirementsKey = $false }
                            if (-not $hasAppRequirementsKey) { try { $hasAppRequirementsKey = $appTarget.Contains('Requirements') } catch { $hasAppRequirementsKey = $false } }
                            if (-not $hasAppRequirementsKey) {
                                try {
                                    foreach ($k in $appTarget.Keys) {
                                        if ($k -eq 'Requirements') { $hasAppRequirementsKey = $true; break }
                                    }
                                }
                                catch {
                                    Write-Verbose "[SafeExport] Unable to enumerate serialized App keys for Requirements restore: $($_.Exception.Message)"
                                    $hasAppRequirementsKey = $false
                                }
                            }
                        }

                        if ($appTarget -is [System.Collections.IDictionary] -and $hasAppRequirementsKey) {
                            $appReqTarget = $appTarget['Requirements']
                            if ($appReqTarget -isnot [System.Collections.IDictionary]) { $appReqTarget = @{}; $appTarget['Requirements'] = $appReqTarget }
                            $appReqTarget['PSModules'] = @($originalModules)
                        }
                    }
                }
            }
            catch {
                Write-Verbose "[SafeExport] Failed to restore PSModules into serialized output: $($_.Exception.Message)"
            }
        }

        if ($hasOriginalPowerShellModules) {
            try {
                if ($stringified -is [System.Collections.IDictionary]) {
                    $hasRequirementsKey = $false
                    try { $hasRequirementsKey = $stringified.ContainsKey('Requirements') } catch { $hasRequirementsKey = $false }
                    if (-not $hasRequirementsKey) { try { $hasRequirementsKey = $stringified.Contains('Requirements') } catch { $hasRequirementsKey = $false } }
                    if (-not $hasRequirementsKey) {
                        try {
                            foreach ($k in $stringified.Keys) {
                                if ($k -eq 'Requirements') { $hasRequirementsKey = $true; break }
                            }
                        }
                        catch {
                            Write-Verbose "[SafeExport] Unable to enumerate serialized output keys for PowerShell restore: $($_.Exception.Message)"
                            $hasRequirementsKey = $false
                        }
                    }

                    if ($hasRequirementsKey) {
                        $reqTarget = $stringified['Requirements']
                        if ($reqTarget -isnot [System.Collections.IDictionary]) { $reqTarget = @{}; $stringified['Requirements'] = $reqTarget }

                        $psTarget = $null
                        $hasPowerShellKey = $false
                        if ($reqTarget -is [System.Collections.IDictionary]) {
                            try { $hasPowerShellKey = $reqTarget.ContainsKey('PowerShell') } catch { $hasPowerShellKey = $false }
                            if (-not $hasPowerShellKey) { try { $hasPowerShellKey = $reqTarget.Contains('PowerShell') } catch { $hasPowerShellKey = $false } }
                            if (-not $hasPowerShellKey) {
                                try {
                                    foreach ($k in $reqTarget.Keys) {
                                        if ($k -eq 'PowerShell') { $hasPowerShellKey = $true; break }
                                    }
                                }
                                catch {
                                    Write-Verbose "[SafeExport] Unable to enumerate serialized Requirements keys for PowerShell restore: $($_.Exception.Message)"
                                    $hasPowerShellKey = $false
                                }
                            }
                        }

                        if ($reqTarget -is [System.Collections.IDictionary] -and $hasPowerShellKey) {
                            $psTarget = $reqTarget['PowerShell']
                        }

                        if ($psTarget -isnot [System.Collections.IDictionary]) {
                            $psTarget = @{}
                            if ($reqTarget -is [System.Collections.IDictionary]) { $reqTarget['PowerShell'] = $psTarget }
                        }

                        if ($psTarget -is [System.Collections.IDictionary]) {
                            $psTarget['Modules'] = $originalPowerShellModules
                        }
                    }

                    $hasAppKey = $false
                    try { $hasAppKey = $stringified.ContainsKey('App') } catch { $hasAppKey = $false }
                    if (-not $hasAppKey) { try { $hasAppKey = $stringified.Contains('App') } catch { $hasAppKey = $false } }
                    if (-not $hasAppKey) {
                        try {
                            foreach ($k in $stringified.Keys) {
                                if ($k -eq 'App') { $hasAppKey = $true; break }
                            }
                        }
                        catch {
                            Write-Verbose "[SafeExport] Unable to enumerate serialized output keys for App PowerShell restore: $($_.Exception.Message)"
                            $hasAppKey = $false
                        }
                    }

                    if ($hasAppKey) {
                        $appTarget = $stringified['App']
                        $hasAppRequirementsKey = $false
                        if ($appTarget -is [System.Collections.IDictionary]) {
                            try { $hasAppRequirementsKey = $appTarget.ContainsKey('Requirements') } catch { $hasAppRequirementsKey = $false }
                            if (-not $hasAppRequirementsKey) { try { $hasAppRequirementsKey = $appTarget.Contains('Requirements') } catch { $hasAppRequirementsKey = $false } }
                            if (-not $hasAppRequirementsKey) {
                                try {
                                    foreach ($k in $appTarget.Keys) {
                                        if ($k -eq 'Requirements') { $hasAppRequirementsKey = $true; break }
                                    }
                                }
                                catch {
                                    Write-Verbose "[SafeExport] Unable to enumerate serialized App keys for Requirements PowerShell restore: $($_.Exception.Message)"
                                    $hasAppRequirementsKey = $false
                                }
                            }
                        }

                        if ($appTarget -is [System.Collections.IDictionary] -and $hasAppRequirementsKey) {
                            $appReqTarget = $appTarget['Requirements']
                            if ($appReqTarget -isnot [System.Collections.IDictionary]) {
                                $appReqTarget = @{}
                                $appTarget['Requirements'] = $appReqTarget
                            }

                            if ($appReqTarget -is [System.Collections.IDictionary]) {
                                $appPsTarget = $null
                                $hasAppPowerShellKey = $false
                                try { $hasAppPowerShellKey = $appReqTarget.ContainsKey('PowerShell') } catch { $hasAppPowerShellKey = $false }
                                if (-not $hasAppPowerShellKey) { try { $hasAppPowerShellKey = $appReqTarget.Contains('PowerShell') } catch { $hasAppPowerShellKey = $false } }
                                if (-not $hasAppPowerShellKey) {
                                    try {
                                        foreach ($k in $appReqTarget.Keys) {
                                            if ($k -eq 'PowerShell') { $hasAppPowerShellKey = $true; break }
                                        }
                                    }
                                    catch {
                                        Write-Verbose "[SafeExport] Unable to enumerate serialized App Requirements keys for PowerShell restore: $($_.Exception.Message)"
                                        $hasAppPowerShellKey = $false
                                    }
                                }
                                if ($hasAppPowerShellKey) { $appPsTarget = $appReqTarget['PowerShell'] }

                                if ($appPsTarget -isnot [System.Collections.IDictionary]) {
                                    $appPsTarget = @{}
                                    $appReqTarget['PowerShell'] = $appPsTarget
                                }

                                if ($appPsTarget -is [System.Collections.IDictionary]) {
                                    $appPsTarget['Modules'] = $originalPowerShellModules
                                }
                            }
                        }
                    }
                }
            }
            catch {
                Write-Verbose "[SafeExport] Failed to restore PowerShell module descriptors into serialized output: $($_.Exception.Message)"
            }
        }

        # Serialize for direct write path
        $content = _ToPsd1 -Data $stringified
        if (-not $content) { throw 'Export produced empty content.' }

        # Resolve FileSystem service from container if available
        $fileSystem = $null
        if ($null -ne $ServiceContainer) {
            try {
                $fileSystem = $ServiceContainer.Resolve('FileSystem')
            }
            catch {
                Write-Verbose "[SafeExport] ServiceContainer.Resolve('FileSystem') failed: $_"
            }
        }

        # Ensure directory exists (use FileSystem service or fallback to native cmdlets)
        $parent = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            $handled = $false
            if ($null -ne $fileSystem) {
                try {
                    if (-not $fileSystem.TestPath($parent)) { $null = $fileSystem.NewItem($parent, 'Directory') }
                    $handled = $true
                }
                catch {
                    $handled = $false
                }
            }

            if (-not $handled) {
                # Fallback to native PowerShell cmdlets
                if (-not (Test-Path -Path $parent)) {
                    $null = New-Item -Path $parent -ItemType Directory -Force -ErrorAction Stop
                }
            }
        }

        # Write using file system service or fallback to native Set-Content
        $wroteWithService = $false
        if ($null -ne $fileSystem) {
            try {
                $fileSystem.SetContent($Path, $content)
                $wroteWithService = $true
            }
            catch {
                $msg = $null
                try { $msg = $_.Exception.Message } catch { $msg = $null }
                if ($msg -and ($msg -match "method named 'SetContent'")) {
                    $wroteWithService = $false
                }
                else {
                    throw "[SafeExport] FileSystem.SetContent failed: $_"
                }
            }
        }

        if (-not $wroteWithService) {
            # Fallback to native PowerShell Set-Content
            try {
                Set-Content -Path $Path -Value $content -Encoding UTF8 -Force -ErrorAction Stop
            }
            catch {
                throw "[SafeExport] Set-Content failed: $_"
            }
        }

        Write-Verbose "[SafeExport] OK (${([System.Text.Encoding]::UTF8.GetByteCount($content))} bytes)"
        return $Path
    }
    catch {
        throw "Failed to export safe configuration: $_"
    }
}
