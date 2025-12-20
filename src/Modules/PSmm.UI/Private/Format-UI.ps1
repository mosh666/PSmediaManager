#Requires -Version 7.5.4
Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Formats text with dynamic multicolumn layout, alignment, padding, and optional borders for UI display.

.DESCRIPTION
    This function provides dynamic multicolumn layouts with various alignment options, applies padding,
    and optionally adds borders with customizable colors. Supports ANSI color codes for terminal output
    styling. Text is automatically wrapped to multiple lines if it exceeds the available width, with
    alignment and padding preserved for each line.

    Use the -Columns parameter to define column specifications. Each column can have its own width,
    alignment, padding, colors, and content.

.PARAMETER Width
    The total width of the formatted output. Must be greater than 0.

.PARAMETER Border
    The character to use for borders. Empty string means no border.

.PARAMETER BorderColor
    ANSI color code for the border. Default is a gray color.

.PARAMETER Columns
    Array of column definitions. Each column can be either:
    - A legacy hashtable with the properties below, or
    - A UiColumn instance (recommended) created via New-UiColumn.

    Hashtable columns support the following properties:
    - Text: The content for this column
    - Width: Column width (can be absolute number, percentage like "25%", or "auto")
    - Alignment: 'l', 'c', 'r' (default: 'l')
    - Padding: Padding for this column (default: 1)
    - TextColor: ANSI color code for this column's text
    - BackgroundColor: ANSI background color code for this column (optional)
    - Bold: Apply bold formatting (boolean, default: false)
    - Italic: Apply italic formatting (boolean, default: false)
    - Underline: Apply underline formatting (boolean, default: false)
    - Dim: Apply dim formatting (boolean, default: false)
    - Blink: Apply blink formatting (boolean, default: false)
    - Strikethrough: Apply strikethrough formatting (boolean, default: false)
    - MinWidth: Minimum width for auto-sized columns (default: 10)
    - MaxWidth: Maximum width for auto-sized columns (default: calculated)

.PARAMETER ColumnSeparator
    Character(s) to separate columns. Default is single space.

.PARAMETER ColumnSeparatorColor
    ANSI color code for column separators. If not specified and borders are present,
    automatically inherits the border color for consistent styling.

.EXAMPLE
    $columns = @(
        New-UiColumn -Text 'Name' -Width '25%' -Alignment 'l' -TextColor '[38;5;14m' -BackgroundColor '[48;5;17m' -Bold
        New-UiColumn -Text 'Status' -Width 15 -Alignment 'c' -TextColor '[38;5;10m' -BackgroundColor '[48;5;22m' -Italic
        New-UiColumn -Text 'Description' -Width 'auto' -Alignment 'l' -TextColor '[38;5;15m' -Underline
    )
    Format-UI -Columns $columns -Width 80 -Border '|'
    Creates a 3-column layout with dynamic widths, background colors, and basic ANSI formatting.

.EXAMPLE
    $data = @(
        New-UiColumn -Text 'Item 1' -Width 20
        New-UiColumn -Text 'Value A' -Width 15 -Alignment 'r'
        New-UiColumn -Text 'Long description text' -Width 'auto'
    )
    Format-UI -Columns $data -Width 80 -ColumnSeparator " | "
    Creates columns with custom separator.

.EXAMPLE
    $columns = @(
        New-UiColumn -Text 'Name' -Width 20 -Alignment 'l'
        New-UiColumn -Text 'Value' -Width 15 -Alignment 'r'
    )
    Format-UI -Columns $columns -Width 50 -ColumnSeparator " | " -Border '=' -BorderColor '[38;5;196m'
    Column separators automatically inherit the red border color for consistent styling.

.EXAMPLE
    $columns = @(
        New-UiColumn -Text 'Header' -Width 20 -Bold -Underline
        New-UiColumn -Text 'Data' -Width 20 -Italic
    )
    Format-UI -Columns $columns -Width 50 -Config $Config
    Uses $Config.UI.ANSI.Basic formatting codes for bold, underline, and italic text.
#>

Set-StrictMode -Version Latest

#region ########## PRIVATE ##########

function _TryGetConfigValue {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    if ($Object -is [System.Collections.IDictionary]) {
        try { if ($Object.ContainsKey($Name)) { return $Object[$Name] } } catch { }
        try { if ($Object.Contains($Name)) { return $Object[$Name] } } catch { }
        try {
            foreach ($k in $Object.Keys) {
                if ($k -eq $Name) { return $Object[$k] }
            }
        }
        catch { }
        return $null
    }

    $p = $Object.PSObject.Properties[$Name]
    if ($null -ne $p) { return $p.Value }
    return $null
}

