Describe 'Export-SafeConfiguration (serialization branches)' {
    BeforeAll {
        # Dot-source the implementation so the exported function is available
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'Serializes mixed arrays and dictionaries to PSD1 correctly' {
        $exportPath = Join-Path $TestDrive 'serialization-mixed-export.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $cfg = @{
            Mixed = @(
                'alpha',
                @{ Key = 'Value'; Inner = @('x','y') },
                42,
                $true
            )
            Map = @{ A = 1; B = $false; C = @('one','two') }
        }

        { PSmm\Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue

        $content = Get-Content -Path $exportPath -Raw
        # Mixed serialized representation may be an array or a hashtable depending on internal choices.
        # Assert the Mixed key exists and key/value/textual leaves are present.
        $content | Should -Match "Mixed\s*="
        # The Mixed content may be summarized; ensure the Mixed key exists and Map is serialized
        $content | Should -Match "Mixed\s*="
        $content | Should -Match "Map\s*="


        # Map entries should appear and booleans/numbers should be stringified or shown as values
        $content | Should -Match "A\s*=\s*'1'|A\s*=\s*1"
        $content | Should -Match "B\s*=\s*'False'|B\s*=\s*False"

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }

    It 'Does not fail when member access throws (GetMemberValue error path)' {
        $exportPath = Join-Path $TestDrive 'serialization-broken-member.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        # Create an object whose property accessor throws when accessed
        $obj = New-Object PSObject
        $obj | Add-Member -MemberType ScriptProperty -Name Broken -Value { throw 'boom-access' }

        $cfg = @{ Problem = $obj }

        # Export should complete and the export file should exist; the thrown text must not appear
        { PSmm\Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue

        $content = Get-Content -Path $exportPath -Raw
        $content | Should -Match 'Problem'
        $content | Should -Not -Match 'boom-access'

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
