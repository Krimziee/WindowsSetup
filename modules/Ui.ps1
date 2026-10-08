<#
    The setup window (WPF, built into Windows). The window only draws; the
    actual work runs in a background runspace (Run-Engine.ps1) and reports
    progress through a queue that a timer reads several times per second.
    That way the window never freezes, whatever the engine is doing.
#>

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$script:Ui      = @{}   # named controls from MainWindow.xaml
$script:UiState = @{}   # everything that changes while the window is open

# Segoe Fluent Icons glyphs (Segoe MDL2 Assets on Windows 10)
$script:Glyph = @{
    Ok = [char]0xE73E; Fail = [char]0xE711; Warn = [char]0xE7BA; Skip = [char]0xE738; Info = [char]0xE946
    Pending = [char]0xE895; Bloatware = [char]0xE74D; Settings = [char]0xE713; Redistributables = [char]0xE7FC
    Apps = [char]0xE71D; Drivers = [char]0xE772; Cleanup = [char]0xE894
}
$script:Colors = @{ Ok = '#6CCB5F'; Skip = '#8A8A8A'; Warn = '#FCE100'; Fail = '#FF99A4'; Info = '#A6A6A6'; Accent = '#4CA6FF'; Muted = '#A6A6A6'; Text = '#F3F3F3' }

# ------------------------------------------------------------------
#  Small helpers
# ------------------------------------------------------------------

function Enable-DpiAwareness {
    # Sharp text on high-resolution screens (otherwise Windows stretches the window and it looks blurry)
    if (-not ('WindowsSetup.Dpi' -as [type])) {
        Add-Type -Namespace WindowsSetup -Name Dpi -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
'@
    }
    try { if (-not [WindowsSetup.Dpi]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))) { [void][WindowsSetup.Dpi]::SetProcessDPIAware() } }
    catch { }
}

function Invoke-UiSafely {
    # An error inside a button or timer handler must never close the window
    param([scriptblock]$Action)
    try { & $Action }
    catch {
        Write-Log "UI error: $($_.Exception.Message) $($_.ScriptStackTrace)"
        [System.Windows.MessageBox]::Show("Something went wrong in the window:`n$($_.Exception.Message)`n`nDetails are in the log.", 'Windows Setup', 'OK', 'Warning') | Out-Null
    }
}

function New-Text {
    param([string]$Text, [string]$Color = $script:Colors.Text, [double]$Size = 14, [string]$Weight = 'Normal', [string]$Margin = '0')
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    $t.Foreground = $Color
    $t.FontSize = $Size
    $t.FontWeight = $Weight
    $t.Margin = $Margin
    $t.TextWrapping = 'Wrap'
    $t
}

function New-Icon {
    param([string]$Glyph, [string]$Color = $script:Colors.Accent, [double]$Size = 16)
    $t = New-Text $Glyph $Color $Size
    $t.FontFamily = 'Segoe Fluent Icons, Segoe MDL2 Assets'
    $t.VerticalAlignment = 'Center'
    $t
}

function New-Card {
    param([string]$Margin = '0,0,0,10')
    $b = New-Object System.Windows.Controls.Border
    $b.Style = $script:Ui.Page.FindResource('Card')
    $b.Margin = $Margin
    $b
}

function Get-CardImage {
    # A picture from ui\images for an option card, or nothing if the file is missing.
    # Read fully into memory (OnLoad) so the file is never kept open.
    param([string]$Root, [string]$Name)
    if (-not $Name) { return }
    $path = Join-Path $Root "ui\images\$Name"
    if (-not (Test-Path $path)) { return }
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = 'OnLoad'
    $bitmap.UriSource = New-Object System.Uri $path
    $bitmap.EndInit()
    $bitmap.Freeze()
    $bitmap
}

function Get-ScrollViewer {
    # Finds the scroll area inside a control (used to keep the log scrolled to the end)
    param($Element)
    if ($Element -is [System.Windows.Controls.ScrollViewer]) { return $Element }
    for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element); $i++) {
        $found = Get-ScrollViewer ([System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i))
        if ($found) { return $found }
    }
    $null
}

function Show-Page {
    param([ValidateSet('Start', 'Progress', 'Finish')] [string]$Name)
    foreach ($p in 'Start', 'Progress', 'Finish') {
        $script:Ui["${p}Page"].Visibility = if ($p -eq $Name) { 'Visible' } else { 'Collapsed' }
    }
}

# ------------------------------------------------------------------
#  Start page
# ------------------------------------------------------------------

function Get-ExtraApps {
    # Optional apps for Custom mode (catalog\ExtraApps.psd1); never part of a preset
    param([string]$Root)
    $file = Join-Path $Root 'catalog\ExtraApps.psd1'
    if (Test-Path $file) { (Import-PowerShellDataFile $file).Groups } else { @() }
}

function Get-Categories {
    <#
        The steps as the window shows them: a title, an icon and (where it
        makes sense) the individual items.
        Normal install: only the chosen preset ($Config).
        Custom install: every preset's items (-Others) and the optional apps
        (-Extras) are listed too. Items that aren't in the chosen preset are
        marked Extra; the preset's own items are the ones that start ticked.
    #>
    param($Config, $Extras, $Others = @())

    $all = @($Config) + @($Others)
    $notMine = { param($cfg) -not [object]::ReferenceEquals($cfg, $Config) }

    # Bloatware: the chosen preset's apps first, then the ones only other presets remove
    $bloat = @(); $seen = @{}
    foreach ($cfg in $all) {
        $list  = @($cfg.Bloatware.Apps | Where-Object { $_ } | ForEach-Object { @{ Key = "store:$($_.Id)"; Name = $_.Name } })
        $list += @($cfg.Bloatware.ClassicApps | Where-Object { $_ } | ForEach-Object { @{ Key = "classic:$($_.DisplayName)"; Name = $_.Name } })
        if ($cfg.Bloatware.RemoveOneDrive) { $list += @{ Key = 'onedrive'; Name = 'OneDrive' } }
        foreach ($item in $list) {
            if ($seen[$item.Key]) { continue }
            $seen[$item.Key] = $true; $item.Extra = & $notMine $cfg; $bloat += $item
        }
    }

    # Apps, group by group (same group names in every preset); optional extras join the group with the same name
    $apps = @(); $seen = @{}
    $groupNames = @()
    foreach ($g in @($all | ForEach-Object { $_.Apps.Groups }) + @($Extras)) { if ($g -and $g.Name -notin $groupNames) { $groupNames += $g.Name } }
    foreach ($groupName in $groupNames) {
        $sources = @(foreach ($cfg in $all) { @{ Packages = ($cfg.Apps.Groups | Where-Object Name -eq $groupName).Packages; Extra = & $notMine $cfg } })
        $sources += @{ Packages = ($Extras | Where-Object Name -eq $groupName).Packages; Extra = $true }
        foreach ($source in $sources) {
            foreach ($p in @($source.Packages | Where-Object { $_ })) {
                if ($seen[$p.Id]) { continue }
                $seen[$p.Id] = $true
                $apps += @{ Key = $p.Id; Name = $p.Name; Group = $groupName; Extra = $source.Extra }
            }
        }
    }

    # Settings. The driver-updates setting has its own checkbox in the footer, so it isn't listed here.
    $mine = @($Config.Settings.Apply | Where-Object { $_ -and $_ -ne $script:DriverSettingId })
    $settingName = @{}
    foreach ($s in $script:SettingsCatalog) { $settingName[$s.Id] = $s.Name }
    if ($Others) {
        # The full list in catalog order, grouped by kind (Look, Taskbar, ...)
        $any = @($all | ForEach-Object { $_.Settings.Apply } | Where-Object { $_ -and $_ -ne $script:DriverSettingId } | Select-Object -Unique)
        $settings = @(foreach ($s in $script:SettingsCatalog) {
            if ($s.Id -notin $any) { continue }
            @{ Key = $s.Id; Name = $s.Name; Info = $script:SettingInfo[$s.Id]; Group = $s.Category; Extra = $s.Id -notin $mine }
        })
    } else {
        $settings = @($mine | ForEach-Object { @{ Key = $_; Name = $(if ($settingName[$_]) { $settingName[$_] } else { $_ }); Info = $script:SettingInfo[$_] } })
    }

    $redist = @(); $seen = @{}
    foreach ($cfg in $all) {
        foreach ($p in @($cfg.Redistributables.Packages | Where-Object { $_ })) {
            if ($seen[$p.Id]) { continue }
            $seen[$p.Id] = $true; $redist += @{ Key = $p.Id; Name = $p.Name; Extra = & $notMine $cfg }
        }
    }

    # A step is listed when any preset shown has it; Ticked = the chosen preset runs it
    $step = {
        param([string]$Key, [string]$Title, $Items, [string]$Unit)
        @{ Key = $Key; Title = $Title; Items = @($Items); Unit = $Unit
           Enabled = [bool]($all | Where-Object { $_[$Key].Enabled }); Ticked = [bool]$Config[$Key].Enabled }
    }
    @(
        & $step 'Bloatware'        'Remove bloatware'      $bloat    'apps'
        & $step 'Settings'         'Windows settings'      $settings 'changes'
        & $step 'Redistributables' 'Game redistributables' $redist   'packages'
        & $step 'Apps'             'Apps'                  $apps     'apps'
        & $step 'Drivers'          'Drivers'               @()       ''
        & $step 'Cleanup'          'Cleanup'               @()       ''
    ) | Where-Object { $_.Enabled -and ($_.Items.Count -gt 0 -or $_.Key -in 'Drivers', 'Cleanup') }
}

