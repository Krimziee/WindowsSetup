<#
    Removes preinstalled Store apps (for the current user, all users and
    future users), optionally OneDrive, and stops Windows from silently
    installing "suggested" apps again.
#>

function Get-InstalledStoreApp {
    param([string]$Id)
    if (Test-IsAdmin) { @(Get-AppxPackage -AllUsers -Name $Id) } else { @(Get-AppxPackage -Name $Id) }
}

function Get-ProvisionedApps {
    # Provisioned = the copy Windows gives to every NEW user account.
    # This query is slow (seconds), so it runs once before and once after.
    if (-not (Test-IsAdmin)) { return @() }
    try { @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) }
    catch { Write-Log "Couldn't list provisioned apps: $($_.Exception.Message)"; @() }
}

function Remove-StoreApp {
    <#
        Each removal step may report errors even when it worked (newer Windows
        versions clean up more in the first step, so the second one finds
        nothing). So the errors are only logged, and the result is decided by
        checking whether the app is actually still there afterwards.
        The new-user copy is checked for all apps at once afterwards.
    #>
    param(
        [string]$Id,
        [string]$Name,
        [object[]]$Provisioned
    )

    $installed = Get-InstalledStoreApp $Id
    $staged    = @($Provisioned | Where-Object { $_.DisplayName -eq $Id })

    if (-not $installed -and -not $staged) {
        Write-Item $Name 'Not installed' 'Skip'
        return
    }
    foreach ($pkg in $installed) { Write-Log "  $Id found: $($pkg.PackageFullName)" }

    if ($script:Setup.DryRun) {
        Write-Log "[dry run] would remove $Name ($Id)"
        Write-Item $Name 'Removed' 'Ok'
        return
    }

    # On a fresh install the Store updates apps in the background. If it is
    # updating this app right now, removal can fail or the new version can
    # appear right after, so we try up to 3 times with a short pause.
    $errors = New-Object System.Collections.Generic.List[string]
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if ($attempt -gt 1) {
            Write-Log "  $Id still present, retrying (attempt $attempt)"
            Start-Sleep -Seconds 5
            $installed = Get-InstalledStoreApp $Id
        }
        Write-Log "Doing: remove $Name ($Id), attempt $attempt"

        foreach ($pkg in $installed) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            } catch {
                $errors.Add("all users: $($_.Exception.Message.Trim())")
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                } catch {
                    $errors.Add("this user: $($_.Exception.Message.Trim())")
                }
            }
        }
        # The step above often removes the new-user copy too; errors here just mean "already gone"
        if ($attempt -eq 1) {
            foreach ($pkg in $staged) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -AllUsers -ErrorAction Stop | Out-Null
                } catch {
                    Write-Log "  $Id new-user copy: $($_.Exception.Message.Trim())"
                }
            }
        }

        $leftForMe = @(Get-AppxPackage -Name $Id)
        if (-not $leftForMe) { break }
    }
    foreach ($e in $errors) { Write-Log "  $Id - $e" }
    if (-not $leftForMe) {
        Write-Item $Name 'Removed' 'Ok'
    } else {
        $reason = if ($errors.Count) { $errors[-1] } else { 'Windows kept it' }
        Write-Item $Name "Couldn't remove: $reason" 'Fail'
    }
}

function Test-NewUserCopies {
    # One slow query for all apps instead of one per app
    param([object[]]$Apps)
    if ($script:Setup.DryRun -or -not (Test-IsAdmin)) { return }
    $left = Get-ProvisionedApps
    foreach ($app in $Apps) {
        if ($left | Where-Object { $_.DisplayName -eq $app.Id }) {
            Write-Item $app.Name 'Removed, but new accounts may still get it' 'Warn'
        }
    }
}

function Get-UninstallEntry {
    # Classic (non-Store) programs register themselves in these registry keys
    param([string]$DisplayName)
    $keys = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    @(Get-ItemProperty $keys -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -eq $DisplayName -and $_.UninstallString })
}

function Remove-ClassicApp {
    <#
        Runs a classic program's own uninstaller with extra arguments that
        make it silent (every vendor uses different ones, so the preset
        provides them), then checks the program is really gone.
    #>
    param(
        [string]$DisplayName,
        [string]$Name,
        [string]$SilentArgs
    )

    $entries = Get-UninstallEntry $DisplayName
    if (-not $entries) {
        Write-Item $Name 'Not installed' 'Skip'
        return
    }

    try {
        foreach ($entry in $entries) {
            $command = $entry.UninstallString.Trim()
            if ($command -match '^"([^"]+)"\s*(.*)$' -or $command -match '^(\S+\.exe)\s*(.*)$') {
                $exe, $arguments = $Matches[1], "$($Matches[2]) $SilentArgs".Trim()
            } else {
                throw "Unexpected uninstall command: $command"
            }
            Write-Log "  $Name uninstaller: $exe $arguments"
            Invoke-Change "uninstall $Name" {
                $proc = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -WindowStyle Hidden
                $null = $proc.Handle   # keeps the exit code available after waiting
                if (-not $proc.WaitForExit(180000)) { throw 'The uninstaller took longer than 3 minutes.' }
                Write-Log "  $Name uninstaller exit code: $($proc.ExitCode)"
            }
        }

        if ($script:Setup.DryRun) {
            Write-Item $Name 'Removed' 'Ok'
            return
        }
        # Some uninstallers hand the work to a helper process and exit early
        for ($i = 0; $i -lt 15 -and (Get-UninstallEntry $DisplayName); $i++) { Start-Sleep -Seconds 2 }
        if (Get-UninstallEntry $DisplayName) {
            Write-Item $Name 'Uninstaller ran, but it''s still installed' 'Fail'
        } else {
            Write-Item $Name 'Removed' 'Ok'
        }
    } catch {
        Write-Log "Removing $Name failed: $($_.Exception.Message)"
        Write-Item $Name "Couldn't remove: $($_.Exception.Message)" 'Fail'
    }
}

