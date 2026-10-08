<#
    Parallel downloads.

    While one app installs, the next ones are already downloading
    ("winget download", which also checks each file's hash). Installs
    themselves still run one at a time, because Windows installers break
    when several run at once.

    Every download comes with winget's description of the installer
    (type, silent switches, success codes), which Install-FromDownload
    uses to run it. Anything unusual returns $false so the caller falls
    back to a normal "winget install".
#>

$script:Downloads = @{
    Root     = Join-Path $env:TEMP 'WindowsSetup-downloads'
    Max      = 3                                             # downloads at the same time
    Pending  = New-Object System.Collections.Generic.Queue[object]
    Running  = @{}                                           # Id -> process
    Done     = @{}                                           # Id -> folder, or $null if it failed
}

# Silent switches winget uses for each installer type when the app doesn't specify its own
$script:DefaultSilentArgs = @{
    msi      = '/quiet /norestart'
    wix      = '/quiet /norestart'
    burn     = '/quiet /norestart'
    inno     = '/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
    nullsoft = '/S'
}

function Start-DownloadQueue {
    param([object[]]$Packages)
    New-Item -ItemType Directory -Force -Path $script:Downloads.Root | Out-Null
    foreach ($p in $Packages) { $script:Downloads.Pending.Enqueue($p) }
    Write-Log "Download queue: $($Packages.Count) package(s)"
    Step-DownloadQueue
}

function Step-DownloadQueue {
    <#
        Collects finished downloads and starts new ones. Called often (every
        half second while something installs), so it must stay quick.
    #>
    $d = $script:Downloads
    foreach ($id in @($d.Running.Keys)) {
        $proc = $d.Running[$id]
        if (-not $proc.HasExited) { continue }
        $folder = Join-Path $d.Root $id
        $ok = $proc.ExitCode -eq 0 -and (Get-ChildItem $folder -Filter *.yaml -ErrorAction SilentlyContinue)
        $d.Done[$id] = if ($ok) { $folder } else { $null }
        Write-Log "  download $id finished (exit $($proc.ExitCode))"
        $d.Running.Remove($id)
    }
    while ($d.Running.Count -lt $d.Max -and $d.Pending.Count -gt 0) {
        $p = $d.Pending.Dequeue()
        $folder = Join-Path $d.Root $p.Id
        $downloadArgs = @('download', '--id', $p.Id, '--exact', '--source', 'winget', '--download-directory', "`"$folder`"",
                          '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        try {
            $proc = Start-Process -FilePath (Get-WingetPath) -ArgumentList $downloadArgs -NoNewWindow -PassThru `
                        -RedirectStandardOutput "$folder.out.txt" -RedirectStandardError "$folder.err.txt"
            $null = $proc.Handle   # keeps the exit code available
            $d.Running[$p.Id] = $proc
        } catch {
            Write-Log "  download $($p.Id) could not start: $($_.Exception.Message)"
            $d.Done[$p.Id] = $null
        }
    }
}

function Wait-Download {
    # Returns the download folder for this package, or $null (not queued or failed)
    param([string]$Id, [string]$Name)
    $d = $script:Downloads
    if (-not $d.Done.ContainsKey($Id) -and -not $d.Running.ContainsKey($Id) -and -not ($d.Pending | Where-Object Id -eq $Id)) {
        return $null
    }
    if (-not $d.Done.ContainsKey($Id)) { Write-Pending $Name 'downloading...' }
    while (-not $d.Done.ContainsKey($Id)) {
        Start-Sleep -Milliseconds 300
        Step-DownloadQueue
    }
    $d.Done[$Id]
}

function Wait-ProcessWhileDownloading {
    # Waits for a process (with a time limit) while keeping the download queue moving
    param($Process, [int]$TimeoutMinutes = 20)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while (-not $Process.WaitForExit(500)) {
        Step-DownloadQueue
        if ((Get-Date) -gt $deadline) {
            $Process | Stop-Process -Force -ErrorAction SilentlyContinue
            throw "took longer than $TimeoutMinutes minutes"
        }
    }
    Step-DownloadQueue
}

function Stop-DownloadQueue {
    $d = $script:Downloads
    $d.Pending.Clear()
    foreach ($proc in $d.Running.Values) { $proc | Stop-Process -Force -ErrorAction SilentlyContinue }
    $d.Running.Clear()
}

# ------------------------------------------------------------------
#  Reading winget's installer description (a small YAML file)
# ------------------------------------------------------------------

function ConvertFrom-YamlScalar {
    param([string]$Text)
    $t = $Text.Trim()
    if ($t -match "^'(.*)'$") { return $Matches[1] -replace "''", "'" }
    if ($t -match '^"(.*)"$') { return $Matches[1] -replace '\\"', '"' -replace '\\\\', '\' }
    $t
}

function Read-InstallerManifest {
    <#
        Reads only the fields we need from the downloaded manifest. It is a
        deliberately small reader for winget's own, very regular YAML; if
        something looks unexpected the caller simply falls back to winget.
    #>
    param([string]$Path)

    $info = @{
        InstallerType = $null; NestedInstallerType = $null; Scope = $null; ElevationRequirement = $null
        Switches = @{}; SuccessCodes = @(0); OkCodes = @(); RetryCodes = @(); HasDependencies = $false
    }
    $section = $null
    $lastCode = $null
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^Installers:') { $section = 'installer'; continue }
        if ($null -eq $section) { continue }
        if ($line -match '^[A-Za-z]') { break }   # next top-level key: end of the Installers block

        # List items inside the success / expected code lists
        if ($section -eq 'success' -and $line -match '^  -\s*(-?\d+)\s*$') {
            $info.SuccessCodes += [int64]$Matches[1]; continue
        }
        if ($section -eq 'expected' -and $line -match '^  -\s*InstallerReturnCode:\s*(-?\d+)') {
            $lastCode = [int64]$Matches[1]; continue
        }

        if ($line -match '^  (InstallerType|NestedInstallerType|Scope|ElevationRequirement):\s*(.+)$') {
            $info[$Matches[1]] = ConvertFrom-YamlScalar $Matches[2]; $section = 'installer'
        } elseif ($line -match '^  Dependencies:') {
            $info.HasDependencies = $true; $section = 'installer'
        } elseif ($line -match '^  InstallerSwitches:') {
            $section = 'switches'
        } elseif ($line -match '^  InstallerSuccessCodes:') {
            $section = 'success'
        } elseif ($line -match '^  ExpectedReturnCodes:') {
            $section = 'expected'
        } elseif ($line -match '^  \S') {
            $section = 'installer'
        } elseif ($section -eq 'switches' -and $line -match '^    (\w+):\s*(.*)$') {
            $info.Switches[$Matches[1]] = ConvertFrom-YamlScalar $Matches[2]
        } elseif ($section -eq 'expected' -and $line -match '^    ReturnResponse:\s*(\w+)') {
            switch ($Matches[1]) {
                { $_ -in 'alreadyInstalled', 'rebootRequiredToFinish', 'rebootRequiredForInstall', 'rebootInitiated' } { $info.OkCodes += $lastCode }
                { $_ -in 'installInProgress', 'packageInUse' } { $info.RetryCodes += $lastCode }
            }
        }
    }
    $info
}

# ------------------------------------------------------------------
#  Running a downloaded installer
# ------------------------------------------------------------------

function Install-FromDownload {
    <#
        Runs the downloaded installer silently. Returns $true when it
        succeeded, $false when the caller should use "winget install".
    #>
    param($Package, [string]$Folder)

    $manifestFile = Get-ChildItem $Folder -Filter *.yaml | Select-Object -First 1
    $installer    = Get-ChildItem $Folder -File | Where-Object { $_.Extension -ne '.yaml' } | Select-Object -First 1
    if (-not $manifestFile -or -not $installer) { Write-Log "  $($Package.Id): download incomplete"; return $false }

    try { $m = Read-InstallerManifest $manifestFile.FullName }
    catch { Write-Log "  $($Package.Id): couldn't read manifest: $($_.Exception.Message)"; return $false }

    $type = $m.InstallerType
    if ($m.HasDependencies -or $m.NestedInstallerType -or $type -notin 'msi', 'wix', 'burn', 'inno', 'nullsoft', 'exe', 'msix', 'appx') {
        Write-Log "  $($Package.Id): type '$type' (dependencies: $($m.HasDependencies)) - using winget install instead"
        return $false
    }

    $file = $installer.FullName
    if ($type -in 'msix', 'appx') {
        Write-Pending $Package.Name 'installing...'
        try { Add-AppxPackage -Path $file -ErrorAction Stop; return $true }
        catch { Write-Log "  $($Package.Id): Add-AppxPackage failed: $($_.Exception.Message)"; return $false }
    }

    # Build the silent command line the same way winget does
    $silent = if ($m.Switches.Silent) { $m.Switches.Silent } else { $script:DefaultSilentArgs[$type] }
    if (-not $silent) { Write-Log "  $($Package.Id): no silent switch known - using winget install instead"; return $false }
    $switches = @($silent, $m.Switches.Custom)
    if ($Package.Location) {
        if (-not $m.Switches.InstallLocation) { return $false }
        $switches += $m.Switches.InstallLocation -replace '<INSTALLPATH>', $Package.Location
    }
    $switchText = ($switches | Where-Object { $_ }) -join ' '

    if ($type -in 'msi', 'wix') { $exe = 'msiexec.exe'; $arguments = "/i `"$file`" $switchText" }
    else                        { $exe = $file;         $arguments = $switchText }

    $asUser = $Package.AsUser -or $m.ElevationRequirement -eq 'elevationProhibited'
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Write-Pending $Package.Name $(if ($attempt -eq 1) { 'installing...' } else { 'retrying...' })
        Write-Log "  run: $exe $arguments$(if ($asUser) { '  (as normal user)' })"
        if ($asUser) {
            $code = Invoke-AsStandardUser -Command "`"$exe`" $arguments"
        } else {
            $proc = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -WindowStyle Hidden
            $null = $proc.Handle
            Wait-ProcessWhileDownloading $proc
            $code = $proc.ExitCode
        }
        Write-Log "  installer exit code: $code"
        if ($code -in $m.SuccessCodes -or $code -in $m.OkCodes) { return $true }
        if ($type -in 'msi', 'wix', 'burn' -and $code -in 3010, 1641) { return $true }   # success, restart needed
        if ($code -notin ($m.RetryCodes + 1618)) { break }                            # 1618 = another install running
        Start-Sleep -Seconds 10
    }
    $false
}