function Get-CategoryDetail {
    # One line that explains a step in plain words
    param($Category, $System)
    switch ($Category.Key) {
        'Drivers' {
            if ($System.IsVM) { 'Not needed in a virtual machine' }
            else {
                $vendors = @($System.Gpus.Vendor) + $System.Cpu.Vendor | Where-Object { $_ -in 'AMD', 'NVIDIA', 'Intel' } | Select-Object -Unique
                $parts = foreach ($v in $vendors) {
                    switch ($v) { 'Intel' { 'Intel driver assistant' } default { "$v driver page opens after the restart" } }
                }
                if ($parts) { $parts -join ', ' } else { 'Nothing needed for this hardware' }
            }
        }
        'Cleanup'       { 'Leftover installer files, apps that start with Windows, taskbar pins' }
        default {
            $included = @($Category.Items | Where-Object { -not $_.Extra })
            $optional = @($Category.Items | Where-Object { $_.Extra }).Count
            $names = @($included | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ', '
            $more  = $included.Count - 5
            "$($included.Count) $($Category.Unit): $names$(if ($more -gt 0) { " and $more more" })" +
                $(if ($optional) { " (+$optional optional)" })
        }
    }
}

function Update-NormalPanel {
    param($Config, $System)
    $panel = $script:Ui.NormalPanel
    $panel.Children.Clear()
    foreach ($cat in Get-Categories $Config) {
        $card = New-Card
        $grid = New-Object System.Windows.Controls.Grid
        $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
        $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $icon = New-Icon $script:Glyph[$cat.Key] $script:Colors.Accent 18
        $icon.Margin = '0,0,14,0'
        $text = New-Object System.Windows.Controls.StackPanel
        [void]$text.Children.Add((New-Text $cat.Title -Weight 'SemiBold'))
        [void]$text.Children.Add((New-Text (Get-CategoryDetail $cat $System) $script:Colors.Muted 12.5 -Margin '0,2,0,0'))
        [System.Windows.Controls.Grid]::SetColumn($text, 1)
        [void]$grid.Children.Add($icon)
        [void]$grid.Children.Add($text)
        $card.Child = $grid
        if ($cat.Key -eq 'Settings') {
            # Hovering over the settings card lists them; Custom shows what each one does
            $card.Background = $script:Ui.Page.FindResource('Surface')   # needed so the whole card reacts to hovering
            $card.ToolTip = (@($cat.Items | ForEach-Object { "- $($_.Name)" }) -join "`n") +
                            "`n`nChoose Custom install and hover over a setting to see what it does."
        }
        [void]$panel.Children.Add($card)
    }
}

# ------------------------------------------------------------------
#  Download estimate
# ------------------------------------------------------------------

function Get-DownloadEstimateMB {
    # Adds up the installer sizes of the apps and redistributables that would run
    param($Config)
    $sizes = $script:UiState.Sizes
    $packages = @()
    if ($Config.Redistributables.Enabled) { $packages += $Config.Redistributables.Packages }
    if ($Config.Apps.Enabled) { foreach ($g in $Config.Apps.Groups) { $packages += $g.Packages } }
    $total = 0.0
    foreach ($p in $packages | Where-Object { $_ }) {
        $total += $(if ($sizes.ContainsKey($p.Id)) { [double]$sizes[$p.Id] } else { 50 })   # unknown: assume 50 MB
    }
    $total
}

function Update-SizeEstimate {
    $mb = Get-DownloadEstimateMB (Get-SelectedConfig)
    $script:Ui.SizeText.Text = if ($mb -lt 1)       { 'Nothing to download' }
                               elseif ($mb -lt 1000) { '~{0:N0} MB to download' -f $mb }
                               else                  { '~{0:N1} GB to download' -f ($mb / 1024) }
}

function Update-ChoiceFeedback {
    # After any tick in Custom mode: the "Select all" labels and the download estimate follow along
    Update-SelectAllLabel
    Update-SizeEstimate
}

function Update-CustomPanel {
    <#
        One card per step: a checkbox for the whole step, and a "Show items"
        link that opens the list of individual items. The list has everything
        from every preset plus the optional apps; the chosen preset's own items
        start ticked, so changing nothing runs the same as Normal install.
        Ticking a step ticks all its items; ticking only some items shows the
        step as "partly selected".
    #>
    param($Config, $System)
    $panel = $script:Ui.CustomPanel
    $panel.Children.Clear()
    $script:UiState.CustomBoxes = @{}
    $script:UiState.BlockLinks  = New-Object System.Collections.Generic.List[object]   # per-step / per-group "Select all"
    # The other presets, so their items can be picked too (Limit-ConfigToCustomChoices looks them up there)
    $script:UiState.Others = @($script:UiState.Presets | Where-Object { $_.Key -ne $script:UiState.Preset.Key } |
                               ForEach-Object { Import-PowerShellDataFile $_.Path })

    foreach ($cat in Get-Categories $Config $script:UiState.Extras $script:UiState.Others) {
        $card  = New-Card
        $stack = New-Object System.Windows.Controls.StackPanel

        # Two columns: the step (wraps if long) and the "Show items" link
        $header = New-Object System.Windows.Controls.Grid
        $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $header.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
        $catBox = New-Object System.Windows.Controls.CheckBox
        $catBox.IsChecked = $false
        $title = New-Object System.Windows.Controls.StackPanel
        [void]$title.Children.Add((New-Text $cat.Title -Weight 'SemiBold'))
        [void]$title.Children.Add((New-Text (Get-CategoryDetail $cat $System) $script:Colors.Muted 12.5))
        $catBox.Content = $title
        [void]$header.Children.Add($catBox)
        [void]$stack.Children.Add($header)

        $itemBoxes = New-Object System.Collections.Generic.List[object]
        if ($cat.Items.Count) {
            $toggle = New-Object System.Windows.Controls.Button
            $toggle.Style = $script:Ui.Page.FindResource('LinkButton')
            $toggle.Content = 'Show items'
            $toggle.HorizontalAlignment = 'Right'
            $toggle.VerticalAlignment = 'Top'
            $toggle.Margin = '16,0,0,0'
            [System.Windows.Controls.Grid]::SetColumn($toggle, 1)
            [void]$header.Children.Add($toggle)

            $itemsPanel = New-Object System.Windows.Controls.StackPanel
            $itemsPanel.Margin = '28,10,0,0'
            $itemsPanel.Visibility = 'Collapsed'
            $wrap = $null
            $lastGroup = $null
            foreach ($item in $cat.Items) {
                # A new block starts at the first item and at every new group (Apps has groups).
                # Each block gets its own "Select all" link next to its group name.
                if (-not $wrap -or ($item.Group -and $item.Group -ne $lastGroup)) {
                    $lastGroup = $item.Group
                    $blockItems = New-Object System.Collections.Generic.List[object]
                    $blockHeader = New-Object System.Windows.Controls.Grid
                    $blockHeader.Margin = if ($item.Group) { '0,8,0,2' } else { '0,0,0,2' }
                    $blockHeader.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
                    $blockHeader.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
                    if ($item.Group) { [void]$blockHeader.Children.Add((New-Text $item.Group $script:Colors.Muted 12)) }
                    $blockLink = New-Object System.Windows.Controls.Button
                    $blockLink.Style = $script:Ui.Page.FindResource('LinkButton')
                    $blockLink.Content = 'Select all'
                    $blockLink.FontSize = 12
                    $blockLink.Margin = '0,0,14,0'
                    $blockLink.Tag = @{ Items = $blockItems; Category = $catBox; AllItems = $itemBoxes }
                    $blockLink.Add_Click({
                        Invoke-UiSafely {
                            $t = $this.Tag
                            $select = [bool]($t.Items | Where-Object { $_.IsChecked -ne $true })
                            foreach ($b in $t.Items) { $b.IsChecked = $select }
                            Update-CategoryState $t.Category $t.AllItems
                            Update-ChoiceFeedback
                        }
                    })
                    [System.Windows.Controls.Grid]::SetColumn($blockLink, 1)
                    [void]$blockHeader.Children.Add($blockLink)
                    [void]$itemsPanel.Children.Add($blockHeader)
                    $script:UiState.BlockLinks.Add($blockLink)

                    $wrap = New-Object System.Windows.Controls.WrapPanel
                    [void]$itemsPanel.Children.Add($wrap)
                }
                $box = New-Object System.Windows.Controls.CheckBox
                # Long names end in "..." instead of being cut mid-word; hovering shows the full name
                $label = New-Text $item.Name
                $label.TextWrapping = 'NoWrap'
                $label.TextTrimming = 'CharacterEllipsis'
                $box.Content = $label
                $box.IsChecked = $cat.Ticked -and -not $item.Extra   # the preset's own items start ticked
                $box.Width = 250
                if ($item.Info) {
                    # What the setting does: the full name in bold, then the explanation
                    $tip = New-Object System.Windows.Controls.StackPanel
                    [void]$tip.Children.Add((New-Text $item.Name -Size 13 -Weight 'SemiBold' -Margin '0,0,0,4'))
                    [void]$tip.Children.Add((New-Text $item.Info -Size 13))
                    $box.ToolTip = $tip
                } else {
                    $box.ToolTip = $item.Name
                }
                # The item knows its own key and its step, so a click can update the step's checkbox
                $box.Tag = @{ Key = $item.Key; Group = $item.Group; Category = $catBox; Items = $itemBoxes }
                $box.Add_Click({ Invoke-UiSafely { Update-CategoryState $this.Tag.Category $this.Tag.Items; Update-ChoiceFeedback } })
                [void]$wrap.Children.Add($box)
                $itemBoxes.Add($box)
                $blockItems.Add($box)
            }
            [void]$stack.Children.Add($itemsPanel)
            $toggle.Tag = $itemsPanel
            $toggle.Add_Click({
                Invoke-UiSafely {
                    $p = $this.Tag
                    $show = $p.Visibility -ne 'Visible'
                    $p.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
                    $this.Content = if ($show) { 'Hide items' } else { 'Show items' }
                }
            })
        }

        # Ticking or unticking a step does the same to all of its items
        $catBox.Tag = @{ Items = $itemBoxes; Key = $cat.Key }
        $catBox.Add_Click({
            Invoke-UiSafely {
                $on = [bool]$this.IsChecked
                foreach ($b in $this.Tag.Items) { $b.IsChecked = $on }
                if ($this.Tag.Key -eq 'Cleanup') { Set-StartupCheckAvailable }   # the startup option belongs to Cleanup
                Update-ChoiceFeedback
            }
        })

        if ($itemBoxes.Count) { Update-CategoryState $catBox $itemBoxes } else { $catBox.IsChecked = $cat.Ticked }
        $script:UiState.CustomBoxes[$cat.Key] = @{ Category = $catBox; Items = $itemBoxes }
        $card.Child = $stack
        [void]$panel.Children.Add($card)
    }
}

$script:DriverSettingId = 'NoDriversFromWindowsUpdate'   # shown as its own footer checkbox

function Select-PresetInUi {
    param([string]$Key)
    $preset = $script:UiState.Presets | Where-Object Key -eq $Key
    $script:UiState.Preset = $preset
    $script:UiState.Config = Import-PowerShellDataFile $preset.Path
    Update-NormalPanel $script:UiState.Config $script:UiState.System
    Update-CustomPanel $script:UiState.Config $script:UiState.System
    $script:Ui.RestartCheck.IsChecked = [bool]$script:UiState.Config.Finish.Restart
    Update-OptionTooltips
    Set-OptionDefaults
    Update-ChoiceFeedback
}

function Update-OptionTooltips {
    # The two footer options explain themselves on hover
    $cleanup = $script:UiState.Config.Cleanup
    # Startup entries have technical names; show the app names people know
    $friendly = @{ GoogleDriveFS = 'Google Drive'; SteelSeriesGG = 'SteelSeries GG' }
    $kept = @($cleanup.KeepStartupApps | Where-Object { $_ } | ForEach-Object { if ($friendly[$_]) { $friendly[$_] } else { $_ } }) +
            'Riot Vanguard', 'Windows Security'
    $script:Ui.StartupCheck.ToolTip = "Apps installed by this setup won't start with Windows.`n" +
                                      "Always kept: $($kept -join ', ').`n" +
                                      "You can turn any app back on in Task Manager > Startup apps."
    $script:Ui.DriverCheck.ToolTip = if ($script:UiState.System.IsLaptop) {
        "Not available on laptops: Windows Update is often the only source of`nWi-Fi, touchpad and other laptop drivers."
    } else {
        "Windows Update stops installing drivers on this PC.`n" +
        "Graphics and chipset drivers then come from AMD, NVIDIA or Intel (see the Drivers step)."
    }
}

function Set-OptionDefaults {
    <#
        The footer options start the way the preset has them, in Normal and
        Custom install alike (like the preset's items in Custom).
    #>
    $config = $script:UiState.Config
    $script:Ui.StartupCheck.IsChecked = [bool]$config.Cleanup.DisableNewStartupApps
    $presetBlocksDrivers = [bool]$config.Settings.Enabled -and ($script:DriverSettingId -in $config.Settings.Apply)
    $script:Ui.DriverCheck.IsChecked = $presetBlocksDrivers -and -not $script:UiState.System.IsLaptop
    $script:Ui.DriverCheck.IsEnabled = -not $script:UiState.System.IsLaptop
    Set-StartupCheckAvailable
}

function Set-StartupCheckAvailable {
    # The startup-apps option only works when the Cleanup step runs
    $cleanupRuns = [bool]$script:UiState.Config.Cleanup.Enabled
    if ($script:Ui.CustomRadio.IsChecked -and $script:UiState.CustomBoxes['Cleanup']) {
        $cleanupRuns = $script:UiState.CustomBoxes['Cleanup'].Category.IsChecked -ne $false
    }
    $script:Ui.StartupCheck.IsEnabled = $cleanupRuns
}

function Update-CategoryState {
    # A step's checkbox shows ticked (all items), unticked (none) or partly selected ($null)
    param($CategoryBox, $Items)
    $on = @($Items | Where-Object { $_.IsChecked }).Count
    $CategoryBox.IsChecked = if ($on -eq 0) { $false } elseif ($on -eq $Items.Count) { $true } else { $null }
}

function Get-AllCustomBoxes {
    foreach ($b in $script:UiState.CustomBoxes.Values) { $b.Category; $b.Items }
}

function Update-SelectAllLabel {
    # Every "Select all" link says "Clear all" once everything it covers is ticked
    $all = @(Get-AllCustomBoxes)
    $everything = $all.Count -and -not ($all | Where-Object { $_.IsChecked -ne $true })
    $script:Ui.SelectAllButton.Content = if ($everything) { 'Clear all' } else { 'Select all' }
    foreach ($link in $script:UiState.BlockLinks) {
        $full = -not ($link.Tag.Items | Where-Object { $_.IsChecked -ne $true })
        $link.Content = if ($full) { 'Clear all' } else { 'Select all' }
    }
}

function Switch-SelectAll {
    # "Select all" ticks every step and item (including the optional apps); "Clear all" unticks them
    $select = $script:Ui.SelectAllButton.Content -eq 'Select all'
    foreach ($b in Get-AllCustomBoxes) { $b.IsChecked = $select }
    $script:Ui.StartupCheck.IsChecked = $select
    $script:Ui.DriverCheck.IsChecked  = $select -and $script:Ui.DriverCheck.IsEnabled
    Set-StartupCheckAvailable
    Update-ChoiceFeedback
}

function Get-SelectedConfig {
    <#
        The preset as the user chose to run it: a fresh copy of the preset,
        limited to what is ticked in Custom mode, plus the footer options.
    #>
    $config = Import-PowerShellDataFile $script:UiState.Preset.Path
    $config.Finish.Restart = [bool]$script:Ui.RestartCheck.IsChecked
    $config.Cleanup.DisableNewStartupApps = [bool]$script:Ui.StartupCheck.IsChecked
    if ($script:Ui.CustomRadio.IsChecked) { Limit-ConfigToCustomChoices $config }

    # The driver-updates option is its own checkbox: add or remove that one setting
    $config.Settings.Apply = @($config.Settings.Apply | Where-Object { $_ -and $_ -ne $script:DriverSettingId })
    if ($script:Ui.DriverCheck.IsChecked -and $script:Ui.DriverCheck.IsEnabled) {
        if (-not $config.Settings.Enabled) { $config.Settings.Enabled = $true; $config.Settings.Apply = @() }
        $config.Settings.Apply = @($config.Settings.Apply) + $script:DriverSettingId
    }
    if ($config.Settings.Enabled -and -not $config.Settings.Apply) { $config.Settings.Enabled = $false }
    $config
}

function Get-FirstById {
    # The first definition of each ticked Id, in the order given (the chosen preset comes first, so its details win)
    param($Definitions, [string[]]$Ids, [string]$IdField = 'Id')
    $seen = @{}
    foreach ($d in $Definitions) {
        if (-not $d) { continue }
        $id = [string]$d[$IdField]
        if ($id -in $Ids -and -not $seen[$id]) { $seen[$id] = $true; $d }
    }
}

function Limit-ConfigToCustomChoices {
    <#
        Custom install: the run gets exactly what's ticked. A ticked item can
        come from the chosen preset, another preset or the optional apps, so
        each one is looked up in all of them (the chosen preset first).
    #>
    param($config)
    $all = @($config) + @($script:UiState.Others)
    foreach ($key in 'Bloatware', 'Settings', 'Redistributables', 'Apps', 'Drivers', 'Cleanup') {
        $boxes = $script:UiState.CustomBoxes[$key]
        # Partly selected ($null) counts as "run this step with the ticked items"
        if (-not $boxes -or $boxes.Category.IsChecked -eq $false) {
            if ($config[$key]) { $config[$key].Enabled = $false }
            continue
        }
        # Ticked although the chosen preset doesn't have this step: take the step's options from a preset that does
        if (-not $config[$key]) { $config[$key] = (@($script:UiState.Others | Where-Object { $_[$key] }) | Select-Object -First 1)[$key] }
        $config[$key].Enabled = $true
        $chosen = @($boxes.Items | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag.Key })
        switch ($key) {
            'Bloatware' {
                $config.Bloatware.Apps        = @(Get-FirstById @($all | ForEach-Object { $_.Bloatware.Apps }) @($chosen -replace '^store:', ''))
                $config.Bloatware.ClassicApps = @(Get-FirstById @($all | ForEach-Object { $_.Bloatware.ClassicApps }) @($chosen -replace '^classic:', '') 'DisplayName')
                $config.Bloatware.RemoveOneDrive = 'onedrive' -in $chosen
            }
            'Settings'         { $config.Settings.Apply = $chosen }   # catalog order, as listed
            'Redistributables' { $config.Redistributables.Packages = @(Get-FirstById @($all | ForEach-Object { $_.Redistributables.Packages }) $chosen) }
            'Apps' {
                # Every app goes into the group it's listed under, with its full details (AsUser, Location, Source)
                $definitions = @(foreach ($cfg in $all) { foreach ($g in $cfg.Apps.Groups) { $g.Packages } }) +
                               @(foreach ($g in $script:UiState.Extras) { $g.Packages })
                $packages = @(Get-FirstById $definitions $chosen)
                $groups = [ordered]@{}
                foreach ($box in @($boxes.Items | Where-Object { $_.IsChecked })) {
                    $package = $packages | Where-Object Id -eq $box.Tag.Key | Select-Object -First 1
                    if (-not $package) { continue }
                    if (-not $groups.Contains($box.Tag.Group)) { $groups[$box.Tag.Group] = @() }
                    $groups[$box.Tag.Group] += $package
                }
                $config.Apps.Groups = @(foreach ($name in $groups.Keys) { @{ Name = $name; Packages = $groups[$name] } })
            }
            'Cleanup' {
                # Startup apps every preset keeps (so an app picked from another preset keeps its startup entry too)
                $config.Cleanup.KeepStartupApps = @($all | ForEach-Object { $_.Cleanup.KeepStartupApps } | Where-Object { $_ } | Select-Object -Unique)
            }
        }
        if ($boxes.Items.Count -and -not $chosen) { $config[$key].Enabled = $false }
    }
}

function Get-WorkEstimate {
    # Roughly how many result lines the run will produce, for the progress bar
    param($Config)
    $n = 4
    if ($Config.Bloatware.Enabled)        { $n += @($Config.Bloatware.Apps).Count + @($Config.Bloatware.ClassicApps).Count + 2 }
    if ($Config.Settings.Enabled)         { $n += @($Config.Settings.Apply).Count }
    if ($Config.Redistributables.Enabled) { $n += @($Config.Redistributables.Packages).Count }
    if ($Config.Apps.Enabled)             { foreach ($g in $Config.Apps.Groups) { $n += @($g.Packages).Count } }
    if ($Config.Drivers.Enabled)          { $n += 1 }
    if ($Config.Cleanup.Enabled)          { $n += 4 }
    [math]::Max($n, 1)
}

# ------------------------------------------------------------------
#  Progress page
# ------------------------------------------------------------------

function New-Row {
    param([string]$Type, [string]$Label, [string]$Value, [string]$Status)
    # Size must be a [double]: WPF silently ignores a whole number for FontSize
    $row = [ordered]@{ Icon = ''; IconColor = $script:Colors.Muted; Label = $Label; Value = $Value
                       LabelColor = $script:Colors.Text; ValueColor = $script:Colors.Muted; Weight = 'Normal'; Size = [double]14; Margin = '0,2'; Type = $Type }
    switch ($Type) {
        'Section' { $row.Weight = 'SemiBold'; $row.Size = [double]15; $row.LabelColor = $script:Colors.Accent; $row.Margin = '0,14,0,4' }
        'Pending' { $row.Icon = $script:Glyph.Pending; $row.IconColor = $script:Colors.Accent }
        'Item' {
            if (-not $Status) { $Status = 'Info' }
            $row.Icon = $script:Glyph[$Status]
            $row.IconColor = $script:Colors[$Status]
            if ($Status -in 'Warn', 'Fail') { $row.ValueColor = $script:Colors[$Status] }
            if ($Status -eq 'Ok') { $row.ValueColor = '#D0D0D0' }
        }
    }
    [pscustomobject]$row
}

function Add-LogRow {
    param($Event)
    $rows = $script:UiState.Rows
    $row  = New-Row $Event.Type $Event.Label $Event.Value $Event.Status
    $last = if ($rows.Count) { $rows[$rows.Count - 1] } else { $null }
    # A result replaces the "working..." line for the same item
    if ($last -and $last.Type -eq 'Pending' -and $last.Label -eq $Event.Label -and $Event.Type -in 'Pending', 'Item') {
        $rows[$rows.Count - 1] = $row
    } else {
        $rows.Add($row)
    }
}

# ------------------------------------------------------------------
#  Details panel (the full log, live)
# ------------------------------------------------------------------

function New-DetailsLine {
    # One log line, colored by what it says
    param([string]$Text)
    $message = $Text -replace '^\[\d\d:\d\d:\d\d\] ', ''
    $color = if ($message -match '^\[FAIL\]|^FATAL|^UI error') { $script:Colors.Fail }
             elseif ($message -match '^\[WARN\]') { $script:Colors.Warn }
             elseif ($message -match '^== ') { $script:Colors.Accent }
             elseif ($message -match '^\[SKIP\]|^\[ -- \]|^\s+\|') { '#8A8A8A' }   # skipped, info and winget's own output
             else { '#D0D0D0' }
    [pscustomobject]@{ Text = $Text; Color = $color }
}

function Test-ScrolledToEnd {
    param($ScrollViewer)
    (-not $ScrollViewer) -or ($ScrollViewer.VerticalOffset -ge $ScrollViewer.ScrollableHeight - 4)
}

function Start-Details {
    # Fills the panel with what the log file has so far; new lines then come through the queue
    $s = $script:UiState
    $s.Lines = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    if ($script:Setup.LogFile -and (Test-Path $script:Setup.LogFile)) {
        foreach ($line in (Get-Content $script:Setup.LogFile -ErrorAction SilentlyContinue)) { $s.Lines.Add((New-DetailsLine $line)) }
    }
    $script:Setup.LogQueue = $s.Queue   # the window's own log lines (Common.ps1 Write-Log)
    $script:Ui.DetailsList.ItemsSource = $s.Lines
    $script:Ui.DetailsButton.Visibility = 'Visible'
}

function Switch-Details {
    # "Show details" / "Hide details": the panel shares the space with the progress or finish view
    $open = $script:Ui.DetailsPanel.Visibility -ne 'Visible'
    $script:Ui.DetailsPanel.Visibility = if ($open) { 'Visible' } else { 'Collapsed' }
    $script:Ui.DetailsRow.Height = if ($open) { New-Object System.Windows.GridLength 1, 'Star' } else { [System.Windows.GridLength]::Auto }
    $script:Ui.DetailsButton.Content = if ($open) { 'Hide details' } else { 'Show details' }
    $lines = $script:UiState.Lines
    if ($open -and $lines.Count) {
        $script:Ui.DetailsList.UpdateLayout()
        $script:Ui.DetailsList.ScrollIntoView($lines[$lines.Count - 1])
    }
}

function Copy-DetailsLog {
    $lines = $script:UiState.Lines
    if (-not $lines -or -not $lines.Count) { return }
    [System.Windows.Clipboard]::SetText((@($lines | ForEach-Object Text) -join "`r`n"))
    # Short feedback on the button itself
    $script:Ui.CopyLogButton.Content = 'Copied'
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(2)
    $timer.Add_Tick({ $this.Stop(); $script:Ui.CopyLogButton.Content = 'Copy' })
    $timer.Start()
}

function Receive-EngineEvents {
    # Called by the timer: moves everything the engine reported onto the screen
    $s = $script:UiState
    $atEnd = Test-ScrolledToEnd $s.LogScroll
    if (-not $s.DetailsScroll -and $script:Ui.DetailsPanel.Visibility -eq 'Visible') { $s.DetailsScroll = Get-ScrollViewer $script:Ui.DetailsList }
    $detailsAtEnd = Test-ScrolledToEnd $s.DetailsScroll
    $newLines = 0

    $event = $null
    $handled = 0
    while ($handled -lt 300 -and $s.Queue.TryDequeue([ref]$event)) {
        $handled++
        switch ($event.Type) {
            'Log' { $s.Lines.Add((New-DetailsLine $event.Value)); $newLines++ }
            'Section' { $script:Ui.StepText.Text = $event.Label; Add-LogRow $event }
            'Pending' { Add-LogRow $event }
            'Item' {
                Add-LogRow $event
                if ($event.Status -ne 'Info') {
                    $s.Completed++
                    $script:Ui.Progress.Value = [math]::Min(98, 100 * $s.Completed / $s.Estimate)
                }
            }
            'Done'  { Show-Finish -Summary $event.Summary }
            'Error' { Show-Finish -ErrorMessage $event.Value }
        }
    }
    if ($handled -and $atEnd -and $s.Rows.Count) { $script:Ui.LogList.ScrollIntoView($s.Rows[$s.Rows.Count - 1]) }
    if ($handled -and -not $s.LogScroll) { $s.LogScroll = Get-ScrollViewer $script:Ui.LogList }
    # The Details panel follows new lines too, unless the person scrolled up to read
    if ($newLines -and $detailsAtEnd -and $script:Ui.DetailsPanel.Visibility -eq 'Visible') {
        $script:Ui.DetailsList.ScrollIntoView($s.Lines[$s.Lines.Count - 1])
    }

    if ($s.Running) {
        $elapsed = (Get-Date) - $s.StartedAt
        $script:Ui.ElapsedText.Text = '{0}:{1:00}' -f [int][math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds
        # The engine stopped without saying why (should not happen, but never hang)
        if ($s.Handle.IsCompleted -and $s.Queue.IsEmpty -and $s.Running) {
            $err = @($s.PowerShell.Streams.Error | ForEach-Object { $_.ToString() }) -join ' '
            Show-Finish -ErrorMessage $(if ($err) { $err } else { 'The setup stopped unexpectedly.' })
        }
    }
}

function Start-Engine {
    $config = Get-SelectedConfig
    # The footer driver option alone is also something to do
    if (-not (Get-Categories $config) -and -not $config.Settings.Enabled) {
        $script:Ui.FooterText.Text = '  Tick at least one step first.'
        $script:Ui.FooterText.Foreground = $script:Colors.Fail
        return
    }
    $script:Ui.FooterText.Text = ''
    if (-not (Show-StartConfirmation $config)) { return }

    # In Krimz's Toolkit the log starts here, so just opening the toolkit leaves no log on the desktop
    if (-not $script:Setup.LogFile) {
        Initialize-Log
        Write-Log "Windows Setup $($script:SetupVersion) started from Krimz's Toolkit (dry run: $($script:Setup.DryRun))"
    }
    $s = $script:UiState
    $s.Config    = $config
    $s.Estimate  = Get-WorkEstimate $config
    $s.Completed = 0
    $s.StartedAt = Get-Date
    $s.Running   = $true
    $s.Queue     = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
    $s.Rows      = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
    $script:Ui.LogList.ItemsSource = $s.Rows
    Start-Details
    Write-Log "Window: starting '$($config.Name)' ($(if ($script:Ui.CustomRadio.IsChecked) { 'custom' } else { 'normal' }))"

    Show-Page 'Progress'
    $script:Ui.SubtitleText.Text = "$($config.Name) - you can leave the PC alone now."
    $script:Ui.RestartCheck.Visibility = 'Collapsed'
    $script:Ui.StartupCheck.Visibility = 'Collapsed'
    $script:Ui.DriverCheck.Visibility = 'Collapsed'
    $script:Ui.FooterText.Text = ''
    $script:Ui.PrimaryButton.Visibility = 'Collapsed'
    $script:Ui.SecondaryButton.Content = 'Cancel'
    $script:Ui.SecondaryButton.Visibility = 'Visible'
    $script:Ui.LogButton.Visibility = 'Visible'

    # The engine runs in its own runspace, so the window stays responsive
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.ExecutionPolicy = 'Bypass'
    $runspace = [runspacefactory]::CreateRunspace($iss)
    $runspace.ApartmentState = 'STA'
    $runspace.ThreadOptions  = 'ReuseThread'
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    [void]$ps.AddCommand((Join-Path $s.Root 'modules\Run-Engine.ps1')).
        AddParameter('Root', $s.Root).AddParameter('Config', $config).AddParameter('System', $s.System).
        AddParameter('LogFile', $script:Setup.LogFile).AddParameter('DryRun', [bool]$script:Setup.DryRun).
        AddParameter('UiQueue', $s.Queue)
    $s.PowerShell = $ps
    $s.Handle = $ps.BeginInvoke()

    $s.Timer = New-Object System.Windows.Threading.DispatcherTimer
    $s.Timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $s.Timer.Add_Tick({ Invoke-UiSafely { Receive-EngineEvents } })
    $s.Timer.Start()
    Set-SetupBusy $true
}

function Stop-Engine {
    # Stops the background work; whatever finished already stays done
    $s = $script:UiState
    if (-not $s.Running) { return }
    Write-Log 'Window: setup cancelled by user'
    try { [void]$s.PowerShell.BeginStop($null, $null) } catch { }
    # Background downloads are child processes of this program; stop them too
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='winget.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Show-Finish -Cancelled
}

# ------------------------------------------------------------------
#  Finish page
# ------------------------------------------------------------------

function Show-Finish {
    param($Summary, [string]$ErrorMessage, [switch]$Cancelled)
    $s = $script:UiState
    if (-not $s.Running) { return }
    $s.Running = $false
    Set-SetupBusy $false
    $script:Ui.Progress.Value = 100

    # Counts come from the rows on screen, so they also work after an error or cancel
    $results = @($s.Rows | Where-Object Type -eq 'Item')
    $count = { param($glyph) @($results | Where-Object Icon -eq $glyph).Count }
    $script:Ui.OkCount.Text   = & $count $script:Glyph.Ok
    $script:Ui.SkipCount.Text = & $count $script:Glyph.Skip
    $script:Ui.WarnCount.Text = & $count $script:Glyph.Warn
    $script:Ui.FailCount.Text = & $count $script:Glyph.Fail
    $failed = [int]$script:Ui.FailCount.Text
    $minutes = [math]::Round(((Get-Date) - $s.StartedAt).TotalMinutes, 1)

    $problems = $script:Ui.ProblemsPanel
    $problems.Children.Clear()
    $bad = @($results | Where-Object { $_.Icon -in $script:Glyph.Warn, $script:Glyph.Fail })
    if ($bad) {
        [void]$problems.Children.Add((New-Text 'NEEDS A LOOK' $script:Colors.Muted 12 -Margin '0,0,0,8'))
        foreach ($b in $bad) {
            $line = New-Object System.Windows.Controls.StackPanel
            $line.Orientation = 'Horizontal'
            $line.Margin = '0,3'
            [void]$line.Children.Add((New-Icon $b.Icon $b.IconColor 13))
            [void]$line.Children.Add((New-Text "$($b.Label): $($b.Value)" -Margin '10,0,0,0'))
            [void]$problems.Children.Add($line)
        }
    } else {
        [void]$problems.Children.Add((New-Text 'Everything went fine. Nothing needs your attention.' $script:Colors.Muted))
    }

    $badge = $script:Ui.ResultBadge; $icon = $script:Ui.ResultIcon
    if ($ErrorMessage -or $Cancelled) {
        $badge.Background = '#3A1F22'; $icon.Text = $script:Glyph.Fail; $icon.Foreground = $script:Colors.Fail
        $script:Ui.ResultTitle.Text = if ($Cancelled) { 'Setup cancelled' } else { 'Setup stopped' }
        $script:Ui.ResultSubtitle.Text = if ($Cancelled) { 'Everything finished before you cancelled stays done.' } else { $ErrorMessage }
    } elseif ($failed) {
        $badge.Background = '#3A3415'; $icon.Text = $script:Glyph.Warn; $icon.Foreground = $script:Colors.Warn
        $script:Ui.ResultTitle.Text = 'Setup finished with problems'
        $script:Ui.ResultSubtitle.Text = "Done in $minutes min. Check the list below."
    } else {
        $script:Ui.ResultTitle.Text = 'Setup finished'
        $script:Ui.ResultSubtitle.Text = "Done in $minutes min."
    }
    Write-Log "Window: finished (error: $ErrorMessage, cancelled: $Cancelled)"

    Show-Page 'Finish'
    $script:Ui.SubtitleText.Text = $s.Config.Name
    $script:Ui.SecondaryButton.Visibility = 'Collapsed'
    $script:Ui.PrimaryButton.Visibility = 'Visible'

    $restart = $s.Config.Finish.Restart -and -not $ErrorMessage -and -not $Cancelled
    if ($restart -and -not $script:Setup.DryRun) {
        Start-RestartCountdown ([int]$s.Config.Finish.CountdownSeconds)
    } elseif ($restart) {
        $script:Ui.FooterText.Text = 'Dry run: the PC would restart now.'
        $script:Ui.PrimaryButton.Content = 'Close'
    } else {
        $script:Ui.FooterText.Text = if ($ErrorMessage -or $Cancelled) { '' } else { 'Restart the PC to finish setup.' }
        $script:Ui.PrimaryButton.Content = 'Close'
    }
    $script:Ui.FooterText.Foreground = $script:Colors.Muted
}

function Start-RestartCountdown {
    param([int]$Seconds = 60)
    $s = $script:UiState
    $s.SecondsLeft = [math]::Max($Seconds, 5)
    $script:Ui.PrimaryButton.Content = 'Restart now'
    $script:Ui.SecondaryButton.Content = 'Don''t restart'
    $script:Ui.SecondaryButton.Visibility = 'Visible'
    $script:Ui.FooterText.Text = "Restarting in $($s.SecondsLeft) seconds to finish setup."

    $s.Countdown = New-Object System.Windows.Threading.DispatcherTimer
    $s.Countdown.Interval = [TimeSpan]::FromSeconds(1)
    $s.Countdown.Add_Tick({
        Invoke-UiSafely {
            $s = $script:UiState
            $s.SecondsLeft--
            if ($s.SecondsLeft -le 0) { Invoke-Restart; return }
            $script:Ui.FooterText.Text = "Restarting in $($s.SecondsLeft) seconds to finish setup."
        }
    })
    $s.Countdown.Start()
    Set-SetupBusy $true
}

function Stop-RestartCountdown {
    $s = $script:UiState
    if ($s.Countdown) { $s.Countdown.Stop(); $s.Countdown = $null }
    Set-SetupBusy $false
    $script:Ui.FooterText.Text = 'Restart the PC yourself to finish setup.'
    $script:Ui.SecondaryButton.Visibility = 'Collapsed'
    $script:Ui.PrimaryButton.Content = 'Close'
    Write-Log 'Window: restart cancelled by user'
}

function Invoke-Restart {
    Stop-RestartCountdown
    Write-Log 'Restarting'
    Restart-Computer -Force
}

# ------------------------------------------------------------------
#  Start confirmation
# ------------------------------------------------------------------

function Show-StartConfirmation {
    <#
        "Start the setup?" with a short summary of what will run. Returns
        $true only when the person presses Start setup.
    #>
    param($Config)

    [xml]$xaml = Get-Content (Join-Path $script:UiState.Root 'ui\ConfirmDialog.xaml') -Raw -Encoding UTF8
    $dialog = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $owner = [System.Windows.Window]::GetWindow($script:Ui.Page)
    if ($owner) { $dialog.Owner = $owner }

    $mode = if ($script:Ui.CustomRadio.IsChecked) { 'custom install' } else { 'normal install' }
    $dialog.FindName('IntroText').Text = "$($Config.Name), $mode. Nothing has been changed yet."

    # The steps that will run, with how many items each has
    $steps = $dialog.FindName('StepsPanel')
    $lines = @(foreach ($cat in Get-Categories $Config) {
        $count = @($cat.Items).Count
        $detail = if ($count) { "$count $($cat.Unit)" } else { '' }
        @{ Glyph = $script:Glyph[$cat.Key]; Title = $cat.Title; Detail = $detail }
    })
    if ($Config.Settings.Enabled -and $script:DriverSettingId -in $Config.Settings.Apply) {
        $lines += @{ Glyph = $script:Glyph.Drivers; Title = 'Turn off driver updates from Windows Update'; Detail = '' }
    }
    if ($Config.Cleanup.Enabled -and $Config.Cleanup.DisableNewStartupApps) {
        $lines += @{ Glyph = $script:Glyph.Cleanup; Title = 'Stop new apps from starting with Windows'; Detail = '' }
    }
    foreach ($line in $lines) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,3'
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = '30' }))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
        $icon = New-Icon $line.Glyph $script:Colors.Accent 15
        $title = New-Text $line.Title -Size 13.5
        $title.VerticalAlignment = 'Center'
        $detail = New-Text $line.Detail $script:Colors.Muted 13 -Margin '12,0,0,0'
        $detail.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($title, 1)
        [System.Windows.Controls.Grid]::SetColumn($detail, 2)
        [void]$row.Children.Add($icon); [void]$row.Children.Add($title); [void]$row.Children.Add($detail)
        [void]$steps.Children.Add($row)
    }

    # What to expect
    $facts = $dialog.FindName('FactsPanel')
    $mb = Get-DownloadEstimateMB $Config
    $download = if ($mb -lt 1) { 'Nothing to download' } elseif ($mb -lt 1000) { 'About {0:N0} MB to download' -f $mb } else { 'About {0:N1} GB to download' -f ($mb / 1024) }
    $restart  = if ($Config.Finish.Restart) { 'The PC restarts when it''s done (you can stop that)' } else { 'The PC doesn''t restart by itself' }
    foreach ($fact in @(
        @{ Glyph = [char]0xE896; Text = $download }
        @{ Glyph = [char]0xE777; Text = $restart }
        @{ Glyph = [char]0xE81C; Text = 'A restore point is made first. You can cancel while it runs; finished steps stay done.' }
    )) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,3'
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = '30' }))
        $row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $icon = New-Icon $fact.Glyph $script:Colors.Muted 14
        $icon.VerticalAlignment = 'Top'; $icon.Margin = '0,2,0,0'
        $text = New-Text $fact.Text $script:Colors.Muted 13
        [System.Windows.Controls.Grid]::SetColumn($text, 1)
        [void]$row.Children.Add($icon); [void]$row.Children.Add($text)
        [void]$facts.Children.Add($row)
    }
    if ($script:Setup.DryRun) { $dialog.FindName('DryRunNote').Visibility = 'Visible' }

    $dialog.FindName('ConfirmButton').Add_Click({ [System.Windows.Window]::GetWindow($this).DialogResult = $true })
    $dialog.Add_MouseLeftButtonDown({ try { $this.DragMove() } catch { } })
    $dialog.Add_ContentRendered({ $this.FindName('CancelButton').Focus() | Out-Null })
    [bool]$dialog.ShowDialog()
}

