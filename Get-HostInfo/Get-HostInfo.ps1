$results = @()

# 1. Motherboard
$board = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
$results += [PSCustomObject]@{
    Item = "Motherboard"
    'Vender / Model' = "$($board.Manufacturer) / $($board.Product)"
    Detail = "Motherboard of the host"
    Qty = 1
}

# 2. Operation System
$os = Get-CimInstance Win32_OperatingSystem
$vendor = "Microsoft Windows"
$results += [PSCustomObject]@{
    Item = "Operation System"
    'Vender / Model' = $vendor
    Detail = $os.Caption
    Qty = 1
}

# 3. CPU
$cpus = Get-CimInstance Win32_Processor
$cpuGroup = $cpus | Group-Object Name
foreach ($g in $cpuGroup) {
    $cpu = $g.Group[0]
    $results += [PSCustomObject]@{
        Item = "CPU"
        'Vender / Model' = $cpu.Manufacturer
        Detail = $cpu.Name.Trim()
        Qty = $g.Count
    }
}

# 4. Memory
$memories = Get-CimInstance Win32_PhysicalMemory
$memGroup = $memories | Group-Object PartNumber
foreach ($g in $memGroup) {
    $mem = $g.Group[0]
    $capacityGB = [math]::Round($mem.Capacity / 1GB)
    $speed = $mem.Speed
    $detail = "Speed ${speed}MHz, ${capacityGB}GB"
    
    # 處理可能為空白的屬性
    $part = if ($mem.PartNumber) { $mem.PartNumber.Trim() } else { "Unknown" }
    $vender = if ($mem.Manufacturer) { $mem.Manufacturer.Trim() } else { "Unknown" }
    
    $results += [PSCustomObject]@{
        Item = "Memory"
        'Vender / Model' = "$vender / $part"
        Detail = $detail
        Qty = $g.Count
    }
}

# 5. Hard Disk Drive
$disks = Get-CimInstance Win32_DiskDrive
$diskGroup = $disks | Group-Object Model
foreach ($g in $diskGroup) {
    $disk = $g.Group[0]
    $sizeGB = [math]::Round($disk.Size / 1GB)
    $type = $disk.InterfaceType
    $results += [PSCustomObject]@{
        Item = "Hard Disk Drive"
        'Vender / Model' = $disk.Model
        Detail = "$type / ${sizeGB}GB"
        Qty = $g.Count
    }
}

# 在畫面上顯示表格
$results | Format-Table -AutoSize

# 匯出成 CSV 檔案 (會存檔在目前 PowerShell 所在的目錄)
$csvPath = "$PWD\HostConfiguration.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "✅ 資訊已成功匯出至: $csvPath" -ForegroundColor Green