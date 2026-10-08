<#
    Detects the PC's hardware and Windows version.
    Other modules use the result to decide what to do (drivers, power plan...).
#>

function Get-CpuInfo {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $vendor = switch -Wildcard ($cpu.Manufacturer) {
        'AuthenticAMD' { 'AMD' }
        'GenuineIntel' { 'Intel' }
        default        { 'Other' }
    }
    [pscustomobject]@{ Name = $cpu.Name.Trim(); Vendor = $vendor }
}

function Get-GpuInfo {
    # The vendor is read from the PCI ID, which is more reliable than the name
    foreach ($gpu in Get-CimInstance Win32_VideoController) {
        $vendor = switch -Regex ($gpu.PNPDeviceID) {
            'VEN_10DE' { 'NVIDIA'; break }
            'VEN_1002' { 'AMD'; break }
            'VEN_8086' { 'Intel'; break }
            default    { 'Other' }
        }
        [pscustomobject]@{ Name = $gpu.Name; Vendor = $vendor }
    }
}

function Test-IsLaptop {
    # A PC counts as a laptop if ANY of the three checks says so
    $laptopChassis = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
    $chassis    = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
    $systemType = (Get-CimInstance Win32_ComputerSystem).PCSystemType
    $hasBattery = [bool](Get-CimInstance Win32_Battery)

    [bool](($chassis | Where-Object { $_ -in $laptopChassis }) -or $systemType -eq 2 -or $hasBattery)
}

function Test-VirtualMachine {
    $cs = Get-CimInstance Win32_ComputerSystem
    "$($cs.Manufacturer) $($cs.Model)" -match 'VirtualBox|innotek|VMware|Virtual Machine|QEMU|KVM|Parallels'
}

function Get-WindowsInfo {
    $os  = Get-CimInstance Win32_OperatingSystem
    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{
        Name    = $os.Caption -replace '^Microsoft ', ''
        Version = $reg.DisplayVersion
        Build   = [int]$os.BuildNumber
        IsWin11 = [int]$os.BuildNumber -ge 22000
    }
}

function Get-SystemInfo {
    [pscustomobject]@{
        Cpu      = Get-CpuInfo
        Gpus     = @(Get-GpuInfo)
        IsLaptop = Test-IsLaptop
        IsVM     = Test-VirtualMachine
        Windows  = Get-WindowsInfo
    }
}

function Show-SystemInfo {
    param($System)
    Write-Section 'Your PC'
    Write-Item 'CPU' "$($System.Cpu.Name)  ($($System.Cpu.Vendor))"
    foreach ($gpu in $System.Gpus) { Write-Item 'GPU' "$($gpu.Name)  ($($gpu.Vendor))" }
    Write-Item 'Type' $(if ($System.IsLaptop) { 'Laptop' } else { 'Desktop' })
    if ($System.IsVM) { Write-Item 'Virtual machine' 'Yes (test environment)' }
    Write-Item 'Windows' "$($System.Windows.Name) $($System.Windows.Version)  (build $($System.Windows.Build))"
}
