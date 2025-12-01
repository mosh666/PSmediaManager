<#
Global app configuration
#>

Set-StrictMode -Version Latest

@{
    App = @{
        UI = @{
            Width = 90
            ANSI = @{
                Basic = @{
                    Bold = '[1m'
                    Dim = '[2m'
                    Italic = '[3m'
                    Underline = '[4m'
                    Blink = '[5m'
                    Strikethrough = '[9m'
                }
                # Modern Color Palette - Foreground Colors
                FG = @{
                    # Primary Colors - Deep Ocean Blue theme
                    Primary = '[38;5;33m'    # Deep Ocean Blue - main brand color
                    PrimaryLight = '[38;5;75m'    # Sky Blue - lighter variant
                    PrimaryDark = '[38;5;27m'    # Navy Blue - darker variant

                    # Secondary Colors - Vibrant Purple
                    Secondary = '[38;5;141m'   # Vibrant Purple - creative accent
                    SecondaryLight = '[38;5;183m'  # Light Lavender
                    SecondaryDark = '[38;5;99m'    # Deep Purple

                    # Accent Colors - Bright Cyan
                    Accent = '[38;5;45m'    # Bright Cyan - highlights
                    AccentLight = '[38;5;87m'    # Aqua
                    AccentDark = '[38;5;39m'    # Deep Cyan

                    # Semantic Colors
                    Success = '[38;5;42m'    # Emerald Green - positive actions
                    SuccessLight = '[38;5;48m'    # Light Green
                    Warning = '[38;5;214m'   # Amber - caution
                    WarningLight = '[38;5;220m'   # Light Yellow
                    Error = '[38;5;196m'   # Crimson Red - critical
                    ErrorLight = '[38;5;203m'   # Light Red
                    Info = '[38;5;75m'    # Sky Blue - information
                    InfoLight = '[38;5;117m'   # Pale Blue

                    # Neutral Colors - Refined grayscale
                    Neutral1 = '[38;5;255m'   # Pure White - text on dark
                    Neutral2 = '[38;5;252m'   # Light Gray - secondary text
                    Neutral3 = '[38;5;246m'   # Medium Gray - tertiary text
                    Neutral4 = '[38;5;240m'   # Dark Gray - muted text
                    Neutral5 = '[38;5;235m'   # Charcoal - borders
                    Neutral6 = '[38;5;232m'   # Near Black - backgrounds

                    # Storage-specific Colors
                    MasterDrive = '[38;5;42m'    # Emerald Green - master storage
                    MasterDriveLight = '[38;5;48m' # Light Green - master accents
                    BackupDrive = '[38;5;141m'   # Vibrant Purple - backup storage
                    BackupDriveLight = '[38;5;183m' # Light Lavender - backup accents
                    BackupDriveDark = '[38;5;99m'  # Deep Purple - backup emphasis
                }
                # Modern Color Palette - Background Colors
                BG = @{
                    # Primary Backgrounds
                    Primary = '[48;5;33m'    # Deep Ocean Blue
                    PrimaryLight = '[48;5;75m'    # Sky Blue
                    PrimaryDark = '[48;5;27m'    # Navy Blue

                    # Secondary Backgrounds
                    Secondary = '[48;5;141m'   # Vibrant Purple
                    SecondaryLight = '[48;5;183m'  # Light Lavender
                    SecondaryDark = '[48;5;99m'    # Deep Purple

                    # Accent Backgrounds
                    Accent = '[48;5;45m'    # Bright Cyan
                    AccentLight = '[48;5;87m'    # Aqua
                    AccentDark = '[48;5;39m'    # Deep Cyan

                    # Semantic Backgrounds
                    Success = '[48;5;42m'    # Emerald Green
                    SuccessLight = '[48;5;48m'    # Light Green
                    Warning = '[48;5;214m'   # Amber
                    WarningLight = '[48;5;220m'   # Light Yellow
                    Error = '[48;5;196m'   # Crimson Red
                    ErrorLight = '[48;5;203m'   # Light Red
                    Info = '[48;5;75m'    # Sky Blue
                    InfoLight = '[48;5;117m'   # Pale Blue

                    # Neutral Backgrounds
                    Neutral1 = '[48;5;255m'   # Pure White
                    Neutral2 = '[48;5;252m'   # Light Gray
                    Neutral3 = '[48;5;246m'   # Medium Gray
                    Neutral4 = '[48;5;240m'   # Dark Gray
                    Neutral5 = '[48;5;235m'   # Charcoal
                    Neutral6 = '[48;5;232m'   # Near Black

                    # Storage-specific Background Colors
                    MasterDrive = '[48;5;22m'    # Dark Green - subtle master bg
                    BackupDrive = '[48;5;53m'    # Dark Purple - subtle backup bg
                }
            }
        }
        Logging = @{
            PrintBody = $true
            Append = $true
            Encoding = 'ascii'
            DefaultLevel = 'DEBUG'
            PrintException = $true
            ShortLevel = $false
            OnlyColorizeLevel = $false
            Format = '[%{timestamp:+yyyyMMdd HHmmss.fff}] [%{level:-9}] [%{caller:-29}] %{message} %{body}'
        }
        # Storage configuration is intentionally empty in the repo.
        # On first start, PSmediaManager detects USB and Removable drives and guides you
        # through a wizard to create storage groups. The resulting config is
        # written to <DriveRoot>\PSmm.Config\PSmm.Storage.psd1 and loaded at runtime.
        #
        # Expected schema (persisted on drive):
        # Storage = @{ '<id>' = @{ DisplayName; Master = @{ Label; SerialNumber }; Backup = @{ '<n>' = @{ Label; SerialNumber } } } }
        Storage = @{}
    }
    Projects = @{
        Paths = @{
            Backup = 'Backup'
            Config = 'Config'
            Databases = 'Databases'
            Documents = 'Documents'
            Libraries = 'Libraries'
            Assets = 'Libraries\Assets'
            Log = 'Log'
            Vault = 'Vault'
        }
    }
}
