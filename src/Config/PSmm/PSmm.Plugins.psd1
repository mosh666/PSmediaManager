<#
.SYNOPSIS
    PSmm plugin manifest (global defaults)
#>

Set-StrictMode -Version Latest

@{
    Plugins = @{
        a_Essentials = @{
            SevenZip = @{
                Mandatory = $true
                Enabled   = $true
                Source = 'GitHub'
                Repo = 'ip7z/7zip'
                AssetPattern = '7z*-x64.exe'
                CommandPath = ''
                Command = '7z.exe'
                Name = '7z'
                RegisterToPath = $true
            }
        }
        b_GitEnv = @{
            Git = @{
                Mandatory = $true
                Enabled   = $true
                Source = 'GitHub'
                Repo = 'git-for-windows/git'
                AssetPattern = 'PortableGit*-64-bit.7z.exe'
                CommandPath = 'cmd'
                Command = 'git.exe'
                Name = 'PortableGit'
                RegisterToPath = $true
            }
            GitVersion = @{
                Mandatory = $true
                Enabled   = $true
                Source = 'GitHub'
                Repo = 'GitTools/GitVersion'
                AssetPattern = 'gitversion-win-x64-*.zip'
                CommandPath = ''
                Command = 'gitversion.exe'
                Name = 'gitversion'
                RegisterToPath = $true
            }
            GitLFS = @{
                Mandatory = $true
                Enabled   = $true
                Source = 'GitHub'
                Repo = 'git-lfs/git-lfs'
                AssetPattern = 'git-lfs-windows-amd64-*.zip'
                CommandPath = ''
                Command = 'git-lfs.exe'
                Name = 'git-lfs'
                RegisterToPath = $true
            }
        }
        c_Misc = @{
            ExifTool = @{
                Mandatory = $true
                Enabled   = $true
                Source = 'Url'
                BaseUri = 'https://exiftool.org'
                VersionUrl = 'https://exiftool.org/ver.txt'
                CommandPath = ''
                Command = 'exiftool.exe'
                Name = 'exiftool'
                RegisterToPath = $true
            }
            FFmpeg = @{
                Mandatory = $false
                Enabled   = $false
                Source = 'Url'
                BaseUri = 'https://www.gyan.dev'
                VersionUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full.7z'
                CommandPath = 'bin'
                Command = 'ffmpeg.exe'
                Name = 'ffmpeg'
                RegisterToPath = $true
            }
            ImageMagick = @{
                Mandatory = $false
                Enabled   = $false
                Source = 'Url'
                BaseUri = 'https://download.imagemagick.org/ImageMagick/download/binaries'
                VersionUrl = 'https://imagemagick.org/script/download.php#windows'
                CommandPath = ''
                Command = 'magick.exe'
                Name = 'ImageMagick'
                AssetPattern = 'ImageMagick-(?<ver>\d+(?:\.\d+){2}-\d+)-portable-Q16-HDRI-x64\.7z'
                RegisterToPath = $true
            }
            KeePassXC = @{
                Mandatory = $true
                Enabled   = $true
                Source = 'GitHub'
                Repo = 'keepassxreboot/keepassxc'
                AssetPattern = 'KeePassXC-*-Win64.zip'
                CommandPath = ''
                Command = 'keepassxc-cli.exe'
                Name = 'KeePassXC'
                RegisterToPath = $true
            }
            MKVToolNix = @{
                Mandatory = $false
                Enabled   = $false
                Source = 'Url'
                BaseUri = 'https://mkvtoolnix.download'
                VersionUrl = 'https://mkvtoolnix.download/windows/releases/'
                CommandPath = ''
                Command = 'mkvmerge.exe'
                Name = 'mkvtoolnix'
                RegisterToPath = $true
            }
        }
        d_Database = @{
            MariaDB = @{
                Mandatory = $true
                Enabled   = $true
                Source = 'Url'
                BaseUri = 'https://downloads.mariadb.org'
                VersionUrl = 'https://downloads.mariadb.org/rest-api/mariadb/'
                CommandPath = 'bin'
                Command = 'mysql.exe'
                Name = 'mariadb'
                RegisterToPath = $true
            }
        }
        e_Management = @{
            digiKam = @{
                Mandatory = $true
                Enabled   = $true
                Source = 'Url'
                BaseUri = 'https://download.kde.org'
                VersionUrl = 'https://download.kde.org/stable/digikam/'
                CommandPath = ''
                Command = 'digikam.exe'
                Name = 'digiKam'
                RegisterToPath = $true
            }
        }
    }
}
