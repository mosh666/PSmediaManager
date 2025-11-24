#Requires -Version 7.5.4
Set-StrictMode -Version Latest

#region ########## PRIVATE ##########
function Protect-ConfigurationData {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Data
    )

    if ($null -eq $Data) {
        return $null
    }

    if ($Data -is [hashtable]) {
        $result = @{}
        foreach ($key in $Data.Keys) {
            if ($key -match '(Token|Password|Secret|ApiKey|Credential|Pwd)') {
                $result[$key] = '********'
            }
            else {
                $result[$key] = Protect-ConfigurationData -Data $Data[$key]
            }
        }
        return $result
    }
    elseif ($Data -is [System.Collections.IEnumerable] -and $Data -isnot [string]) {
        $result = @()
        foreach ($item in $Data) {
            $result += Protect-ConfigurationData -Data $item
        }
        return $result
    }
    elseif ($Data -is [string]) {
        return $Data -replace '(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9]{36,}', '$1****************'
    }
    else {
        return $Data
    }
}

#endregion ########## PRIVATE ##########
