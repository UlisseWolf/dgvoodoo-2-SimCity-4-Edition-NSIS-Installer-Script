param(
    [switch]$Pause
)

$vendors = New-Object System.Collections.Generic.List[string]

function Add-Vendor {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    if ($Value -match 'VEN_10DE|NVIDIA') {
        if (-not $vendors.Contains('NVIDIA')) {
            [void]$vendors.Add('NVIDIA')
        }
    }

    if ($Value -match 'VEN_1002|VEN_1022|AMD|Radeon|ATI|Advanced Micro Devices') {
        if (-not $vendors.Contains('AMD')) {
            [void]$vendors.Add('AMD')
        }
    }

    if ($Value -match 'VEN_8086|Intel') {
        if (-not $vendors.Contains('Intel')) {
            [void]$vendors.Add('Intel')
        }
    }
}

try {
    Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
        Add-Vendor $_.Name
        Add-Vendor $_.PNPDeviceID
        Add-Vendor $_.AdapterCompatibility
    }
} catch {
    try {
        Get-WmiObject Win32_VideoController -ErrorAction Stop | ForEach-Object {
            Add-Vendor $_.Name
            Add-Vendor $_.PNPDeviceID
            Add-Vendor $_.AdapterCompatibility
        }
    } catch {
    }
}

if (-not $vendors.Count) {
    try {
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Video' -ErrorAction Stop | ForEach-Object {
            Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $p = Get-ItemProperty $_.PSPath -ErrorAction Stop
                    Add-Vendor $p.DriverDesc
                    Add-Vendor $p.MatchingDeviceId
                    Add-Vendor $p.ProviderName
                } catch {
                }
            }
        }
    } catch {
    }
}

$result = if ($vendors.Count) {
    $vendors -join ', '
} else {
    'Unknown'
}

[Console]::Out.WriteLine($result)

if ($Pause) {
    Write-Host ''
    Read-Host 'Press Enter to close' | Out-Null
}
