<#
    Installs game redistributables and apps with winget, the package
    manager built into Windows. winget always downloads the latest version
    from the publisher's official source.
#>

$script:WingetCodes = @{
    AlreadyInstalled = -1978335135   # 0x8A150061
    NoUpgrade        = -1978335189   # 0x8A15002B  no newer version available
    TechMismatch     = -1978335090   # 0x8A15008E  update uses a different installer type
    RebootRequired   = -1978334967   # 0x8A150109
}

function Get-WingetPath {
    (Get-Command winget.exe -ErrorAction Stop).Source
}

function Write-ToolOutputToLog {
    # winget prints progress bars; only keep lines with real words
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    Get-Content $Path -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '[A-Za-z]{3}' -and $_ -notmatch '^\s*[-\\|/]\s*$' } |
        Select-Object -Last 15 |
        ForEach-Object { Write-Log "    | $($_.Trim())" }
}

function Invoke-Winget {
    <#
        Runs winget with a time limit and returns its exit code.
        -AsUser runs it WITHOUT admin rights, for apps whose installer
        refuses to run as admin (Spotify, for example).
    #>
    param(
        [string[]]$Arguments,
        [switch]$AsUser,
        [int]$TimeoutMinutes = 20
    )
    $winget  = Get-WingetPath
    $outFile = Join-Path $env:TEMP ("WindowsSetup-winget-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    Write-Log "  winget $($Arguments -join ' ')$(if ($AsUser) { '  (as normal user)' })"

    try {
        if (-not $AsUser) {
            $proc = Start-Process -FilePath $winget -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput $outFile
            # Touching .Handle makes .NET keep the exit code; without it ExitCode can come back empty
            $null = $proc.Handle
            Wait-ProcessWhileDownloading $proc $TimeoutMinutes
            return $proc.ExitCode
        }
        return Invoke-AsStandardUser -Command "`"$winget`" $($Arguments -join ' ') > `"$outFile`" 2>&1" -TimeoutMinutes $TimeoutMinutes
    }
    finally {
        Write-ToolOutputToLog $outFile
        Remove-Item $outFile -ErrorAction SilentlyContinue
    }
}

function Invoke-AsStandardUser {
    <#
        Runs a command as the signed-in user without admin rights, using a
        one-time scheduled task (the simplest reliable way to "drop" admin
        rights from an elevated script). Returns the command's exit code.
    #>
    param([string]$Command, [int]$TimeoutMinutes = 20)

    $user = (Get-CimInstance Win32_ComputerSystem).UserName
    if (-not $user) { throw 'no signed-in user found' }
    $taskName = 'WindowsSetup-RunAsUser'

    # The extra outer quotes are needed because cmd strips the first and last quote
    $action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$Command`""
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes $TimeoutMinutes) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    try {
        Start-ScheduledTask -TaskName $taskName
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        Start-Sleep -Seconds 2
        while ((Get-ScheduledTask -TaskName $taskName).State -in 'Running', 'Queued') {
            if ((Get-Date) -gt $deadline) { throw "took longer than $TimeoutMinutes minutes" }
            Start-Sleep -Seconds 1
            Step-DownloadQueue
        }
        # The task reports the exit code as an unsigned number; winget's codes are negative
        $result = [uint32](Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult
        [BitConverter]::ToInt32([BitConverter]::GetBytes($result), 0)
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Test-WingetInstalled {
    param([string]$Id)
    $code = Invoke-Winget -Arguments @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity') -TimeoutMinutes 3
    $code -eq 0
}

# Id -> installed version, filled once by Update-InstalledSnapshot.
# $null means the snapshot failed and each app is checked on its own instead.
$script:WingetInstalled = $null

function Update-InstalledSnapshot {
    <#
        Asks winget ONCE for everything installed (much faster than asking
        about each app separately). "winget export" writes it as a JSON file.
    #>
    $file = Join-Path $env:TEMP 'WindowsSetup-installed.json'
    try {
        Remove-Item $file -ErrorAction SilentlyContinue
        $code = Invoke-Winget -Arguments @('export', '--output', "`"$file`"", '--source', 'winget', '--include-versions',
                                           '--accept-source-agreements', '--disable-interactivity') -TimeoutMinutes 5
        if (-not (Test-Path $file)) { throw "winget export failed with code $code" }

        $installed = @{}
        foreach ($source in (Get-Content $file -Raw | ConvertFrom-Json).Sources) {
            foreach ($pkg in $source.Packages) { $installed[$pkg.PackageIdentifier] = "$($pkg.Version)" }
        }
        $script:WingetInstalled = $installed
        Write-Log "Installed-apps snapshot: $($installed.Count) packages"
    } catch {
        $script:WingetInstalled = $null
        Write-Log "Snapshot failed, checking apps one by one: $($_.Exception.Message)"
    } finally {
        Remove-Item $file -ErrorAction SilentlyContinue
    }
}

