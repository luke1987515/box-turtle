# ==========================================
# 1. 初始化與互動詢問
# ==========================================
$currentDir = Get-Location
$expectedDiskCount = Read-Host "請輸入預期的磁碟數量 (例如: 78)"

# 驗證輸入是否為數字
if ($expectedDiskCount -match '^\d+$') {
    $expectedDiskCount = [int]$expectedDiskCount
} else {
    Write-Host "輸入錯誤：請輸入有效的數字！" -ForegroundColor Red
    exit
}

# 設定 Log 檔案名稱
$logName = "PowerCycleTest_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
$logPath = Join-Path -Path $currentDir -ChildPath $logName

Write-Host "`n[測試初始化]" -ForegroundColor Cyan
Write-Host "預期磁碟數量: $expectedDiskCount"
Write-Host "Log 儲存路徑: $logPath"
Write-Host "----------------------------------------------"

# ==========================================
# 2. 執行 300 次大迴圈
# ==========================================
for ($i = 1; $i -le 300; $i++) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $header = "`n[第 $i 次測試] 啟動時間: $timestamp"
    $header | Tee-Object -FilePath $logPath -Append

    # --- Step 1: Power Off ---
    Write-Host "[$i] 正在執行 Power Off..." -ForegroundColor Yellow
    .\ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 power off | Add-Content -Path $logPath
    
    Write-Host "等待 60 秒..."
    Start-Sleep -Seconds 60

    # --- Step 2: Power On ---
    Write-Host "[$i] 正在執行 Power On..." -ForegroundColor Yellow
    .\ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 power on | Add-Content -Path $logPath
    
    Write-Host "等待 120 秒 (基礎啟動時間)..."
    Start-Sleep -Seconds 120

    # --- Step 3: 檢測磁碟數量 (含無限重試機制) ---
    $retryCount = 0
    $startTime = Get-Date

    while ($true) {
        # 取得目前磁碟清單
        $disks = Get-PhysicalDisk -CanPool $true | Sort-Object { [int] $_.DeviceId }
        $currentCount = ($disks).Count

        if ($currentCount -eq $expectedDiskCount) {
            # 計算從開機完成到認滿硬碟花的時間
            $duration = New-TimeSpan -Start $startTime -End (Get-Date)
            $successMsg = "成功：檢測到 $currentCount 顆磁碟 (重試次數: $retryCount, 檢測耗時: $($duration.TotalSeconds) 秒)。"
            Write-Host $successMsg -ForegroundColor Green
            $successMsg | Add-Content -Path $logPath
            break # 數量正確，跳出 while 重試迴圈
        }

        # 數量不正確，進入重試邏輯
        $retryCount++
        
        # 定義重試等待時間：10s -> 20s -> 30s (之後固定 30s)
        if ($retryCount -eq 1) { $wait = 10 }
        elseif ($retryCount -eq 2) { $wait = 20 }
        else { $wait = 30 }

        $warnMsg = "警告：目前僅偵測到 $currentCount 顆 (預期 $expectedDiskCount)。第 $retryCount 次重試，等待 $wait 秒..."
        
        # 修正後的顏色參數 (使用 Red 確保相容性)
        Write-Host $warnMsg -ForegroundColor Red
        $warnMsg | Add-Content -Path $logPath

        Start-Sleep -Seconds $wait
    }

    # 記錄正確後的詳細磁碟資訊
    $diskDetails = $disks | Select-Object DeviceId, FriendlyName, SerialNumber, @{Name="Size(GB)"; Expression={[math]::round($_.Size / 1GB, 2)}} | Out-String
    $diskDetails | Add-Content -Path $logPath
    
    Write-Host "----------------------------------------------"
}

# 300 次跑完後的結尾
Write-Host "`n[測試完成]" -ForegroundColor Cyan
Write-Host "300 次 Power Cycle 循環測試已全數通過！" -ForegroundColor Green