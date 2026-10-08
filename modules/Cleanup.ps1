<#
    Cleanup after everything is installed:
    - settings that must come last (e.g. unpinning taskbar apps)
    - desktop shortcuts that installers added during this run
    - auto-start entries that installers added during this run
    - leftover installer and temp files, and the Windows Update download cache
    - the copy of this tool in C:\WindowsSetup (removed after the restart)
#>

$script:DesktopBefore = @()
$script:StartupBefore = @()

function Get-StartupEntries {
    <#
        Lists the programs that start with Windows, from the same places Task
        Manager's "Startup apps" tab reads. ApprovedKey is where Task Manager
        stores the enabled/disabled switch for each one.
    #>
    $approved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $sources = @(
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKCU:\$approved\Run" }
        @{ Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKLM:\$approved\Run" }
        @{ Key = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$approved\Run32" }
    )
    foreach ($s in $sources) {
        $values = Get-ItemProperty $s.Key -ErrorAction SilentlyContinue
        if (-not $values) { continue }
        foreach ($p in $values.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
            [pscustomobject]@{ Name = $p.Name; ApprovedKey = $s.Approved; Id = "$($s.Key)|$($p.Name)" }
        }
    }
    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Startup');       Approved = "HKCU:\$approved\StartupFolder" }
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$approved\StartupFolder" }
    )
    foreach ($f in $folders) {
        foreach ($file in Get-ChildItem $f.Path -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini') {
            [pscustomobject]@{ Name = $file.Name; ApprovedKey = $f.Approved; Id = "$($f.Path)|$($file.Name)" }
        }
    }
}

function Disable-NewStartupApps {
    # Turns off auto-start for programs added during this run, like
    # switching them to "Disabled" in Task Manager (easy to turn back on)
    param([string[]]$Keep)

    # Never turned off: Windows Security, and Valorant's anti-cheat (the game needs it)
    $Keep = @($Keep) + 'SecurityHealth', 'Riot Vanguard'

    $new = @(Get-StartupEntries | Where-Object { $_.Id -notin $script:StartupBefore })
    $toDisable = @($new | Where-Object { $name = $_.Name; -not ($Keep | Where-Object { $name -like $_ }) })
    if (-not $toDisable) {
        Write-Item 'Startup apps' 'No new ones added' 'Skip'
        return
    }
    # First byte 3 = disabled (2 = enabled); the rest is a timestamp Windows doesn't need
    $disabled = [byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    # Some apps register in more than one place (Discord does); show each app once
    foreach ($app in $toDisable | Group-Object { $_.Name -replace '\.lnk$', '' }) {
        try {
            foreach ($entry in $app.Group) { Set-RegistryValue $entry.ApprovedKey $entry.Name $disabled 'Binary' }
            Write-Item "Startup: $($app.Name)" 'Won''t start with Windows' 'Ok'
        } catch {
            Write-Log "Disabling startup entry $($app.Name) failed: $($_.Exception.Message)"
            Write-Item "Startup: $($app.Name)" "Couldn't turn off: $($_.Exception.Message)" 'Warn'
        }
    }
}

function Save-CleanupState {
    # Remember what was there before, so cleanup only touches what this run added
    $script:DesktopBefore = Get-DesktopShortcuts
    $script:StartupBefore = @(Get-StartupEntries | ForEach-Object Id)
}

function Get-DesktopShortcuts {
    $folders = [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')
    @(Get-ChildItem $folders -Filter *.lnk -File -Force -ErrorAction SilentlyContinue | ForEach-Object FullName)
}

function Remove-NewDesktopShortcuts {
    $new = @(Get-DesktopShortcuts | Where-Object { $_ -notin $script:DesktopBefore })
    if (-not $new) {
        Write-Item 'Desktop shortcuts' 'None added' 'Skip'
        return
    }
    foreach ($file in $new) {
        Invoke-Change "remove desktop shortcut $file" { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    }
    Write-Item 'Desktop shortcuts' "Removed $($new.Count) added by installers" 'Ok'
}

function Remove-OldFiles {
    <#
        Deletes files in a temp folder that were created during this run
        (installer leftovers) or are older than a week, like Disk Cleanup
        does. Files that are in use are skipped.
    #>
    param([string]$Folder, [datetime]$Since)
    if (-not (Test-Path $Folder)) { return }
    $weekAgo = (Get-Date).AddDays(-7)
    Get-ChildItem $Folder -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.CreationTime -ge $Since -or $_.LastWriteTime -lt $weekAgo } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

function Clear-SetupLeftovers {
    param([datetime]$StartedAt)

    $drive  = Get-PSDrive ($env:SystemDrive.TrimEnd(':'))
    $before = $drive.Free
    try {
        Invoke-Change 'delete leftover installer and temp files' {
            Remove-Item $script:Downloads.Root -Recurse -Force -ErrorAction SilentlyContinue
            Remove-OldFiles $env:TEMP $StartedAt
            Remove-OldFiles (Join-Path $env:SystemRoot 'Temp') $StartedAt
            # Windows Update keeps downloaded updates around for sharing; they aren't needed anymore
            if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                # *> $null hides the "Deleting..." text this command prints straight to the screen
                Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue *> $null
            }
        }
        $freed = [math]::Max(0, ((Get-PSDrive $drive.Name).Free - $before) / 1MB)
        Write-Item 'Temporary files' ('Cleaned up ({0:N0} MB freed)' -f $freed) 'Ok'
    } catch {
        Write-Log "Temp cleanup failed: $($_.Exception.Message)"
        Write-Item 'Temporary files' "Couldn't clean up: $($_.Exception.Message)" 'Warn'
    }
}

function Remove-SetupCopyAfterRestart {
    # Start Setup.cmd copied the tool to C:\WindowsSetup; delete that copy after the restart
    $copy = 'C:\WindowsSetup'
    if ($PSScriptRoot -notlike "$copy\*") { return }   # running from somewhere else (USB, dev folder)
    try {
        Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' 'WindowsSetup-RemoveCopy' "cmd.exe /c rmdir /s /q `"$copy`"" 'String'
        Write-Item 'Setup files' 'Removed after the restart' 'Ok'
    } catch {
        Write-Log "Scheduling removal of $copy failed: $($_.Exception.Message)"
    }
}

function Invoke-Cleanup {
    param($Config, $System, [datetime]$StartedAt)

    Write-Section 'Cleanup'
    Invoke-LastSettings $System
    if ($Config.RemoveNewDesktopShortcuts) { Remove-NewDesktopShortcuts }
    if ($Config.DisableNewStartupApps)     { Disable-NewStartupApps -Keep $Config.KeepStartupApps }
    Clear-SetupLeftovers $StartedAt
    if ($Config.RemoveSetupCopy) { Remove-SetupCopyAfterRestart }
}
