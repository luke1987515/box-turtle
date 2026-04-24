# ==============================================================================
# FIO 多磁碟自動壓力測試腳本 (互動版)
# 功能：自動偵測非系統碟、生成 Job File、執行並行寫入測試
# ==============================================================================

# 1. 取得所有非系統磁碟 (排除 OS 碟且狀態為 Online)
$nonOSDrives = Get-Disk | Where-Object { $_.IsSystem -eq $false -and $_.OperationalStatus -eq 'Online' }

if ($null -eq $nonOSDrives) {
    Write-Host "`n [!] 錯誤：找不到任何可供測試的非系統磁碟。" -ForegroundColor Red
    exit
}

# 2. 顯示偵測到的磁碟資訊供使用者核對
$driveCount = $nonOSDrives.Count
Write-Host "`n=== 偵測到 $driveCount 顆測試對象 ===" -ForegroundColor Cyan
$nonOSDrives | Select-Object Number, FriendlyName, @{Name="Size(GB)";Expression={[Math]::Round($_.Size/1GB, 2)}}, @{Name="Path";Expression={"\\.\PhysicalDrive$($_.Number)"}} | Format-Table -AutoSize

# 3. 互動式確認與參數輸入
Write-Host " [警告] 此測試將使用 'write' 模式，$driveCount 顆磁碟資料將會被完全抹除！" -ForegroundColor Yellow
$confirmation = Read-Host "確認要開始測試嗎？ (輸入 Y 繼續 / 其他鍵退出)"
if ($confirmation -ne "Y" -and $confirmation -ne "y") {
    Write-Host " [-] 測試已取消。" -ForegroundColor Gray
    exit
}

$runtime = Read-Host "`n請輸入測試時間 (秒) [預設 60]"
if ([string]::IsNullOrWhiteSpace($runtime)) { $runtime = "60" }

$bs = Read-Host "請輸入 Block Size (例如 1M, 4k, 128k) [預設 1M]"
if ([string]::IsNullOrWhiteSpace($bs)) { $bs = "1M" }

# 4. 生成 FIO 臨時設定檔 (避開 Windows 指令長度限制)
$jobFilePath = "$env:TEMP\fio_batch_stress.fio"

# 寫入 Global 全域設定
$fioConfig = @"
[global]
ioengine=windowsaio
direct=1
thread
rw=write
bs=$bs
runtime=$runtime
time_based
group_reporting
"@

# 寫入各別磁碟 Job
foreach ($drive in $nonOSDrives) {
    $fioConfig += "`n`n[disk_$($drive.Number)]`nfilename=\\.\PhysicalDrive$($drive.Number)"
}

# 儲存設定檔 (使用 ASCII 編碼確保相容性)
$fioConfig | Out-File -FilePath $jobFilePath -Encoding ascii

Write-Host "`n[+] 設定檔已生成: $jobFilePath" -ForegroundColor Gray
Write-Host "[+] 正在啟動 $driveCount 顆磁碟並行壓力測試..." -ForegroundColor Green
Write-Host "------------------------------------------------------------"

# 5. 執行 FIO
& fio $jobFilePath

# 6. 清理
if (Test-Path $jobFilePath) {
    Remove-Item $jobFilePath -ErrorAction SilentlyContinue
}

Write-Host "`n=== 測試流程結束 ===" -ForegroundColor Cyan