function Get-InstalledVersion {
    # Returns the installed version, 'unknown' if installed without a known version, or $null if not installed
    param([string]$Id)
    if ($null -ne $script:WingetInstalled) {
        if ($script:WingetInstalled.ContainsKey($Id)) {
            $v = $script:WingetInstalled[$Id]
            if ($v) { return $v } else { return 'unknown' }
        }
        return $null
    }
    if (Test-WingetInstalled $Id) { 'unknown' } else { $null }
}

function Update-WingetPackage {
    <# Brings an already-installed app up to the latest version. #>
    param($Package, [string]$CurrentVersion)

    $name  = $Package.Name
    $shown = if ($CurrentVersion -ne 'unknown') { " ($CurrentVersion)" } else { '' }

    if ($script:Setup.DryRun) {
        Write-Log "[dry run] would check $name for updates"
        Write-Item $name "Installed$shown, would check for updates" 'Skip'
        return
    }

    Write-Pending $name 'checking for updates...'
    Write-Log "Doing: update $name ($($Package.Id)) from $CurrentVersion"
    $upgradeArgs = @('upgrade', '--id', $Package.Id, '--exact', '--source', 'winget', '--silent',
                     '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    try {
        $code = Invoke-Winget -Arguments $upgradeArgs -AsUser:([bool]$Package.AsUser)
    } catch {
        Write-Log "  $name - $($_.Exception.Message)"
        $code = $null
    }
    Write-Log "  $name update exit code: $code"

    switch ($code) {
        0                                    { Write-Item $name "Updated$(if ($shown) { " (was $CurrentVersion)" })" 'Ok' }
        $script:WingetCodes.RebootRequired   { Write-Item $name 'Updated (needs a restart)' 'Ok' }
        $script:WingetCodes.NoUpgrade        { Write-Item $name "Up to date$shown" 'Skip' }
        $script:WingetCodes.TechMismatch     { Write-Item $name 'Installed (update it from inside the app)' 'Skip' }
        default {
            $hex = if ($null -ne $code) { '0x{0:X8}' -f $code } else { 'no response' }
            Write-Item $name "Installed, but update failed ($hex)" 'Warn'
        }
    }
}

