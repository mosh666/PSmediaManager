#Requires -Version 7.5.4
Set-StrictMode -Version Latest

Describe 'Logging service-first policy' {
    BeforeAll {
        $script:repoRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent
        $modulesRoot = Join-Path -Path $script:repoRoot -ChildPath 'src\Modules'

        # Import PSmm first so class-based types referenced by logging are available.
        $psmmManifest = Join-Path -Path (Join-Path -Path $modulesRoot -ChildPath 'PSmm') -ChildPath 'PSmm.psd1'
        Import-Module -Name $psmmManifest -Force -Global -ErrorAction Stop

        $psmmLoggingManifest = Join-Path -Path (Join-Path -Path $modulesRoot -ChildPath 'PSmm.Logging') -ChildPath 'PSmm.Logging.psd1'
        Import-Module -Name $psmmLoggingManifest -Force -Global -ErrorAction Stop
    }

    It 'Initialize-Logging requires -FileSystem' {
        $cmd = Get-Command -Name Initialize-Logging -ErrorAction Stop
        $param = $cmd.Parameters['FileSystem']

        $paramAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1
        $paramAttr | Should -Not -BeNullOrEmpty
        $paramAttr.Mandatory | Should -BeTrue
    }

    It 'Invoke-LogRotation requires -FileSystem' {
        $cmd = Get-Command -Name Invoke-LogRotation -ErrorAction Stop
        $param = $cmd.Parameters['FileSystem']

        $paramAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1
        $paramAttr | Should -Not -BeNullOrEmpty
        $paramAttr.Mandatory | Should -BeTrue
    }
}
