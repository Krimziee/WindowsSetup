<#
    Checks and preparation that run before anything else:
    internet, winget (installed and up to date) and a restore point.
#>

function Test-Internet {
    try {
        $response = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8
        $response.Content -eq 'Microsoft Connect Test'
    } catch { $false }
}

function Get-WingetVersion {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { return $null }
    try {
        $text = (& $winget.Source --version 2>$null | Out-String).Trim()
        if ($text -match 'v?(\d+\.\d+\.\d+)') { [version]$Matches[1] } else { $null }
    } catch { $null }
}

function Get-LatestWingetRelease {
    # Official winget releases are published by Microsoft on GitHub
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing -TimeoutSec 20
    $bundle  = $release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1
    $deps    = $release.assets | Where-Object { $_.name -like '*Dependencies*.zip' } | Select-Object -First 1
    [pscustomobject]@{
        Version     = [version]($release.tag_name -replace '^v', '')
        BundleUrl   = $bundle.browser_download_url
        DepsZipUrl  = $deps.browser_download_url
    }
}

function Install-WingetBundle {
    param($Release)

    $work = Join-Path $env:TEMP 'WindowsSetup-winget'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $bundlePath = Join-Path $work 'AppInstaller.msixbundle'
    Invoke-WebRequest -Uri $Release.BundleUrl -OutFile $bundlePath -UseBasicParsing

    try {
        Add-AppxPackage -Path $bundlePath -ForceApplicationShutdown -ErrorAction Stop
        return
    } catch {
        Write-Log "winget install without dependencies failed: $($_.Exception.Message)"
        if (-not $Release.DepsZipUrl) { throw }
    }

    # Second try: include the dependency packages that ship with the release
    $zipPath = Join-Path $work 'deps.zip'
    Invoke-WebRequest -Uri $Release.DepsZipUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath (Join-Path $work 'deps') -Force
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $depFiles = Get-ChildItem (Join-Path $work 'deps') -Recurse -Include *.appx, *.msix |
                Where-Object { $_.FullName -match "\\$arch\\" -or $_.Name -match "_$arch" } |
                Select-Object -ExpandProperty FullName
    Add-AppxPackage -Path $bundlePath -DependencyPath $depFiles -ForceApplicationShutdown -ErrorAction Stop
}

function Update-Winget {
    $current = Get-WingetVersion

    if (-not $current) {
        # On some fresh installs winget exists but isn't registered yet
        try {
            Invoke-Change 'register winget' {
                Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
            }
            $current = Get-WingetVersion
        } catch { Write-Log "winget register failed: $($_.Exception.Message)" }
    }

    try {
        $latest = Get-LatestWingetRelease
    } catch {
        Write-Log "Could not check latest winget: $($_.Exception.Message)"
        if ($current) { Write-Item 'winget' "v$current (couldn't check for updates)" 'Warn' }
        else          { Write-Item 'winget' 'Not available - apps can''t be installed' 'Fail' }
        return [bool]$current
    }

    if ($current -and $current -ge $latest.Version) {
        Write-Item 'winget' "v$current (up to date)" 'Ok'
        return $true
    }

    $from = if ($current) { "v$current" } else { 'not installed' }
    try {
        Invoke-Change "update winget $from -> v$($latest.Version)" { Install-WingetBundle $latest }
        if ($script:Setup.DryRun) {
            Write-Item 'winget' "$from -> v$($latest.Version)" 'Ok'
            return $true
        }
        $now = Get-WingetVersion
        if ($now -and $now -ge $latest.Version) {
            Write-Item 'winget' "Updated $from -> v$now" 'Ok'
            return $true
        }
        throw "version is still $now"
    } catch {
        Write-Log "winget update failed: $($_.Exception.Message)"
        if ($current) {
            Write-Item 'winget' "Couldn't update, using $from" 'Warn'
            return $true
        }
        Write-Item 'winget' 'Not available - apps can''t be installed' 'Fail'
        return $false
    }
}

function New-SafetyRestorePoint {
    try {
        Invoke-Change 'create a System Restore point' {
            $drive = "$env:SystemDrive\"
            Enable-ComputerRestore -Drive $drive -ErrorAction Stop
            # Windows normally allows only one restore point per 24 hours
            Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
            Checkpoint-Computer -Description 'Before Windows Setup' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        }
        Write-Item 'Restore point' 'Created ("Before Windows Setup")' 'Ok'
    } catch {
        Write-Log "Restore point failed: $($_.Exception.Message)"
        Write-Item 'Restore point' 'Couldn''t create one, continuing anyway' 'Warn'
    }
}
