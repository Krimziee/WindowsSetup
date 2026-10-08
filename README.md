# Windows Setup

Sets up a fresh Windows 10 / 11 install in one go: removes bloatware, applies sensible settings, installs game redistributables and your apps, sets up drivers, cleans up and restarts. Windows Update is left to Windows itself. You pick a setup in a small window, press **Start setup**, and walk away.

## Run it

Open **Terminal (Admin)** or **PowerShell** (right-click the Start button) and paste:

```powershell
irm https://raw.githubusercontent.com/Krimziee/WindowsSetup/main/install.ps1 | iex
```

This downloads the newest version to `C:\WindowsSetup` and opens the setup window. Click **Yes** when Windows asks for permission.

**Without the command:** download the zip (green **Code** button → **Download ZIP**), unpack it and double-click **`Start Setup.cmd`**.

## What it does

| Step | Details |
|---|---|
| Getting ready | Checks internet, updates winget, creates a System Restore point |
| Remove bloatware | Clipchamp, News, Weather, Solitaire, Copilot and similar preinstalled apps; stops Windows from reinstalling "suggested" apps |
| Windows settings | Show file extensions, no ads or suggestions in Start/Settings, and more (depends on the setup you pick) |
| Game redistributables | Visual C++ 2005–2022, DirectX, .NET 6/8/9/10, XNA, OpenAL |
| Apps | Installed with winget from each app's official source, always the latest version |
| Drivers | Detects the hardware: Intel gets Intel's driver assistant; AMD/NVIDIA get their official driver page after the restart |
| Cleanup | Removes leftover installer files; optionally stops newly installed apps from starting with Windows |

Hover over any setting in Custom install to see what it does. The start page shows a live estimate of how much will be downloaded.

Optional checkboxes at the bottom: **Restart when finished**, **Disable unnecessary startup apps** and **Disable Windows driver updates** (desktops only).

Two setups are included:

- **Recommended** – safe defaults for anyone, a few essential apps.
- **Power user** – the full app list and advanced tweaks.

Choose **Custom install** to pick exactly what runs: everything starts unticked, with **Select all** links for everything, for each step and for each app group. Custom also offers optional extras: GOG Galaxy, Firefox, Brave, Telegram, WhatsApp, Bitwarden, Dropbox, AnyDesk, VS Code, WinRAR and CrystalDiskInfo.

## Good to know

- **Nothing changes until you press Start setup and confirm.** A short summary of what will run is shown first. A restore point is created before anything changes, and a log is saved to your desktop.
- Windows Setup is also a tab in Krimz's Toolkit, which shows the same page.
- Already-installed apps are updated instead of reinstalled, so it's safe to run again.
- Windows SmartScreen or antivirus software may warn about scripts downloaded from the internet. The whole tool is plain PowerShell you can read in this repository.
- Settings are changed for the account that runs the setup.

## For developers

`setup.ps1 -Console` runs the text version; add `-DryRun` to see what would happen without changing anything. Setups live in `presets\*.psd1`, optional apps in `catalog\ExtraApps.psd1`.
