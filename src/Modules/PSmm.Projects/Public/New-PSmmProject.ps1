#Requires -Version 7.5.4
Set-StrictMode -Version Latest

function New-PSmmProject {
    <#
    .SYNOPSIS
        Creates a new PSmediaManager project with complete directory structure.

    .DESCRIPTION
        Creates a new media project with a standardized directory structure including
        Config, Log, Backup, Databases, Documents, Libraries, and Vault folders.
        Initializes a KeePass database with MariaDB credentials.

    .PARAMETER Config
        Application configuration object (AppConfiguration).
        Preferred modern approach with strongly-typed configuration.


    .PARAMETER FileSystem
        File system service for testing. Defaults to FileSystemService instance.

    .EXAMPLE
        New-PSmmProject -Config $appConfig

    .EXAMPLE
        New-PSmmProject -Config $appConfig

    .NOTES
        This function is interactive and prompts for project name.
        Requires Show-Header, Format-Text, and KeePass functions to be available.
        Creates MariaDB database credentials in the project vault.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [AppConfiguration]$Config,

        [Parameter()]
        [IFileSystemService]$FileSystem = [FileSystemService]::new()
    )

    try {
        Clear-Host
        Show-Header -Config $Config
        Format-Text -Text1 'Create a new project' -Width '80' -Alignment 'c' -ForegroundColor 'DarkGreen' -Border 'Box'

        # Get project name from user
        $pName = Read-Host "`nPlease enter a project name"

        if ([string]::IsNullOrWhiteSpace($pName)) {
            Write-Warning "Project name cannot be empty. Operation cancelled."
            return
        }

        Write-Verbose "Creating new project: $pName"

        # Get storage drive for projects
        $storageDrive = Get-StorageDrive | Where-Object { $_.Label -eq $Config.Storage['1'].Master.Label }
        if (-not $storageDrive) {
            throw "Master storage drive not found. Cannot create project."
        }

        $projectsBasePath = Join-Path -Path "$($storageDrive.DriveLetter)\" -ChildPath 'Projects'
        $projectBasePath = Join-Path -Path $projectsBasePath -ChildPath $pName
        $projectConfigPath = Join-Path -Path $projectBasePath -ChildPath 'Config'

        # Check if project already exists
        if ($FileSystem.TestPath($projectBasePath)) {
            Write-Warning "Project '$pName' already exists at: $projectBasePath"
            return
        }

        # Define directory structure
        $directoriesToCreate = @(
            ''  # Root project directory
            'Config'
            'Log'
            'Backup'
            'Databases'
            'Databases\digiKam'
            'Databases\Resolve Project Library'
            'Databases\PSmediaManager'
            'Databases\PSmediaManager\MariaDB'
            'Databases\PSmediaManager\MariaDB\db_data'
            'Documents'
            'Libraries'
            'Libraries\_IMPORT_'
            'Libraries\Assets'
            'Libraries\Footage'
            'Vault'
        )

        # Create all directories
        Write-Verbose "Creating project directory structure..."
        foreach ($directory in $directoriesToCreate) {
            $fullPath = Join-Path -Path $projectBasePath -ChildPath $directory

            if (-not $FileSystem.TestPath($fullPath)) {
                if ($PSCmdlet.ShouldProcess($fullPath, 'Create directory')) {
                    try {
                        $FileSystem.NewItem($fullPath, 'Directory') | Out-Null
                        Write-Verbose "Created: $fullPath"
                    }
                    catch {
                        Write-Error "Failed to create directory '$fullPath': $_"
                        throw
                    }
                }
            }
        }

        # Copy digiKam configuration
        Write-Verbose "Copying digiKam configuration..."
        try {
            $digiKamConfigSource = $Config.Paths.App.ConfigDigiKam

            if ($FileSystem.TestPath($digiKamConfigSource)) {
                $FileSystem.CopyItem($digiKamConfigSource, $projectConfigPath, $true)
                Write-Verbose "digiKam configuration copied successfully"
            }
            else {
                Write-Warning "digiKam configuration source not found: $digiKamConfigSource"
            }
        }
        catch {
            Write-Warning "Failed to copy digiKam configuration: $_"
        }

        # Initialize KeePass vault
        Write-Output ''
        Write-Verbose "Initializing KeePass database..."
        try {
            $vaultPath = Join-Path -Path $projectBasePath -ChildPath 'Vault'
            $dbName = "$pName.kdbx"

            New-KeePassDatabase -vaultPath $vaultPath -dbName $dbName

            # Prompt for MariaDB credentials entry
            Write-Host "`nPlease enter a secure password for MariaDB root user:" -ForegroundColor Yellow
            Write-Host "Press ENTER without typing to auto-generate a secure password" -ForegroundColor Gray
            $mariaDBPassword = Read-Host "MariaDB Password" -AsSecureString

            # Validate that user entered a password
            if ($mariaDBPassword.Length -eq 0) {
                Write-Host "Generating a secure random password..." -ForegroundColor Yellow

                # Generate a cryptographically secure random password
                $passwordBytes = New-Object byte[] 24
                $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
                $rng.GetBytes($passwordBytes)
                $rng.Dispose()

                # Convert to base64 and take first 20 characters for readability
                $randomPassword = [Convert]::ToBase64String($passwordBytes).Substring(0, 20)

                # Display the generated password to user
                Write-Host "`nGenerated password: " -NoNewline -ForegroundColor Cyan
                Write-Host $randomPassword -ForegroundColor Green
                Write-Host "IMPORTANT: Save this password in a secure location NOW!" -ForegroundColor Red
                Write-Host "Press any key to continue after saving the password..." -ForegroundColor Yellow
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

                # Convert to SecureString securely (from character array to avoid string in memory)
                $securePassword = New-Object System.Security.SecureString
                foreach ($char in $randomPassword.ToCharArray()) {
                    $securePassword.AppendChar($char)
                }
                $securePassword.MakeReadOnly()
                $mariaDBPassword = $securePassword

                # Clear the plain text password from memory
                $randomPassword = $null
                [System.GC]::Collect()
            }

            New-KeePassEntry -vaultPath $vaultPath `
                -dbName $dbName `
                -Title 'MariaDB' `
                -pUserName 'root' `
                -pPassword $mariaDBPassword

            Write-Verbose "KeePass database created with MariaDB credentials"
        }
        catch {
            Write-Warning "Failed to initialize KeePass vault: $_"
        }

        Write-Output ''
        Write-Information "Project '$pName' created successfully at: $projectBasePath" -InformationAction Continue

        # Clear project registry cache to force rescan
        Write-Verbose "Clearing project registry cache to include new project"
        try {
            Clear-PSmmProjectRegistry -Config $Config
            Write-PSmmLog -Level INFO -Context 'New-PSmmProject' `
                -Message "Project '$pName' created, registry cache cleared" -File
        }
        catch {
            Write-Warning "Failed to clear project registry cache: $_"
        }

        # Note: MariaDB database is initialized when digiKam starts for the first time
        # The database credentials are already stored in the project KeePass vault
        # MariaDB itself is managed by Start-PSmmdigiKam / Stop-PSmmdigiKam functions

        Write-Verbose "Project creation complete"
    }
    catch {
        Write-Error "Failed to create project: $_"
        throw
    }
}
