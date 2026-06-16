# 1. 取得所有非系統磁碟 (IsSystem = $false)
$targetDisks = Get-Disk | Where-Object { $_.IsSystem -eq $false }  | Where-Object -FilterScript {$_.Bustype -ne "USB"} | Sort-Object Number

foreach ($disk in $targetDisks) {
    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    Write-Host "正在處理磁碟編號: $($disk.Number) ($($disk.FriendlyName))" -ForegroundColor Cyan
    
    # 1. 解除唯讀並將磁碟連線
    # 確保磁碟處於連線狀態，必須先有寫入權限且在線，後續動作才能成功
    # 步驟 1-1：先解除唯讀
    Write-Host "正在解除唯讀狀態..."
    Set-Disk -Number $disk.Number -IsReadOnly $false
    
    # 步驟 1-2：再設定為連線
    Write-Host "正在將磁碟連線..."
    Set-Disk -Number $disk.Number -IsOffline $false
    
    # [優化加入] 檢查該磁碟目前是否含有分割區
    $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
    
    # 2. 判斷磁碟狀態並決定處理策略
    # 如果已經是 MBR，且裡面沒有任何分割區 ($null 或 數量為 0)，則視為已就緒
    if ($disk.PartitionStyle -eq 'MBR' -and ($null -eq $partitions -or $partitions.Count -eq 0)) {
        Write-Host "偵測到磁碟已是乾淨的 MBR 格式且無分割區，跳過清除，直接確保連線。" -ForegroundColor Yellow
        Set-Disk -Number $disk.Number -IsOffline $false
    } 
    else {
        # 進入清除與初始化流程 (包含 RAW、GPT，或是「含有舊資料/分割區」的 MBR)
        if ($disk.PartitionStyle -ne 'RAW') {
            Write-Host "偵測到現有分區或非乾淨 MBR 狀態 ($($disk.PartitionStyle))，正在清除內容..."
            Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -Confirm:$false
        } else {
            Write-Host "磁碟為未初始化狀態 (RAW)，準備進行初始化。" -ForegroundColor Yellow
        }
        
        # 3. 初始化磁碟為 MBR (注意：超過 2TB 的空間將無法使用)
        Write-Host "正在初始化為 MBR 格式..."
        Initialize-Disk -Number $disk.Number -PartitionStyle MBR
        
        # 4. 確保磁碟狀態為 Online
        Set-Disk -Number $disk.Number -IsOffline $false
    }
    
    Write-Host "磁碟 $($disk.Number) 處理完成。" -ForegroundColor Green
}

Write-Host "`n所有非系統磁碟已重置完成。" -ForegroundColor White -BackgroundColor DarkGreen
