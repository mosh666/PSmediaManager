#Requires -Version 7.5.4
Set-StrictMode -Version Latest

class ConfigMemberAccess {
    static [bool] TryGetMemberValue([object] $Object, [string] $Name, [ref] $Value) {
        if ($null -eq $Object) {
            return $false
        }

        if ($Object -is [System.Collections.IDictionary]) {
            try {
                if ($Object.ContainsKey($Name)) {
                    $Value.Value = $Object[$Name]
                    return $true
                }
            }
            catch {
                $null = $_
                # Ignore; fall through
            }

            try {
                if ($Object.Contains($Name)) {
                    $Value.Value = $Object[$Name]
                    return $true
                }
            }
            catch {
                $null = $_
                # Ignore; fall through
            }

            try {
                foreach ($k in $Object.Keys) {
                    if ($k -eq $Name) {
                        $Value.Value = $Object[$k]
                        return $true
                    }
                }
            }
            catch {
                $null = $_
                # Ignore; fall through
            }

            return $false
        }

        $hasMember = $false
        try {
            $hasMember = $null -ne (
                $Object |
                    Get-Member -Name $Name -MemberType Property,NoteProperty,ScriptProperty,AliasProperty -ErrorAction SilentlyContinue
            )
        }
        catch {
            $hasMember = $false
        }

        if ($hasMember) {
            try {
                $Value.Value = $Object.$Name
                return $true
            }
            catch {
                return $false
            }
        }

        # Fallback for indexer-capable objects that aren't IDictionary
        # (e.g. objects with a default Item property / get_Item method).
        try {
            $Value.Value = $Object[$Name]
            return $true
        }
        catch {
            return $false
        }

        return $false
    }

    static [object] GetMemberValue([object] $Object, [string] $Name) {
        if ($null -eq $Object) {
            return $null
        }

        if ($Object -is [System.Collections.IDictionary]) {
            try {
                if ($Object.ContainsKey($Name)) {
                    return $Object[$Name]
                }
            }
            catch {
                $null = $_
                # Ignore; fall through
            }

            try {
                if ($Object.Contains($Name)) {
                    return $Object[$Name]
                }
            }
            catch {
                $null = $_
                # Ignore; fall through
            }

            try {
                foreach ($k in $Object.Keys) {
                    if ($k -eq $Name) {
                        return $Object[$k]
                    }
                }
            }
            catch {
                $null = $_
                # Ignore; fall through
            }

            return $null
        }

        $hasMember = $false
        try {
            $hasMember = $null -ne (
                $Object |
                    Get-Member -Name $Name -MemberType Property,NoteProperty,ScriptProperty,AliasProperty -ErrorAction SilentlyContinue
            )
        }
        catch {
            $hasMember = $false
        }

        if ($hasMember) {
            try {
                return $Object.$Name
            }
            catch {
                return $null
            }
        }

        # Fallback for indexer-capable objects that aren't IDictionary
        try {
            return $Object[$Name]
        }
        catch {
            return $null
        }

        return $null
    }

    static [object] GetNestedValue([object] $Object, [string[]] $Path) {
        $current = $Object
        foreach ($segment in $Path) {
            $current = [ConfigMemberAccess]::GetMemberValue($current, $segment)
            if ($null -eq $current) {
                return $null
            }
        }

        return $current
    }

    static [bool] SetMemberValue([object] $Object, [string] $Name, [object] $Value) {
        if ($null -eq $Object) {
            return $false
        }

        if ($Object -is [System.Collections.IDictionary]) {
            try {
                $Object[$Name] = $Value
                return $true
            }
            catch {
                return $false
            }
        }

        try {
            $Object.$Name = $Value
            return $true
        }
        catch {
            $null = $_
            # Ignore; fall through
        }

        try {
            $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
            return $true
        }
        catch {
            return $false
        }
    }
}