# ------------------------------------------------------------------
#  Page and window
# ------------------------------------------------------------------

function Set-SetupBusy {
    # Tells Krimz's Toolkit (if the page is shown there) that setup is working
    param([bool]$Busy)
    if ($script:UiState.OnBusy) { try { & $script:UiState.OnBusy $Busy } catch { } }
}

function Import-SetupTheme {
    # The shared look (Theme.xaml) becomes the application's resources, so the
    # page and the dialog find its styles. Krimz's Toolkit does this itself.
    param([string]$Root)
    [xml]$xaml = Get-Content (Join-Path $Root 'ui\Theme.xaml') -Raw -Encoding UTF8
    $theme = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $app = [System.Windows.Application]::Current
    if (-not $app) { $app = New-Object System.Windows.Application }
    $app.ShutdownMode = 'OnExplicitShutdown'
    $app.Resources = $theme
}

function New-SetupPage {
    <#
        Builds the Windows Setup page (ui\Page.xaml) and wires it up. Used by
        the standalone window below and by Krimz's Toolkit (modules\Page.ps1).
        -OnBusy is called with $true / $false when setup starts and stops.
    #>
    param([string]$Root, [string]$Version, $System, [scriptblock]$OnBusy)

    [xml]$xaml = Get-Content (Join-Path $Root 'ui\Page.xaml') -Raw -Encoding UTF8
    $page = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $script:Ui.Page = $page
    $xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
        $name = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        if ($name) { $script:Ui[$name] = $page.FindName($name) }
    }

    $s = $script:UiState
    $s.Root    = $Root
    $s.System  = $System
    $s.Running = $false
    $s.OnBusy  = $OnBusy
    $s.Presets = @(Get-Presets $Root)
    $s.Extras  = @(Get-ExtraApps $Root)
    $sizeFile = Join-Path $Root 'catalog\DownloadSizes.psd1'
    $s.Sizes   = if (Test-Path $sizeFile) { Import-PowerShellDataFile $sizeFile } else { @{} }

    $script:Ui.VersionText.Text = "v$Version"
    if ($script:Setup.DryRun) { $script:Ui.DryRunBadge.Visibility = 'Visible' }

    # "Your PC" card: a small two-column table
    # (an ordered hashtable keeps the pairs together; nested arrays would get flattened)
    $pc = [ordered]@{
        'CPU'      = $System.Cpu.Name -replace '\s+\d+-Core Processor$', '' -replace '\s{2,}', ' '
        'Graphics' = @($System.Gpus | ForEach-Object Name) -join ', '
        'Type'     = $(if ($System.IsLaptop) { 'Laptop' } else { 'Desktop' }) + $(if ($System.IsVM) { ' (virtual machine)' })
        'Windows'  = "$($System.Windows.Name -replace '^Windows ', '') $($System.Windows.Version)"
    }
    $table = New-Object System.Windows.Controls.Grid
    $table.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{ Width = '72' }))
    $table.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $row = 0
    foreach ($entry in $pc.GetEnumerator()) {
        $table.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
        $name  = New-Text $entry.Key $script:Colors.Muted 12.5 -Margin '0,3'
        $value = New-Text $entry.Value -Size 13 -Margin '0,3'
        [System.Windows.Controls.Grid]::SetRow($name, $row);  [System.Windows.Controls.Grid]::SetRow($value, $row)
        [System.Windows.Controls.Grid]::SetColumn($value, 1)
        [void]$table.Children.Add($name); [void]$table.Children.Add($value)
        $row++
    }
    [void]$script:Ui.PcInfoPanel.Children.Add($table)

    # One card per preset
    foreach ($p in $s.Presets) {
        $radio = New-Object System.Windows.Controls.RadioButton
        $radio.Style = $page.FindResource('CardRadio')
        $radio.GroupName = 'Preset'
        $radio.Tag = $p.Key
        $text = New-Object System.Windows.Controls.StackPanel
        $text.VerticalAlignment = 'Center'
        [void]$text.Children.Add((New-Text $p.Name -Weight 'SemiBold'))
        [void]$text.Children.Add((New-Text $p.Description $script:Colors.Muted 12))
        # Optional picture on the right (Image in the preset file), sized like the Custom install card's
        $content = New-Object System.Windows.Controls.DockPanel
        $picture = Get-CardImage $Root $p.Image
        if ($picture) {
            $image = New-Object System.Windows.Controls.Image -Property @{ Source = $picture; Height = 36; Margin = '12,0,0,0' }
            [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($image, 'HighQuality')
            [System.Windows.Controls.DockPanel]::SetDock($image, 'Right')
            [void]$content.Children.Add($image)
        }
        [void]$content.Children.Add($text)
        $radio.Content = $content
        $radio.Add_Checked({ Invoke-UiSafely { Select-PresetInUi $this.Tag } })
        [void]$script:Ui.PresetPanel.Children.Add($radio)
    }
    $script:Ui.PresetPanel.Children[0].IsChecked = $true
    $picture = Get-CardImage $Root 'Custom.png'
    if ($picture) { $script:Ui.CustomImage.Source = $picture; $script:Ui.CustomImage.Visibility = 'Visible' }

    $script:Ui.NormalRadio.Add_Checked({
        $script:Ui.NormalPanel.Visibility = 'Visible'; $script:Ui.CustomPanel.Visibility = 'Collapsed'
        $script:Ui.SelectAllButton.Visibility = 'Collapsed'
        $script:Ui.RightTitle.Text = 'WHAT WILL HAPPEN'
        Invoke-UiSafely { Set-OptionDefaults; Update-SizeEstimate }
    })
    $script:Ui.CustomRadio.Add_Checked({
        $script:Ui.NormalPanel.Visibility = 'Collapsed'; $script:Ui.CustomPanel.Visibility = 'Visible'
        $script:Ui.SelectAllButton.Visibility = 'Visible'
        $script:Ui.RightTitle.Text = 'PICK WHAT RUNS'
        Invoke-UiSafely { Set-OptionDefaults; Update-ChoiceFeedback }
    })
    $script:Ui.SelectAllButton.Add_Click({ Invoke-UiSafely { Switch-SelectAll } })

    $script:Ui.PrimaryButton.Add_Click({
        Invoke-UiSafely {
            $s = $script:UiState
            if (-not $s.StartedAt)       { Start-Engine }                    # Start page
            elseif ($s.Countdown)        { Invoke-Restart }                  # "Restart now"
            else                         { [System.Windows.Window]::GetWindow($script:Ui.Page).Close() }   # "Close"
        }
    })
    $script:Ui.SecondaryButton.Add_Click({
        Invoke-UiSafely {
            $s = $script:UiState
            if ($s.Running) {
                $answer = [System.Windows.MessageBox]::Show('Stop the setup? Everything finished so far stays done.', 'Windows Setup', 'YesNo', 'Question')
                if ($answer -eq 'Yes') { Stop-Engine }
            } elseif ($s.Countdown) {
                Stop-RestartCountdown
            }
        }
    })
    $script:Ui.LogButton.Add_Click({ Invoke-UiSafely { Start-Process notepad.exe -ArgumentList "`"$($script:Setup.LogFile)`"" } })
    $script:Ui.DetailsButton.Add_Click({ Invoke-UiSafely { Switch-Details } })
    $script:Ui.CopyLogButton.Add_Click({ Invoke-UiSafely { Copy-DetailsLog } })

    $page
}

function Test-SetupCanClose {
    # Asked before the window closes. While setup runs, the person decides.
    $s = $script:UiState
    if ($s.Running) {
        $answer = [System.Windows.MessageBox]::Show('Setup is still running. Stop it and close?', 'Windows Setup', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return $false }
        Stop-Engine
    }
    $true
}

function Close-SetupPage {
    # The window is closing: stop the timers
    $s = $script:UiState
    if ($s.Countdown) { $s.Countdown.Stop() }
    if ($s.Timer) { $s.Timer.Stop() }
}

function Show-SetupWindow {
    # The standalone window. -NoShow builds it without opening it (used for automated screenshots)
    param([string]$Root, [string]$Version, $System, [switch]$NoShow)

    Enable-DpiAwareness
    Import-SetupTheme $Root
    [xml]$xaml = Get-Content (Join-Path $Root 'ui\MainWindow.xaml') -Raw -Encoding UTF8
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $script:Ui.Window = $window
    $window.Content = New-SetupPage -Root $Root -Version $Version -System $System

    # Dark title bar to match the window (Windows 10 2004+ / Windows 11)
    $window.Add_SourceInitialized({
        try {
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper $script:Ui.Window).Handle
            $on = 1
            [void][WindowsSetup.Dpi]::DwmSetWindowAttribute($hwnd, 20, [ref]$on, 4)
        } catch { }
    })

    $window.Add_Closing({
        param($sender, $e)
        if (-not (Test-SetupCanClose)) { $e.Cancel = $true; return }
        Close-SetupPage
    })

    if ($NoShow) { return $window }
    [void]$window.ShowDialog()
}