function _TryGetNestedValue {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()]$Root,
        [Parameter(Mandatory)][string[]]$PathParts
    )

    $cur = $Root
    foreach ($part in $PathParts) {
        if ($null -eq $cur) { return $null }
        $cur = _TryGetConfigValue -Object $cur -Name $part
    }
    return $cur
}

function New-UiColumn {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter()]
        [string]$Text = '',

        [Parameter()]
        [object]$Width = 'auto',

        [Parameter()]
        [ValidateSet('l', 'c', 'r')]
        [string]$Alignment = 'l',

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Padding = 1,

        [Parameter()]
        [string]$TextColor = $null,

        [Parameter()]
        [string]$BackgroundColor = $null,

        [Parameter()]
        [switch]$Bold,

        [Parameter()]
        [switch]$Italic,

        [Parameter()]
        [switch]$Underline,

        [Parameter()]
        [switch]$Dim,

        [Parameter()]
        [switch]$Blink,

        [Parameter()]
        [switch]$Strikethrough,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MinWidth = 10,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxWidth = 0
    )

    $uiColumnType = 'UiColumn' -as [type]
    if (-not $uiColumnType) {
        $psmmManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\\..\\PSmm\\PSmm.psd1'
        if (Test-Path -LiteralPath $psmmManifestPath) {
            try {
                Import-Module -Name $psmmManifestPath -Force -ErrorAction Stop | Out-Null
            }
            catch {
                # ignore - handled below
            }
        }
        $uiColumnType = 'UiColumn' -as [type]
    }

    if (-not $uiColumnType) {
        throw 'Unable to resolve type [UiColumn].'
    }

    $col = $uiColumnType::new()
    $col.Text = $Text
    $col.Width = $Width
    $col.Alignment = $Alignment
    $col.Padding = $Padding
    $col.TextColor = $TextColor
    $col.BackgroundColor = $BackgroundColor
    $col.Bold = $Bold.IsPresent
    $col.Italic = $Italic.IsPresent
    $col.Underline = $Underline.IsPresent
    $col.Dim = $Dim.IsPresent
    $col.Blink = $Blink.IsPresent
    $col.Strikethrough = $Strikethrough.IsPresent
    $col.MinWidth = $MinWidth
    $col.MaxWidth = $MaxWidth
    return $col
}

function New-UiKeyValueItem {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter()]
        [object]$Value = $null,

        [Parameter()]
        [string]$Color = $null
    )

    $uiKeyValueItemType = 'UiKeyValueItem' -as [type]
    if (-not $uiKeyValueItemType) {
        $psmmManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\\..\\PSmm\\PSmm.psd1'
        if (Test-Path -LiteralPath $psmmManifestPath) {
            try {
                Import-Module -Name $psmmManifestPath -Force -ErrorAction Stop | Out-Null
            }
            catch {
                # ignore - handled below
            }
        }
        $uiKeyValueItemType = 'UiKeyValueItem' -as [type]
    }

    if (-not $uiKeyValueItemType) {
        throw 'Unable to resolve type [UiKeyValueItem].'
    }

    return $uiKeyValueItemType::new($Key, $Value, $Color)
}

