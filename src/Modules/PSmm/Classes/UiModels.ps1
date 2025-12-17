#Requires -Version 7.5.4
Set-StrictMode -Version Latest

class UiColumn {
    [string]$Text = ''
    [object]$Width = 'auto'
    [string]$Alignment = 'l'
    [int]$Padding = 1

    [string]$TextColor = $null
    [string]$BackgroundColor = $null

    [bool]$Bold = $false
    [bool]$Italic = $false
    [bool]$Underline = $false
    [bool]$Dim = $false
    [bool]$Blink = $false
    [bool]$Strikethrough = $false

    [int]$MinWidth = 10
    [int]$MaxWidth = 0

    UiColumn() {
    }

    static [UiColumn] FromHashtable([hashtable]$column) {
        if ($null -eq $column) {
            throw [System.ArgumentNullException]::new('column')
        }

        $c = [UiColumn]::new()

        if ($column.ContainsKey('Text')) { $c.Text = [string]$column.Text }
        if ($column.ContainsKey('Width')) { $c.Width = $column.Width }
        if ($column.ContainsKey('Alignment')) { $c.Alignment = [string]$column.Alignment }
        if ($column.ContainsKey('Padding')) { $c.Padding = [int]$column.Padding }

        if ($column.ContainsKey('TextColor')) { $c.TextColor = $column.TextColor }
        if ($column.ContainsKey('BackgroundColor')) { $c.BackgroundColor = $column.BackgroundColor }

        if ($column.ContainsKey('Bold')) { $c.Bold = [bool]$column.Bold }
        if ($column.ContainsKey('Italic')) { $c.Italic = [bool]$column.Italic }
        if ($column.ContainsKey('Underline')) { $c.Underline = [bool]$column.Underline }
        if ($column.ContainsKey('Dim')) { $c.Dim = [bool]$column.Dim }
        if ($column.ContainsKey('Blink')) { $c.Blink = [bool]$column.Blink }
        if ($column.ContainsKey('Strikethrough')) { $c.Strikethrough = [bool]$column.Strikethrough }

        if ($column.ContainsKey('MinWidth')) { $c.MinWidth = [int]$column.MinWidth }
        if ($column.ContainsKey('MaxWidth')) { $c.MaxWidth = [int]$column.MaxWidth }

        return $c
    }

    [hashtable] ToHashtable() {
        return @{
            Text          = $this.Text
            Width         = $this.Width
            Alignment     = $this.Alignment
            Padding       = $this.Padding
            TextColor     = $this.TextColor
            BackgroundColor = $this.BackgroundColor
            Bold          = $this.Bold
            Italic        = $this.Italic
            Underline     = $this.Underline
            Dim           = $this.Dim
            Blink         = $this.Blink
            Strikethrough = $this.Strikethrough
            MinWidth      = $this.MinWidth
            MaxWidth      = $this.MaxWidth
        }
    }
}

class UiKeyValueItem {
    [string]$Key = ''
    [object]$Value = $null
    [string]$Color = $null

    UiKeyValueItem() {
    }

    UiKeyValueItem([string]$Key, [object]$Value, [string]$Color) {
        $this.Key = $Key
        $this.Value = $Value
        $this.Color = $Color
    }

    static [UiKeyValueItem] FromHashtable([hashtable]$item) {
        if ($null -eq $item) {
            throw [System.ArgumentNullException]::new('item')
        }

        $kv = [UiKeyValueItem]::new()
        if ($item.ContainsKey('Key')) { $kv.Key = [string]$item.Key }
        if ($item.ContainsKey('Value')) { $kv.Value = $item.Value }
        if ($item.ContainsKey('Color')) { $kv.Color = $item.Color }
        return $kv
    }

    [hashtable] ToHashtable() {
        return @{
            Key   = $this.Key
            Value = $this.Value
            Color = $this.Color
        }
    }
}

class UiErrorCatalog {
    [System.Collections.Generic.Dictionary[string, string]]$Storage

    UiErrorCatalog() {
        $this.Storage = [System.Collections.Generic.Dictionary[string, string]]::new()
    }