function Get-OneDriveCloudOnlyFiles {
    # Files that exist only in the cloud would be lost from this PC's view
    # once OneDrive is gone, so we never uninstall when any are found.
    $folders = @($env:OneDrive, $env:OneDriveConsumer) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    $cloudOnly = 0x400000 -bor 0x40000 -bor 0x1000   # recall on access, recall on open, offline
    foreach ($folder in $folders) {
        Get-ChildItem -LiteralPath $folder -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { ([int]$_.Attributes -band $cloudOnly) -ne 0 } |
            Select-Object -First 1
    }
}

function Remove-OneDrive {
    $exePaths = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    )
    $installed = $exePaths | Where-Object { Test-Path $_ }
    $setupPaths = @(
        (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\OneDrive\*\OneDriveSetup.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName),
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    if (-not $installed) {
        Write-Item 'OneDrive' 'Not installed' 'Skip'
        return
    }
    if (Get-OneDriveCloudOnlyFiles) {
        Write-Item 'OneDrive' 'Kept: some files exist only in the cloud' 'Warn'
        return
    }
    if (-not $setupPaths) {
        Write-Item 'OneDrive' 'Uninstaller not found' 'Fail'
        return
    }

    try {
        Invoke-Change 'uninstall OneDrive' {
            Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
            $proc = Start-Process -FilePath ($setupPaths | Select-Object -First 1) -ArgumentList '/uninstall' -PassThru -Wait
            Write-Log "OneDriveSetup /uninstall exit code: $($proc.ExitCode)"
        }
        if (-not $script:Setup.DryRun -and ($exePaths | Where-Object { Test-Path $_ })) {
            Write-Item 'OneDrive' 'Uninstaller ran, but files remain' 'Warn'
        } else {
            Write-Item 'OneDrive' 'Removed' 'Ok'
        }
    } catch {
        Write-Log "OneDrive removal failed: $($_.Exception.Message)"
        Write-Item 'OneDrive' "Couldn't remove: $($_.Exception.Message)" 'Fail'
    }
}

function Disable-SuggestedAppInstalls {
    param([bool]$AlsoBlockOneDriveForNewUsers)

    # These stop Windows from quietly installing "suggested" apps (games, promos)
    $cdm = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $values = 'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled', 'OemPreInstalledAppsEnabled'

    try {
        foreach ($v in $values) { Set-RegistryValue "HKCU:\$cdm" $v 0 }

        Invoke-WithDefaultUserHive {
            param($root)
            foreach ($v in $values) { Set-RegistryValue "$root\$cdm" $v 0 }
            if ($AlsoBlockOneDriveForNewUsers) {
                # New accounts would otherwise get OneDrive installed at first sign-in
                Invoke-Change 'remove OneDriveSetup from new-user startup' {
                    Remove-ItemProperty -LiteralPath "$root\Software\Microsoft\Windows\CurrentVersion\Run" -Name 'OneDriveSetup' -ErrorAction SilentlyContinue
                }
            }
        }
        Write-Item 'Auto-installed apps' 'Blocked (this and new accounts)' 'Ok'
    } catch {
        Write-Log "Blocking suggested apps failed: $($_.Exception.Message)"
        Write-Item 'Auto-installed apps' "Couldn't block: $($_.Exception.Message)" 'Fail'
    }
}

function Invoke-BloatwareRemoval {
    param($Config)

    Write-Section 'Removing bloatware'

    $provisioned = Get-ProvisionedApps
    foreach ($app in $Config.Apps) {
        Remove-StoreApp -Id $app.Id -Name $app.Name -Provisioned $provisioned
    }
    Test-NewUserCopies $Config.Apps

    foreach ($app in $Config.ClassicApps) {
        Remove-ClassicApp -DisplayName $app.DisplayName -Name $app.Name -SilentArgs $app.SilentArgs
    }

    if ($Config.RemoveOneDrive) { Remove-OneDrive }

    Disable-SuggestedAppInstalls -AlsoBlockOneDriveForNewUsers ([bool]$Config.RemoveOneDrive)
}
