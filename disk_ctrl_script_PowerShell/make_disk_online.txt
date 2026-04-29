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
    
    # 2. 檢查磁碟是否需要清除
    # 使用 if 判斷可以避免掉你之前遇到的 "磁碟未初始化" 報錯
	# 清除磁碟資訊 (-RemoveData 會清除分割區，-RemoveOEM 會清除隱藏分割)
    if ($disk.PartitionStyle -ne 'RAW') {
        Write-Host "偵測到現有分區 ($($disk.PartitionStyle))，正在清除內容..."
        Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -Confirm:$false
    } else {
        Write-Host "磁碟已是未初始化狀態，跳過 Clear-Disk。" -ForegroundColor Yellow
    }
    
    # 3. 初始化磁碟為 MBR (注意：超過 2TB 的空間將無法使用)
    Write-Host "正在初始化為 MBR 格式..."
    Initialize-Disk -Number $disk.Number -PartitionStyle MBR
    
    # 4. 確保磁碟狀態為 Online
    Set-Disk -Number $disk.Number -IsOffline $false
    
    Write-Host "磁碟 $($disk.Number) 處理完成。" -ForegroundColor Green
}

Write-Host "`n所有非系統磁碟已重置完成。" -ForegroundColor White -BackgroundColor DarkGreen
