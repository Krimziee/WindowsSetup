<#
    Drivers, based on the detected hardware.

    AMD and NVIDIA don't allow scripted driver downloads that we can rely
    on, so their official driver page opens right after the restart.
    Intel's own Driver & Support Assistant is installed with winget.
    Laptops keep getting drivers from Windows Update (see Settings).
#>

$script:DriverPages = @{
    AMD    = 'https://www.amd.com/en/support/download/drivers.html'
    NVIDIA = 'https://www.nvidia.com/en-us/software/nvidia-app/'
}

function Add-OpenAfterRestart {
    <#
        Opens a web page once, the next time this user signs in. RunOnce
        entries are deleted by Windows after they run.
    #>
    param([string]$Name, [string]$Url)
    Set-RegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' "WindowsSetup-$Name" "explorer.exe `"$Url`"" 'String'
}

function Invoke-DriverSetup {
    param($Config, $System)

    Write-Section 'Drivers'

    if ($System.IsVM) {
        Write-Item 'Drivers' 'Not needed in a virtual machine' 'Skip'
        return
    }

    # Vendors that need drivers: every real GPU, plus the CPU (chipset drivers)
    $vendors = @($System.Gpus | Where-Object Vendor -ne 'Other' | ForEach-Object Vendor) + $System.Cpu.Vendor |
               Where-Object { $_ -in 'AMD', 'NVIDIA', 'Intel' } | Select-Object -Unique

    foreach ($vendor in $vendors) {
        switch ($vendor) {
            'Intel' {
                # Intel's assistant finds drivers for Intel CPUs, graphics, Wi-Fi and Bluetooth
                Install-WingetPackage @{ Id = 'Intel.IntelDriverAndSupportAssistant'; Name = 'Intel Driver & Support Assistant' }
            }
            default {
                try {
                    Add-OpenAfterRestart $vendor $script:DriverPages[$vendor]
                    $what = if ($vendor -eq 'AMD') { 'AMD drivers (graphics + chipset)' } else { 'NVIDIA drivers' }
                    Write-Item $what 'Download page opens after the restart' 'Ok'
                } catch {
                    Write-Log "Scheduling the $vendor page failed: $($_.Exception.Message)"
                    Write-Item "$vendor drivers" "Get them from $($script:DriverPages[$vendor])" 'Warn'
                }
            }
        }
    }

    if ($System.IsLaptop) {
        Write-Item 'Laptop drivers' 'Windows Update will install them' 'Info'
    }
}