    static [UiErrorCatalog] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [UiErrorCatalog]::new()
        }

        if ($obj -is [UiErrorCatalog]) {
            return $obj
        }

        $catalog = [UiErrorCatalog]::new()

        # Shape A: @{ Storage = @{ '1.Master' = 'msg'; ... } }
        if ($obj -is [hashtable] -and $obj.ContainsKey('Storage')) {
            $storageObj = $obj['Storage']
            if ($storageObj -is [hashtable]) {
                foreach ($k in $storageObj.Keys) {
                    $v = $storageObj[$k]
                    if ($v -is [string] -and -not [string]::IsNullOrWhiteSpace($v)) {
                        $catalog.Storage[[string]$k] = $v
                    }
                }
            }
            return $catalog
        }

        # Shape B: flat hashtable of key -> message
        if ($obj -is [hashtable]) {
            foreach ($k in $obj.Keys) {
                $v = $obj[$k]
                if ($v -is [string] -and -not [string]::IsNullOrWhiteSpace($v)) {
                    $catalog.Storage[[string]$k] = $v
                }
            }
            return $catalog
        }

        return $catalog
    }

    [UiErrorCatalog] FilterStorageGroup([string]$storageGroupFilter) {
        if ([string]::IsNullOrWhiteSpace($storageGroupFilter)) {
            return $this
        }

        $filtered = [UiErrorCatalog]::new()
        $prefix = [regex]::Escape($storageGroupFilter) + '\.'
        foreach ($kvp in $this.Storage.GetEnumerator()) {
            if ($kvp.Key -match ('^' + $prefix)) {
                $filtered.Storage[$kvp.Key] = $kvp.Value
            }
        }
        return $filtered
    }

    [string[]] GetAllMessages() {
        $messages = [System.Collections.Generic.List[string]]::new()
        foreach ($kvp in $this.Storage.GetEnumerator()) {
            if (-not [string]::IsNullOrWhiteSpace($kvp.Value)) {
                $messages.Add($kvp.Value)
            }
        }
        return $messages.ToArray()
    }
}

class UiProjectsIndex {
    [hashtable]$Master
    [hashtable]$Backup

    UiProjectsIndex() {
        $this.Master = @{}
        $this.Backup = @{}
    }

    static [UiProjectsIndex] FromObject([object]$obj) {
        if ($null -eq $obj) {
            return [UiProjectsIndex]::new()
        }

        if ($obj -is [UiProjectsIndex]) {
            return $obj
        }

        $idx = [UiProjectsIndex]::new()

        $masterObj = $null
        $backupObj = $null

        if ($obj -is [hashtable]) {
            if ($obj.ContainsKey('Master')) { $masterObj = $obj['Master'] }
            if ($obj.ContainsKey('Backup')) { $backupObj = $obj['Backup'] }
        }
        else {
            if ($obj.PSObject.Properties.Match('Master').Count -gt 0) { $masterObj = $obj.Master }
            if ($obj.PSObject.Properties.Match('Backup').Count -gt 0) { $backupObj = $obj.Backup }
        }

        if ($masterObj -is [System.Collections.IDictionary]) {
            foreach ($k in $masterObj.Keys) {
                $v = $masterObj[$k]
                $idx.Master[[string]$k] = if ($null -eq $v) { [object[]]@() } else { [object[]]@($v) }
            }
        }

        if ($backupObj -is [System.Collections.IDictionary]) {
            foreach ($k in $backupObj.Keys) {
                $v = $backupObj[$k]
                $idx.Backup[[string]$k] = if ($null -eq $v) { [object[]]@() } else { [object[]]@($v) }
            }
        }

        return $idx
    }
}

class UiDriveProjectsInfo {
    [object[]]$Projects = @()
    [string]$DriveType = ''
    [string]$Prefix = ''
    [Nullable[int]]$BackupNumber = $null
    [bool]$IsFallback = $false

    UiDriveProjectsInfo() {
    }

    UiDriveProjectsInfo(
        [object[]]$Projects,
        [string]$DriveType,
        [string]$Prefix,
        [Nullable[int]]$BackupNumber,
        [bool]$IsFallback
    ) {
        $this.Projects = if ($null -eq $Projects) { @() } else { $Projects }
        $this.DriveType = $DriveType
        $this.Prefix = $Prefix
        $this.BackupNumber = $BackupNumber
        $this.IsFallback = $IsFallback
    }
}