function Install-StoreApp {
    <#
        Installs an app from the Microsoft Store through winget. Store apps
        can't be downloaded ahead of time, and the Store keeps them up to
        date by itself, so this is simpler than the normal path.
    #>
    param($Package)
    $name = $Package.Name
    if (Test-WingetInstalled $Package.Id) {
        Write-Item $name 'Already installed (the Store keeps it updated)' 'Skip'
        return
    }
    if ($script:Setup.DryRun) {
        Write-Log "[dry run] would install $name ($($Package.Id)) from the Microsoft Store"
        Write-Item $name 'Installed' 'Ok'
        return
    }
    Write-Pending $name 'installing from the Store...'
    Write-Log "Doing: install $name ($($Package.Id)) from the Microsoft Store"
    $storeArgs = @('install', '--id', $Package.Id, '--exact', '--source', 'msstore', '--silent',
                   '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    $code = Invoke-Winget -Arguments $storeArgs
    Write-Log "  $name exit code: $code"
    if ($code -in 0, $script:WingetCodes.AlreadyInstalled -or (Test-WingetInstalled $Package.Id)) {
        Write-Item $name 'Installed' 'Ok'
    } else {
        Write-Item $name ("Failed (winget error 0x{0:X8})" -f $code) 'Fail'
    }
}

function Install-WingetPackage {
    param($Package)   # @{ Id; Name; AsUser; Location; Source }

    $name  = $Package.Name
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        if ($Package.Source -eq 'msstore') {
            Install-StoreApp $Package
            return
        }
        $current = Get-InstalledVersion $Package.Id
        if ($current) {
            Update-WingetPackage $Package $current
            return
        }
        if ($script:Setup.DryRun) {
            Write-Log "[dry run] would install $name ($($Package.Id))"
            Write-Item $name 'Installed' 'Ok'
            return
        }

        # Fast path: the installer was already downloaded in the background
        $folder = Wait-Download $Package.Id $name
        if ($folder) {
            Write-Log "Doing: install $name ($($Package.Id)) from download"
            $ok = $false
            try { $ok = Install-FromDownload $Package $folder }
            catch { Write-Log "  $name - $($_.Exception.Message)" }
            finally { Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue }
            if ($ok) {
                Write-Item $name 'Installed' 'Ok'
                return
            }
            Write-Log "  $name - falling back to winget install"
        }

        $installArgs = @('install', '--id', $Package.Id, '--exact', '--source', 'winget', '--silent',
                         '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        if ($Package.Location) {
            # Quoted by hand: Windows PowerShell doesn't quote arguments that contain spaces
            $installArgs += '--location', "`"$($Package.Location)`""
        }
        $code = $null
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            Write-Pending $name $(if ($attempt -eq 1) { 'installing...' } else { 'retrying...' })
            Write-Log "Doing: install $name ($($Package.Id)), attempt $attempt"
            try {
                $code = Invoke-Winget -Arguments $installArgs -AsUser:([bool]$Package.AsUser)
            } catch {
                Write-Log "  $name - $($_.Exception.Message)"
                $code = $null
            }
            Write-Log "  $name exit code: $code"
            if ($code -in 0, $script:WingetCodes.AlreadyInstalled, $script:WingetCodes.RebootRequired) { break }
            if ($attempt -eq 1) { Start-Sleep -Seconds 5 }
        }

        if ($code -eq $script:WingetCodes.RebootRequired) {
            Write-Item $name 'Installed (needs a restart)' 'Ok'
        } elseif ($code -in 0, $script:WingetCodes.AlreadyInstalled) {
            Write-Item $name 'Installed' 'Ok'
        } elseif (Test-WingetInstalled $Package.Id) {
            # Some installers report odd exit codes even when they worked
            Write-Item $name 'Installed' 'Ok'
        } else {
            $hex = if ($null -ne $code) { '0x{0:X8}' -f $code } else { 'no response' }
            Write-Item $name "Failed (winget error $hex)" 'Fail'
        }
    } catch {
        Write-Log "Installing $name failed: $($_.Exception.Message)"
        Write-Item $name "Failed: $($_.Exception.Message)" 'Fail'
    } finally {
        # Timing per app, to see later where the time goes
        Write-Log ("  {0} took {1:N0} s" -f $name, $timer.Elapsed.TotalSeconds)
    }
}

# ------------------------------------------------------------------
#  Steps called from the engine
# ------------------------------------------------------------------

function Update-WingetCatalog {
    # Makes sure winget works from the newest list of app versions
    try {
        Write-Pending 'App catalog' 'refreshing...'
        $code = Invoke-Winget -Arguments @('source', 'update', '--name', 'winget', '--disable-interactivity') -TimeoutMinutes 5
        if ($code -eq 0) { Write-Item 'App catalog' 'Refreshed' 'Ok' }
        else             { Write-Item 'App catalog' ("Couldn't refresh (0x{0:X8}), using cached" -f $code) 'Warn' }
    } catch {
        Write-Log "Catalog refresh failed: $($_.Exception.Message)"
        Write-Item 'App catalog' "Couldn't refresh, using cached" 'Warn'
    }
}

function Start-AppDownloads {
    <#
        Queues background downloads for every package that isn't installed
        yet, in the same order they will be installed.
    #>
    param($Config)
    if ($script:Setup.DryRun) { return }
    if ($null -eq $script:WingetInstalled) { Update-InstalledSnapshot }

    $all = @()
    if ($Config.Redistributables.Enabled) { $all += $Config.Redistributables.Packages }
    if ($Config.Apps.Enabled) { foreach ($g in $Config.Apps.Groups) { $all += $g.Packages } }
    # Store apps can't be downloaded ahead of time; they install directly
    $missing = @($all | Where-Object { $_.Source -ne 'msstore' -and -not (Get-InstalledVersion $_.Id) })
    if ($missing) { Start-DownloadQueue $missing }
}

function Invoke-Redistributables {
    param($Config)
    Write-Section 'Game redistributables'
    if ($null -eq $script:WingetInstalled) { Update-InstalledSnapshot }
    foreach ($package in $Config.Packages) { Install-WingetPackage $package }
}

function Invoke-AppInstall {
    param($Config)
    if ($null -eq $script:WingetInstalled) { Update-InstalledSnapshot }
    foreach ($group in $Config.Groups) {
        Write-Section "Apps: $($group.Name)"
        foreach ($package in $group.Packages) { Install-WingetPackage $package }
    }
}
