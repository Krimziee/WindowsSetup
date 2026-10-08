# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Windows Setup sets up a fresh Windows 10/11 install (bloatware, settings, redistributables, apps via winget, drivers, cleanup, restart). Plain Windows PowerShell 5.1 + WPF, no build step, no external dependencies. It is public at github.com/Krimziee/WindowsSetup and is also the first tab of Krimz's Toolkit (`D:\Claude Code\KrimzToolkit`, its own repo).

## Running and checking

There is no test suite. Changes are checked by running the tool, preferably in dry-run mode (logs what it *would* do; every change goes through `Invoke-Change`, see below):

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1 -DryRun                  # window, nothing changed
powershell -ExecutionPolicy Bypass -File setup.ps1 -Console -DryRun -Preset Recommended   # text version
```

- A real run needs admin rights and changes the PC; `Start Setup.cmd` copies the folder to `C:\WindowsSetup` and starts it elevated.
- Dry run still writes a log `WindowsSetup-log-*.txt` to the desktop; delete logs created by your own test runs.
- Window screenshots without opening it: `Show-SetupWindow -Root <repo> -Version $script:SetupVersion -System (Get-SystemInfo) -NoShow` returns the window; show it off-screen and render it with `RenderTargetBitmap` (load `modules\Load-Modules.ps1` and `modules\Ui.ps1` first).
- Syntax check: `[System.Management.Automation.Language.Parser]::ParseFile(<file>, [ref]$null, [ref]$errors)`.

## Architecture

- **Entry points.** `setup.ps1` (window by default, `-Console` for text), `Start Setup.cmd` (local launcher, copies to `C:\WindowsSetup`), `install.ps1` (the online one-liner `irm .../install.ps1 | iex`, downloads the `main` branch zip - anything pushed to `main` is live for users).
- **Engine** (`modules\Load-Modules.ps1` loads it all): `Engine.ps1` `Invoke-Setup` runs the steps in order (preflight, restore point, bloatware, settings, redistributables, apps, drivers, cleanup). Each step is its own module.
- **Presets** (`presets\*.psd1`) are the data: which bloatware, which setting Ids, which winget packages per group, finish options, and an optional `Image` (a PNG in `ui\images` shown on the preset's card; the Custom install card uses `ui\images\Custom.png`). Card pictures are small PNGs (128 px): WebP needs an optional Windows codec. Every `.psd1` in that folder becomes a choice. `catalog\ExtraApps.psd1` holds optional apps (Custom mode only, never in presets); app group names are shared by all presets and the extras. **Custom mode** lists every preset's items plus the extras (`Get-Categories -Others`), with the chosen preset's items ticked; `Limit-ConfigToCustomChoices` builds the run from the ticked items, looking each one up in all presets (chosen preset first) so details like `AsUser`/`Location`/`Source` carry over. Custom with nothing changed must equal Normal install; `catalog\DownloadSizes.psd1` feeds the download estimate.
- **Settings catalog**: every Windows setting is one entry in `$script:SettingsCatalog` in `modules\Settings.ps1` (Id, Name, Category, optional `Only = 'Win11'|'Desktop'`, `Last = $true`, `Apply` scriptblock) with its hover text in `$script:SettingInfo`. Presets only list Ids. `NoDriversFromWindowsUpdate` is special: the window shows it as its own footer checkbox.
- **All changes go through `Invoke-Change`** (and `Set-RegistryValue`, which uses it) in `Common.ps1`, which is what makes `-DryRun` safe. New code that changes the PC must use it.
- **Output is routed, not printed.** Modules call `Write-Section` / `Write-Item` / `Write-Pending`; in the console they print, in the window they go into `$script:Setup.UiQueue`. `Write-Log` also sends every log line there (or to `LogQueue` for the window's own lines), which feeds the live Details panel. `Write-Item` also records results for the summary and nudges the download queue (`Downloads.ps1` downloads the next apps in parallel while one installs).
- **Window** (`modules\Ui.ps1`): the UI is a page, `ui\Page.xaml` (a UserControl), built by `New-SetupPage`. `Show-SetupWindow` wraps it in the empty `ui\MainWindow.xaml`; Krimz's Toolkit loads it through `modules\Page.ps1`. The engine runs in a background runspace (`Run-Engine.ps1`) and a `DispatcherTimer` drains the queue, so the window never freezes. Start setup always shows `ui\ConfirmDialog.xaml` first (Enter must not confirm it).
- **Styles** come from `ui\Theme.xaml`, loaded as the WPF Application's resources (so XAML uses `{StaticResource ...}` from it). It is a copy of the toolkit's `ui\Theme.xaml`, which is the main copy - change the toolkit's and copy it here. Page-only styles live in the page.
- **Toolkit page contract** (`modules\Page.ps1`): defines `New-ToolPage -Root -Shell` (returns the page), `Test-ToolPageCanClose`, `Close-ToolPage`. The toolkit loads it in a private module, passes `$Shell.SetBusy` (working dot on the tab, called via `Set-SetupBusy`) and `$Shell.DryRun`. In the toolkit the log only starts when setup is confirmed.
- **Version** is `$script:SetupVersion` in `modules\Common.ps1` (used by both the window and the toolkit).

## Conventions

- Windows PowerShell 5.1 only: no ternary, `??`, `?.`, `&&`/`||`. Files keep CRLF line endings (`.gitattributes`); most `.ps1` files have a UTF-8 BOM.
- Text shown to users is plain, non-technical English (the audience is friends and family setting up a PC).
- The user decides on commits and pushes; commits use the repo's local git identity (Krimz, GitHub no-reply email).
