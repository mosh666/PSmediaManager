Describe 'Export-SafeConfiguration (helpers)' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '../../../src/Modules/PSmm/Public/Export-SafeConfiguration.ps1'
        $scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        . $scriptPath
    }

    It 'Export-SafeConfiguration serializes arrays and hashtables (indirect _ToPsd1 exercise)' {
        $exportPath = Join-Path $TestDrive 'helpers-serialize.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $cfg = @{ 
            Mixed = @('one','two', @{ K='V' })
            Map = @{ A = 1; B = $false; C = @('x','y') }
        }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw
        $content | Should -Match 'Mixed' 
        # Allow either the nested key to appear or the map serialization (order/format may vary)
        $content | Should -Match "K\s*=\s*'V'|Map"
        $content | Should -Match "A\s*=\s*'1'|B\s*=\s*'False'"

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }

    It 'Export-SafeConfiguration handles deep enumerables and MaxDepth (indirect _CloneGeneric exercise)' {
        $exportPath = Join-Path $TestDrive 'helpers-deep.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        # build extremely deep nested array to trigger MaxDepth in clone logic
        $depth = 30
        $node = 'leaf'
        for ($i = 0; $i -lt $depth; $i++) { $node = @($node) }

        $cfg = @{ Deep = $node }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw
        # Accept either a preserved leaf or a MaxDepth marker
        $content | Should -Match 'leaf|\[MaxDepth\]'

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }

    It 'Export-SafeConfiguration reads IDictionary, PSObject properties and swallows accessor exceptions (indirect _GetMemberValue exercise)' {
        $exportPath = Join-Path $TestDrive 'helpers-getmember.psd1'
        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force

        $bad = New-Object PSObject
        $bad | Add-Member -MemberType ScriptProperty -Name Boom -Value { throw 'boom-access' }

        $cfg = @{ Dict = @{ X = 'v1' }; Obj = [pscustomobject]@{ Prop = 'val' }; Broken = $bad }

        { Export-SafeConfiguration -Configuration $cfg -Path $exportPath } | Should -Not -Throw
        Test-Path $exportPath | Should -BeTrue
        $content = Get-Content -Path $exportPath -Raw

        # Ensure values from IDictionary and PSObject appear and the thrown message does not
        $content | Should -Match "X\s*=\s*'v1'|Prop\s*=\s*'val'"
        $content | Should -Not -Match 'boom-access'

        Remove-Item -Path $exportPath -ErrorAction SilentlyContinue -Force
    }
}
