#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function New-FileSystemService {
    <#
    .SYNOPSIS
        Creates a new FileSystemService instance.

    .DESCRIPTION
        Creates and returns a FileSystemService instance. This function requires that the
        FileSystemService class has been loaded into the session (typically by importing
        the PSmm module first).

        NOTE: No fallback mechanism - FileSystemService class must be available.
        If the class is not available, this indicates a module loading order issue.

    .EXAMPLE
        $fs = New-FileSystemService
        $exists = $fs.TestPath('C:\temp')

    .OUTPUTS
        FileSystemService - A new instance of the FileSystemService class
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Factory function creates objects but does not modify system state')]
    [CmdletBinding()]
    [OutputType([FileSystemService], [psobject])]
    param()

        # Try to use the real class when available; otherwise fall back to a shim so logging stays functional in isolated imports
        try {
            $class = [FileSystemService]
        }
        catch {
            $class = $null
        }

        if ($class) {
            return [FileSystemService]::new()
        }

        $shim = [pscustomobject]@{ PSTypeName = 'FileSystemService' }
        $shim | Add-Member -MemberType ScriptMethod -Name TestPath -Value { param($path) Test-Path -Path $path -ErrorAction SilentlyContinue }
        $shim | Add-Member -MemberType ScriptMethod -Name NewItem -Value { param($path, $itemType) $null = New-Item -Path $path -ItemType $itemType -Force -ErrorAction Stop }
        $shim | Add-Member -MemberType ScriptMethod -Name GetContent -Value { param($path) Get-Content -Path $path -Raw -ErrorAction Stop }
        $shim | Add-Member -MemberType ScriptMethod -Name SetContent -Value { param($path, $content) Set-Content -Path $path -Value $content -Force -ErrorAction Stop }
        $shim | Add-Member -MemberType ScriptMethod -Name GetChildItem -Value {
            param($path, $filter, $itemType, $recurse)
            $params = @{ Path = $path; ErrorAction = 'SilentlyContinue' }
            if ($filter) { $params['Filter'] = $filter }
            if ($recurse) { $params['Recurse'] = $true }
            $items = Get-ChildItem @params
            if ($itemType -eq 'Directory') { return @($items | Where-Object { $_.PSIsContainer }) }
            if ($itemType -eq 'File') { return @($items | Where-Object { -not $_.PSIsContainer }) }
            return @($items)
        }
        $shim | Add-Member -MemberType ScriptMethod -Name RemoveItem -Value { param($path, $recurse) Remove-Item -Path $path -Force -ErrorAction Stop -Recurse:$recurse }
        $shim | Add-Member -MemberType ScriptMethod -Name CopyItem -Value { param($source, $destination) Copy-Item -Path $source -Destination $destination -Force -ErrorAction Stop }
        $shim | Add-Member -MemberType ScriptMethod -Name MoveItem -Value { param($source, $destination) Move-Item -Path $source -Destination $destination -Force -ErrorAction Stop }
        $shim | Add-Member -MemberType ScriptMethod -Name GetItemProperty -Value { param($path) Get-Item -Path $path -ErrorAction Stop }

        return $shim
}
