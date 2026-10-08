<#
    Windows Setup - online starter

    Run this in PowerShell (it downloads the newest Windows Setup from
    GitHub and opens it):

        irm https://raw.githubusercontent.com/Krimziee/WindowsSetup/main/install.ps1 | iex

    What it does:
      1. Downloads the project from github.com/Krimziee/WindowsSetup as a zip
      2. Unpacks it to C:\WindowsSetup (replacing an older copy)
      3. Starts the setup window with admin rights (Windows asks "Yes/No")
    Nothing is changed on the PC until you press "Start setup" in the window.
#>

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference    = 'SilentlyContinue'   # much faster downloads in Windows PowerShell
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $zipUrl = 'https://github.com/Krimziee/WindowsSetup/archive/refs/heads/main.zip'
    $target = 'C:\WindowsSetup'
    $zip    = Join-Path $env:TEMP 'WindowsSetup.zip'
    $unpack = Join-Path $env:TEMP 'WindowsSetup-unpack'

    try {
        Write-Host ''
        Write-Host ' Windows Setup' -ForegroundColor Cyan
        Write-Host ' Downloading the latest version...' -ForegroundColor Gray
        Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing

        Write-Host " Unpacking to $target..." -ForegroundColor Gray
        Remove-Item $unpack -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $zip -DestinationPath $unpack -Force
        # GitHub puts everything in one folder named "<repo>-<branch>"
        $source = Get-ChildItem $unpack -Directory | Select-Object -First 1
        if (-not (Test-Path (Join-Path $source.FullName 'setup.ps1'))) { throw 'The download looks incomplete (setup.ps1 is missing).' }

        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        Copy-Item $source.FullName $target -Recurse
        # Files from the internet are marked as "downloaded"; clear that so Windows doesn't block them
        Get-ChildItem $target -Recurse -File | Unblock-File

        Write-Host ' Starting - click "Yes" when Windows asks for permission.' -ForegroundColor Gray
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$target\setup.ps1`""
        )
        Write-Host ' The setup window is opening. You can close this window.' -ForegroundColor Green
    }
    catch {
        Write-Host ''
        Write-Host " Couldn't start Windows Setup: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ' Check your internet connection and try again.' -ForegroundColor Gray
    }
    finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $unpack -Recurse -Force -ErrorAction SilentlyContinue
    }
}
