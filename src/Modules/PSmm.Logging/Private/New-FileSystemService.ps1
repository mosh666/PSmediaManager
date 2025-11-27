#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function New-FileSystemService {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'FileSystemService type may be unavailable when modules load in isolation.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType('FileSystemService')]
    [OutputType([pscustomobject])]
    param()

    if (-not $PSCmdlet.ShouldProcess('File system service provider', 'Create new instance')) {
        return
    }

    try {
        $null = [FileSystemService]
        return [FileSystemService]::new()
    }
    catch {
        Write-Verbose 'FileSystemService type unavailable, using native cmdlet wrapper'

        $wrapper = [pscustomobject]@{}

        $wrapper = $wrapper | Add-Member -MemberType ScriptMethod -Name TestPath -Value {
            param([string]$path)
            if ([string]::IsNullOrWhiteSpace($path)) {
                return $false
            }
            return Test-Path -Path $path -ErrorAction SilentlyContinue
        } -PassThru

        $wrapper = $wrapper | Add-Member -MemberType ScriptMethod -Name NewItem -Value {
            param([string]$path, [string]$itemType)
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw "Path cannot be empty"
            }
            if ([string]::IsNullOrWhiteSpace($itemType)) {
                throw "ItemType cannot be empty"
            }
            $null = New-Item -Path $path -ItemType $itemType -Force -ErrorAction Stop
        } -PassThru

        $wrapper = $wrapper | Add-Member -MemberType ScriptMethod -Name GetChildItem -Value {
            param([string]$path, [string]$filter, [string]$itemType)
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw "Path cannot be empty"
            }

            $params = @{ Path = $path; ErrorAction = 'SilentlyContinue' }
            if (-not [string]::IsNullOrWhiteSpace($filter)) {
                $params['Filter'] = $filter
            }

            $items = Get-ChildItem @params

            if (-not [string]::IsNullOrWhiteSpace($itemType)) {
                switch ($itemType.ToLower()) {
                    'directory' { $items = $items | Where-Object { $_.PSIsContainer } }
                    'file' { $items = $items | Where-Object { -not $_.PSIsContainer } }
                }
            }

            return @($items)
        } -PassThru

        $wrapper = $wrapper | Add-Member -MemberType ScriptMethod -Name RemoveItem -Value {
            param([string]$path, [bool]$recurse)
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw "Path cannot be empty"
            }
            if (-not (Test-Path -Path $path -ErrorAction SilentlyContinue)) {
                return
            }

            $params = @{ Path = $path; Force = $true; ErrorAction = 'Stop' }
            if ($recurse) { $params['Recurse'] = $true }
            Remove-Item @params
        } -PassThru

        $wrapper = $wrapper | Add-Member -MemberType ScriptMethod -Name SetContent -Value {
            param([string]$path, [string]$content)
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw "Path cannot be empty"
            }

            $directory = Split-Path -Path $path -Parent
            if (-not (Test-Path -Path $directory -ErrorAction SilentlyContinue)) {
                $null = New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop
            }

            Set-Content -Path $path -Value $content -Force -ErrorAction Stop
        } -PassThru

        return $wrapper
    }
}
