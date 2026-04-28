# 1. 設定 dskcache.exe 的路徑 (使用當前資料夾)
$dskcachePath = Join-Path $PSScriptRoot "dskcache.exe"

if (Test-Path $dskcachePath) {
    Write-Host "找到 dskcache.exe，準備執行..." -ForegroundColor Green
} else {
    Write-Host "找不到檔案，請確認 dskcache.exe 是否在當前資料夾！" -ForegroundColor Red
    return
}

# 2. 取得所有非系統磁碟，依編號排序
$targetDisks = Get-Disk | Where-Object { $_.IsSystem -eq $false } | Sort-Object Number

Write-Host "開始檢查磁碟 Write Cache 狀態..." -ForegroundColor Yellow
Write-Host "目標狀態：Write Cache is disabled`n" -ForegroundColor White

$allPassed = $true

foreach ($disk in $targetDisks) {
    $driveName = "PhysicalDrive$($disk.Number)"
    
    # 執行 dskcache 並抓取輸出內容
    $result = & $dskcachePath $driveName 2>&1
    
    # 檢查輸出字串中是否包含 "Write Cache is disabled"
    if ($result -match "Write Cache is disabled") {
        Write-Host "[ PASS ] " -NoNewline -ForegroundColor Green
        Write-Host "$driveName ($($disk.FriendlyName)): Cache 已關閉"
    } else {
        Write-Host "[ FAIL ] " -NoNewline -ForegroundColor Red
        Write-Host "$driveName ($($disk.FriendlyName)): Cache 仍開啟或狀態異常！"
        $allPassed = $false
    }
}

Write-Host "`n------------------------------------------------"
if ($allPassed) {
    Write-Host "檢查完畢：所有磁碟均符合測試規範 (Cache Disabled)。" -ForegroundColor Green
} else {
    Write-Host "檢查完畢：發現有磁碟未符合規範，請確認。" -ForegroundColor Red
}