function Format-UI {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Width,

        [Parameter()]
        [string]$Border = '',

        [Parameter()]
        [string]$BorderColor = '[38;5;75m',

        [Parameter(Mandatory)]
        [object[]]$Columns,

        [Parameter()]
        [string]$ColumnSeparator = ' ',

        [Parameter()]
        [string]$ColumnSeparatorColor = '[38;5;75m',

        [Parameter()]
        [object]$Config = $null
    )

    begin {
        # Safely derive column count; support single hashtable or null
        $colCount = if ($null -eq $Columns) { 0 } elseif ($Columns -is [array]) { $Columns.Count } else { 1 }
        $uiWidth = _TryGetNestedValue -Root $Config -PathParts @('UI', 'Width')
        $configWidth = if ($null -ne $uiWidth) { $uiWidth } else { 'N/A' }
        Write-Verbose ("[Format-UI] BEGIN (WidthParam={0}, ConfigWidth={1}, Columns={2})" -f ($PSBoundParameters['Width']), $configWidth, $colCount)
        # Define constants
        $BORDER_WIDTH = 2  # Border adds 1 char on left + 1 on right
        $ESCAPE_CHAR = [char]0x1b
        $NEWLINE = "`n"

        # Set default width from $Config.UI.Width if not explicitly provided
        if ($PSBoundParameters.ContainsKey('Width') -eq $false) {
            $resolvedWidth = $null
            if ($null -ne $uiWidth) {
                try { $resolvedWidth = [int]$uiWidth } catch { $resolvedWidth = $null }
            }

            # Fallback to 80 if Config UI.Width is not available/valid
            if ($null -ne $resolvedWidth -and $resolvedWidth -gt 0) {
                $Width = $resolvedWidth
            }
            else {
                $Width = 80
            }
        }
    }

    process {
        Write-Verbose "[Format-UI] Calculating layout..."

        # Normalize columns: accept legacy hashtables and UiColumn objects.
        $columnsForEngine = @()
        foreach ($column in @($Columns)) {
            if ($null -eq $column) {
                continue
            }

            if ($column -is [hashtable]) {
                $columnsForEngine += $column
                continue
            }

            if ($column.PSObject.TypeNames -contains 'UiColumn') {
                $columnsForEngine += $column.ToHashtable()
                continue
            }

            $typeName = $column.GetType().FullName
            throw "Unsupported column definition type: $typeName. Expected hashtable or UiColumn."
        }

        # Calculate effective width based on border presence
        $hasBorder = -not [string]::IsNullOrEmpty($Border)
        $contentWidth = if ($hasBorder) { $Width - $BORDER_WIDTH } else { $Width }

        # Auto-inherit border color for column separators when borders are present
        # and no explicit column separator color was provided (i.e., using default)
        $effectiveColumnSeparatorColor = $ColumnSeparatorColor
        if ($hasBorder -and $ColumnSeparatorColor -eq '[38;5;75m') {
            $effectiveColumnSeparatorColor = $BorderColor
        }

        Write-Verbose ("[Format-UI] Border={0} ContentWidth={1}" -f $hasBorder, $contentWidth)

        # Process multicolumn layout
        $allFormattedLines = ConvertTo-MultiColumnLines -Columns $columnsForEngine -Width $contentWidth `
            -ColumnSeparator $ColumnSeparator -ColumnSeparatorColor $effectiveColumnSeparatorColor `
            -EscapeChar $ESCAPE_CHAR -Config $Config

        $lineCount = if ($null -eq $allFormattedLines) { 0 } elseif ($allFormattedLines -is [array]) { $allFormattedLines.Count } else { 1 }
        Write-Verbose ("[Format-UI] Generated {0} lines" -f $lineCount)

        if ($lineCount -eq 0) {
            Write-Verbose '[Format-UI] No lines generated (columns or widths may be invalid)'
        }
        else {
            $sampleCount = [Math]::Min($lineCount - 1, 4)

            for ($i = 0; $i -le $sampleCount; $i++) {
                $visible = $allFormattedLines[$i] -replace '\x1b\[[0-9;]*m', ''
                Write-Verbose ("[Format-UI] Line[{0}] VisibleLen={1} Text='{2}'" -f $i, $visible.Length, ($visible.Trim()))
            }
        }

        # Apply border if specified
        $output = if ($hasBorder) {
            Format-WithBorder -Lines $allFormattedLines -Width $Width -ContentWidth $contentWidth `
                -Border $Border -BorderColor $BorderColor -EscapeChar $ESCAPE_CHAR -Newline $NEWLINE
        }
        else {
            # Join all lines without border
            ($allFormattedLines -join $NEWLINE)
        }

        # Write output directly to host to ensure visibility
        Write-PSmmHost $output

        if ([string]::IsNullOrWhiteSpace(($output -replace '\x1b\[[0-9;]*m', '').Trim())) {
            Write-Verbose '[Format-UI] Output appears empty after stripping ANSI sequences.'
        }

        Write-Verbose "[Format-UI] END"
    }
}

function ConvertTo-MultiColumnLines {
    <#
    .SYNOPSIS
        Processes multiple columns with dynamic width calculation and formatting.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function converts content to multiple lines')]
    param (
        [hashtable[]]$Columns,
        [int]$Width,
        [string]$ColumnSeparator,
        [string]$ColumnSeparatorColor,
        [char]$EscapeChar,
        [object]$Config = $null
    )

    # Validate and normalize column definitions
    $normalizedColumns = Initialize-ColumnDefinitions -Columns $Columns

    # Calculate column widths
    $columnWidths = Get-ColumnWidths -Columns $normalizedColumns -TotalWidth $Width `
        -ColumnSeparator $ColumnSeparator

    # Process each column's content into lines
    $columnContentLines = @()
    $maxLines = 0

    for ($i = 0; $i -lt $normalizedColumns.Count; $i++) {
        $column = $normalizedColumns[$i]
        $columnWidth = $columnWidths[$i]

        # Split text by explicit newlines first
        $textLines = if ([string]::IsNullOrEmpty($column.Text)) { @('') } else { $column.Text -split "`r?`n" }

        # Process each line for this column
        $processedLines = [System.Collections.Generic.List[string]]::new()

        foreach ($textLine in $textLines) {
            $wrappedLines = Split-TextIntoLines -Text $textLine -MaxWidth ($columnWidth - ($column.Padding * 2))

            foreach ($wrappedLine in $wrappedLines) {
                $alignedLine = Format-ColumnText -Text $wrappedLine -Width $columnWidth `
                    -Alignment $column.Alignment -Padding $column.Padding `
                    -TextColor $column.TextColor -BackgroundColor $column.BackgroundColor `
                    -Bold $column.Bold -Italic $column.Italic -Underline $column.Underline `
                    -Dim $column.Dim -Blink $column.Blink -Strikethrough $column.Strikethrough `
                    -Config $Config -EscapeChar $EscapeChar
                $processedLines.Add($alignedLine)
            }
        }

        $columnContentLines += , $processedLines.ToArray()
        $maxLines = [Math]::Max($maxLines, $processedLines.Count)
    }

    # Combine all columns into final lines
    return Join-ColumnLines -ColumnContentLines $columnContentLines -MaxLines $maxLines `
        -ColumnSeparator $ColumnSeparator -ColumnSeparatorColor $ColumnSeparatorColor `
        -EscapeChar $EscapeChar -ColumnWidths $columnWidths
}

function Initialize-ColumnDefinitions {
    <#
    .SYNOPSIS
        Validates and normalizes column definitions with default values.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function initializes multiple column definitions')]
    param (
        [hashtable[]]$Columns
    )

    $normalized = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($column in $Columns) {
        $normalizedColumn = @{
            Text = if ($column.ContainsKey('Text')) { [string]$column.Text } else { '' }
            Width = if ($column.ContainsKey('Width')) { $column.Width } else { 'auto' }
            Alignment = if ($column.ContainsKey('Alignment')) { $column.Alignment } else { 'l' }
            Padding = if ($column.ContainsKey('Padding')) { [int]$column.Padding } else { 1 }
            TextColor = if ($column.ContainsKey('TextColor')) { $column.TextColor } else { '[38;5;255m' }
            BackgroundColor = if ($column.ContainsKey('BackgroundColor')) { $column.BackgroundColor } else { '' }
            Bold = if ($column.ContainsKey('Bold')) { [bool]$column.Bold } else { $false }
            Italic = if ($column.ContainsKey('Italic')) { [bool]$column.Italic } else { $false }
            Underline = if ($column.ContainsKey('Underline')) { [bool]$column.Underline } else { $false }
            Dim = if ($column.ContainsKey('Dim')) { [bool]$column.Dim } else { $false }
            Blink = if ($column.ContainsKey('Blink')) { [bool]$column.Blink } else { $false }
            Strikethrough = if ($column.ContainsKey('Strikethrough')) { [bool]$column.Strikethrough } else { $false }
            MinWidth = if ($column.ContainsKey('MinWidth')) { [int]$column.MinWidth } else { 10 }
            MaxWidth = if ($column.ContainsKey('MaxWidth')) { [int]$column.MaxWidth } else { 0 } # 0 = no limit
        }

        # Validate alignment
        if ($normalizedColumn.Alignment -notin @('l', 'c', 'r')) {
            $normalizedColumn.Alignment = 'l'
        }

        $normalized.Add($normalizedColumn)
    }

    return , $normalized.ToArray()
}

function Get-ColumnWidths {
    <#
    .SYNOPSIS
        Calculates actual column widths based on specifications and available space.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function calculates multiple column widths')]
    param (
        [hashtable[]]$Columns,
        [int]$TotalWidth,
        [string]$ColumnSeparator
    )

    # Calculate separator space
    $separatorWidth = if ($Columns.Count -gt 1) {
        Get-VisibleLength -Text $ColumnSeparator
    }
    else {
        0
    }
    $totalSeparatorSpace = $separatorWidth * ($Columns.Count - 1)

    # Available width for columns (excluding separators)
    # Note: TotalWidth is already the content width (borders already subtracted if present)
    $availableWidth = $TotalWidth - $totalSeparatorSpace

    # Separate fixed, percentage, and auto columns
    $fixedColumns = @()
    $percentageColumns = @()
    $autoColumns = @()
    $fixedTotalWidth = 0
    $percentageTotalWidth = 0

    for ($i = 0; $i -lt $Columns.Count; $i++) {
        $width = $Columns[$i].Width

        if ($width -is [int] -or ($width -is [string] -and $width -match '^\d+$')) {
            # Fixed width
            $fixedWidth = [int]$width
            $fixedColumns += @{ Index = $i; Width = $fixedWidth }
            $fixedTotalWidth += $fixedWidth
        }
        elseif ($width -is [string] -and $width -match '^(\d+(?:\.\d+)?)%$') {
            # Percentage width
            $percentage = [double]$Matches[1] / 100
            $percentageColumns += @{ Index = $i; Percentage = $percentage }
            $percentageTotalWidth += $percentage
        }
        else {
            # Auto width
            $autoColumns += @{ Index = $i; Column = $Columns[$i] }
        }
    }

    # Calculate percentage widths
    $percentageActualWidth = 0
    foreach ($percCol in $percentageColumns) {
        $width = [Math]::Floor($availableWidth * $percCol.Percentage)
        $percCol.Width = $width
        $percentageActualWidth += $width
    }

    # Calculate remaining width for auto columns
    $remainingWidth = $availableWidth - $fixedTotalWidth - $percentageActualWidth
    $autoColumnWidth = if ($autoColumns.Count -gt 0) {
        [Math]::Max(10, [Math]::Floor($remainingWidth / $autoColumns.Count))
    }
    else {
        0
    }

    # Build final width array
    $finalWidths = @(0) * $Columns.Count

    foreach ($fixedCol in $fixedColumns) {
        $finalWidths[$fixedCol.Index] = $fixedCol.Width
    }

    foreach ($percCol in $percentageColumns) {
        $finalWidths[$percCol.Index] = $percCol.Width
    }

    foreach ($autoCol in $autoColumns) {
        $width = [Math]::Max($autoCol.Column.MinWidth, $autoColumnWidth)
        if ($autoCol.Column.MaxWidth -gt 0) {
            $width = [Math]::Min($width, $autoCol.Column.MaxWidth)
        }
        $finalWidths[$autoCol.Index] = $width
    }

    return $finalWidths
}

function Format-ColumnText {
    <#
    .SYNOPSIS
        Formats text within a single column with specified alignment, padding, colors, and basic ANSI formatting.
    #>
    param (
        [string]$Text,
        [int]$Width,
        [string]$Alignment,
        [int]$Padding,
        [string]$TextColor,
        [string]$BackgroundColor = '',
        [bool]$Bold = $false,
        [bool]$Italic = $false,
        [bool]$Underline = $false,
        [bool]$Dim = $false,
        [bool]$Blink = $false,
        [bool]$Strikethrough = $false,
        [object]$Config = $null,
        [char]$EscapeChar
    )

    # Build ANSI color and formatting codes
    $ansiCodes = @()

    $ansiBasic = if ($Config) { _TryGetNestedValue -Root $Config -PathParts @('UI', 'ANSI', 'Basic') } else { $null }

    # Add basic formatting codes
    if ($Bold -and $null -ne $ansiBasic) {
        $boldCode = _TryGetConfigValue -Object $ansiBasic -Name 'Bold'
        if (-not [string]::IsNullOrEmpty($boldCode)) { $ansiCodes += ([string]$boldCode).TrimStart('[').TrimEnd('m') }
    }
    if ($Italic -and $null -ne $ansiBasic) {
        $italicCode = _TryGetConfigValue -Object $ansiBasic -Name 'Italic'
        if (-not [string]::IsNullOrEmpty($italicCode)) { $ansiCodes += ([string]$italicCode).TrimStart('[').TrimEnd('m') }
    }
    if ($Underline -and $null -ne $ansiBasic) {
        $underlineCode = _TryGetConfigValue -Object $ansiBasic -Name 'Underline'
        if (-not [string]::IsNullOrEmpty($underlineCode)) { $ansiCodes += ([string]$underlineCode).TrimStart('[').TrimEnd('m') }
    }
    if ($Dim -and $null -ne $ansiBasic) {
        $dimCode = _TryGetConfigValue -Object $ansiBasic -Name 'Dim'
        if (-not [string]::IsNullOrEmpty($dimCode)) { $ansiCodes += ([string]$dimCode).TrimStart('[').TrimEnd('m') }
    }
    if ($Blink -and $null -ne $ansiBasic) {
        $blinkCode = _TryGetConfigValue -Object $ansiBasic -Name 'Blink'
        if (-not [string]::IsNullOrEmpty($blinkCode)) { $ansiCodes += ([string]$blinkCode).TrimStart('[').TrimEnd('m') }
    }
    if ($Strikethrough -and $null -ne $ansiBasic) {
        $strikeCode = _TryGetConfigValue -Object $ansiBasic -Name 'Strikethrough'
        if (-not [string]::IsNullOrEmpty($strikeCode)) { $ansiCodes += ([string]$strikeCode).TrimStart('[').TrimEnd('m') }
    }

    # Add color codes
    if (-not [string]::IsNullOrEmpty($TextColor)) {
        $ansiCodes += $TextColor.TrimStart('[').TrimEnd('m')
    }
    if (-not [string]::IsNullOrEmpty($BackgroundColor)) {
        $ansiCodes += $BackgroundColor.TrimStart('[').TrimEnd('m')
    }

    $ansiPrefix = if ($ansiCodes.Count -gt 0) {
        "$EscapeChar[" + ($ansiCodes -join ';') + 'm'
    } else {
        ''
    }
    $ansiReset = "$EscapeChar[0m"

    # Apply colors to text and create formatted output
    $coloredText = if (-not [string]::IsNullOrEmpty($ansiPrefix)) { "$ansiPrefix$Text$ansiReset" } else { $Text }

    $availableWidth = $Width - ($Padding * 2)
    $textLength = $Text.Length

    if (-not [string]::IsNullOrEmpty($BackgroundColor)) {
        # When background color is specified, apply it to the entire column width including padding and fill spaces
        $backgroundOnlyPrefix = "$EscapeChar$BackgroundColor"

        switch ($Alignment) {
            'l' {
                # Left align: background + padding + text + fill + padding + background_reset
                $paddingSpaces = ' ' * $Padding
                $fillSpaces = ' ' * ($availableWidth - $textLength)
                $formatted = "$backgroundOnlyPrefix$paddingSpaces$ansiReset$coloredText$backgroundOnlyPrefix$fillSpaces$paddingSpaces$ansiReset"
            }
            'c' {
                # Center align
                $totalFillSpace = $availableWidth - $textLength
                $leftFill = [Math]::Floor($totalFillSpace / 2.0)
                $rightFill = $totalFillSpace - $leftFill
                $paddingSpaces = ' ' * $Padding
                $leftFillSpaces = ' ' * $leftFill
                $rightFillSpaces = ' ' * $rightFill
                $formatted = "$backgroundOnlyPrefix$paddingSpaces$leftFillSpaces$ansiReset$coloredText$backgroundOnlyPrefix$rightFillSpaces$paddingSpaces$ansiReset"
            }
            'r' {
                # Right align: background + padding + fill + text + padding + background_reset
                $paddingSpaces = ' ' * $Padding
                $fillSpaces = ' ' * ($availableWidth - $textLength)
                $formatted = "$backgroundOnlyPrefix$paddingSpaces$fillSpaces$ansiReset$coloredText$backgroundOnlyPrefix$paddingSpaces$ansiReset"
            }
            default {
                # Default to left align
                $paddingSpaces = ' ' * $Padding
                $fillSpaces = ' ' * ($availableWidth - $textLength)
                $formatted = "$backgroundOnlyPrefix$paddingSpaces$ansiReset$coloredText$backgroundOnlyPrefix$fillSpaces$paddingSpaces$ansiReset"
            }
        }
    } else {
        # No background color, use regular spacing
        switch ($Alignment) {
            'l' {
                # Left align: padding + text + fill + padding
                $formatted = (' ' * $Padding) + $coloredText + (' ' * ($availableWidth - $textLength)) + (' ' * $Padding)
            }
            'c' {
                # Center align
                $totalFillSpace = $availableWidth - $textLength
                $leftFill = [Math]::Floor($totalFillSpace / 2.0)
                $rightFill = $totalFillSpace - $leftFill
                $formatted = (' ' * $Padding) + (' ' * $leftFill) + $coloredText + (' ' * $rightFill) + (' ' * $Padding)
            }
            'r' {
                # Right align: padding + fill + text + padding
                $formatted = (' ' * $Padding) + (' ' * ($availableWidth - $textLength)) + $coloredText + (' ' * $Padding)
            }
            default {
                # Default to left align
                $formatted = (' ' * $Padding) + $coloredText + (' ' * ($availableWidth - $textLength)) + (' ' * $Padding)
            }
        }
    }

    return $formatted
}

function Join-ColumnLines {
    <#
    .SYNOPSIS
        Combines individual column lines into complete formatted lines.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function joins multiple column lines')]
    param (
        [array]$ColumnContentLines,
        [int]$MaxLines,
        [string]$ColumnSeparator,
        [string]$ColumnSeparatorColor,
        [char]$EscapeChar,
        [int[]]$ColumnWidths
    )

    $result = [System.Collections.Generic.List[string]]::new($MaxLines)
    $ansiSeparatorPrefix = "$EscapeChar$ColumnSeparatorColor"
    $ansiReset = "$EscapeChar[0m"
    $coloredSeparator = if ([string]::IsNullOrEmpty($ColumnSeparatorColor)) {
        $ColumnSeparator
    }
    else {
        "$ansiSeparatorPrefix$ColumnSeparator$ansiReset"
    }

    for ($lineIndex = 0; $lineIndex -lt $MaxLines; $lineIndex++) {
        $lineParts = [System.Collections.Generic.List[string]]::new($ColumnContentLines.Count)

        for ($colIndex = 0; $colIndex -lt $ColumnContentLines.Count; $colIndex++) {
            $columnLines = $ColumnContentLines[$colIndex]

            if ($lineIndex -lt $columnLines.Count) {
                $lineParts.Add($columnLines[$lineIndex])
            }
            else {
                # Create empty line for this column
                $emptyLine = ' ' * $ColumnWidths[$colIndex]
                $lineParts.Add($emptyLine)
            }
        }

        # Join columns with separator
        $completeLine = $lineParts -join $coloredSeparator
        $result.Add($completeLine)
    }

    return $result.ToArray()
}

function Format-WithBorder {
    <#
    .SYNOPSIS
        Applies borders to formatted lines.
    #>
    param (
        [string[]]$Lines,
        [int]$Width,
        [int]$ContentWidth,
        [string]$Border,
        [string]$BorderColor,
        [char]$EscapeChar,
        [string]$Newline
    )

    # Build border manually to ensure correct width
    $borderChar = [string]$Border[0]
    $horizontalBorder = $borderChar * $Width
    $ansiPrefix = "$EscapeChar$BorderColor"
    $ansiReset = "$EscapeChar[0m"

    $result = [System.Collections.Generic.List[string]]::new($Lines.Count + 2)
    $result.Add("$ansiPrefix$horizontalBorder$ansiReset")

    foreach ($line in $Lines) {
        # Normalize line to exact contentWidth (accounting for ANSI codes)
        $normalizedLine = Get-NormalizedWidth -Text $line -Width $ContentWidth
        # Add borders on both sides
        $result.Add("$ansiPrefix$borderChar$ansiReset$normalizedLine$ansiPrefix$borderChar$ansiReset")
    }

    $result.Add("$ansiPrefix$horizontalBorder$ansiReset")

    return ($result -join $Newline)
}

function Get-VisibleLength {
    <#
    .SYNOPSIS
        Gets the visible length of text excluding ANSI escape codes.
    #>
    param (
        [string]$Text
    )

    # Remove ANSI escape sequences to get visible length
    $textWithoutAnsi = $Text -replace '\x1b\[[0-9;]*m', ''
    return $textWithoutAnsi.Length
}

function Get-NormalizedWidth {
    <#
    .SYNOPSIS
        Ensures text is exactly the specified width by padding or trimming (accounting for ANSI codes).
    #>
    param (
        [string]$Text,
        [int]$Width
    )

    $visibleLength = Get-VisibleLength -Text $Text

    if ($visibleLength -eq $Width) {
        return $Text
    }
    elseif ($visibleLength -lt $Width) {
        # Add padding at the end
        return $Text + (' ' * ($Width - $visibleLength))
    }
    else {
        # This shouldn't happen if our logic is correct, but handle it
        # We need to trim considering ANSI codes
        $textWithoutAnsi = $Text -replace '\x1b\[[0-9;]*m', ''
        return $textWithoutAnsi.Substring(0, $Width)
    }
}

function Split-TextIntoLines {
    <#
    .SYNOPSIS
        Splits text into lines that fit within a specified width.
    .DESCRIPTION
        Splits text using either word-based wrapping (respecting word boundaries) or
        character-based wrapping (splitting at exact character position).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Function splits text into multiple lines')]
    param (
        [string]$Text,
        [int]$MaxWidth
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return @('')
    }

    $Text = $Text.Trim()
    if ($Text.Length -le $MaxWidth) {
        return @($Text)
    }

    $lines = [System.Collections.Generic.List[string]]::new()

    # Character-based wrapping - splits at exact position
    for ($i = 0; $i -lt $Text.Length; $i += $MaxWidth) {
        $chunkLength = [Math]::Min($MaxWidth, $Text.Length - $i)
        $lines.Add($Text.Substring($i, $chunkLength))
    }

    return $lines.ToArray()
}

function New-ColumnDefinition {
    <#
    .SYNOPSIS
        Creates a properly formatted column definition hashtable for use with Format-UI.
    .DESCRIPTION
        Helper function to create column definitions with proper validation and defaults.
        This ensures consistent column structure and helps prevent common configuration errors.
    .PARAMETER Text
        The content for this column.
    .PARAMETER Width
        Column width specification. Can be:
        - Integer: Fixed width in characters
        - String with %: Percentage of total width (e.g., "25%")
        - "auto": Automatically calculated based on remaining space
    .PARAMETER Alignment
        Text alignment within the column: 'l' (left), 'c' (center), 'r' (right)
    .PARAMETER Padding
        Internal padding for the column content.
    .PARAMETER TextColor
        ANSI color code for the column text.
    .PARAMETER BackgroundColor
        ANSI background color code for the column.
    .PARAMETER Bold
        Apply bold formatting to the column text.
    .PARAMETER Italic
        Apply italic formatting to the column text.
    .PARAMETER Underline
        Apply underline formatting to the column text.
    .PARAMETER Dim
        Apply dim formatting to the column text.
    .PARAMETER Blink
        Apply blink formatting to the column text.
    .PARAMETER Strikethrough
        Apply strikethrough formatting to the column text.
    .PARAMETER MinWidth
        Minimum width for auto-sized columns.
    .PARAMETER MaxWidth
        Maximum width for auto-sized columns (0 = no limit).
    .EXAMPLE
        $col = New-ColumnDefinition -Text "Header" -Width "25%" -Alignment 'c' -TextColor '[38;5;226m' -BackgroundColor '[48;5;17m' -Bold
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This function creates and returns a hashtable configuration object without modifying system state')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter()]
        [string]$Text = '',

        [Parameter()]
        [object]$Width = 'auto',

        [Parameter()]
        [ValidateSet('l', 'c', 'r')]
        [string]$Alignment = 'l',

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Padding = 1,

        [Parameter()]
        [string]$TextColor = '[38;5;255m',

        [Parameter()]
        [string]$BackgroundColor = '',

        [Parameter()]
        [switch]$Bold,

        [Parameter()]
        [switch]$Italic,

        [Parameter()]
        [switch]$Underline,

        [Parameter()]
        [switch]$Dim,

        [Parameter()]
        [switch]$Blink,

        [Parameter()]
        [switch]$Strikethrough,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MinWidth = 10,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxWidth = 0
    )

    return @{
        Text = $Text
        Width = $Width
        Alignment = $Alignment
        Padding = $Padding
        TextColor = $TextColor
        BackgroundColor = $BackgroundColor
        Bold = $Bold.IsPresent
        Italic = $Italic.IsPresent
        Underline = $Underline.IsPresent
        Dim = $Dim.IsPresent
        Blink = $Blink.IsPresent
        Strikethrough = $Strikethrough.IsPresent
        MinWidth = $MinWidth
        MaxWidth = $MaxWidth
    }
}

#endregion ########## PRIVATE ##########
