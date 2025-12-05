<#
.SYNOPSIS
    PSmm requirements
#>

Set-StrictMode -Version Latest

@{
    PowerShell = @{
        VersionMinimum = '7.5.4'
        Modules = @(
            @{Name = '7Zip4PowerShell'; Repository = 'PSGallery' },
            @{Name = 'Pester'; Repository = 'PSGallery' },
            @{Name = 'PSLogs'; Repository = 'PSGallery' },
            @{Name = 'PSScriptAnalyzer'; Repository = 'PSGallery' },
            @{Name = 'PSScriptTools'; Repository = 'PSGallery' }
        )
    }
    Plugins = @{
        a_Essentials = @{
            SevenZip = @{
                Source = 'GitHub'
                Repo = 'ip7z/7zip'
                AssetPattern = '7z*-x64.exe'
                CommandPath = ''
                Command = '7z.exe'
                Name = '7z'
                RegisterToPath = $false
            }
        }
        b_GitEnv = @{
            Git = @{
                Source = 'GitHub'
                Repo = 'git-for-windows/git'
                AssetPattern = 'PortableGit*-64-bit.7z.exe'
                CommandPath = 'cmd'
                Command = 'git.exe'
                Name = 'PortableGit'
                RegisterToPath = $true
            }
            GitVersion = @{
                Source = 'GitHub'
                Repo = 'GitTools/GitVersion'
                AssetPattern = 'gitversion-win-x64-*.zip'
                CommandPath = ''
                Command = 'gitversion.exe'
                Name = 'gitversion'
                RegisterToPath = $true
            }
            GitLFS = @{
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
                Source = 'Url'
                BaseUri = 'https://exiftool.org'
                VersionUrl = 'https://exiftool.org/ver.txt'
                CommandPath = ''
                Command = 'exiftool.exe'
                Name = 'exiftool'
                RegisterToPath = $false
            }
            FFmpeg = @{
                Source = 'Url'
                BaseUri = 'https://www.gyan.dev'
                VersionUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full.7z'
                CommandPath = 'bin'
                Command = 'ffmpeg.exe'
                Name = 'ffmpeg'
                RegisterToPath = $false
            }
            ImageMagick = @{
                Source = 'Url'
                BaseUri = 'https://download.imagemagick.org/ImageMagick/download/binaries'
                VersionUrl = 'https://imagemagick.org/script/download.php#windows'
                CommandPath = ''
                Command = 'magick.exe'
                Name = 'ImageMagick'
                AssetPattern = 'ImageMagick-(?<ver>\d+(?:\.\d+){2}-\d+)-portable-Q16-HDRI-x64\.7z'
                RegisterToPath = $false
            }
            KeePassXC = @{
                Source = 'GitHub'
                Repo = 'keepassxreboot/keepassxc'
                AssetPattern = 'KeePassXC-*-Win64.zip'
                CommandPath = ''
                Command = 'keepassxc-cli.exe'
                Name = 'KeePassXC'
                RegisterToPath = $true
            }
            MKVToolNix = @{
                Source = 'Url'
                BaseUri = 'https://mkvtoolnix.download'
                VersionUrl = 'https://mkvtoolnix.download/windows/releases/'
                CommandPath = ''
                Command = 'mkvmerge.exe'
                Name = 'mkvtoolnix'
                RegisterToPath = $false
            }
        }
        d_Database = @{
            MariaDB = @{
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
