# $PSScriptRoot 代表腳本檔案所在的資料夾
$dskcachePath = Join-Path $PSScriptRoot "dskcache.exe"

if (Test-Path $dskcachePath) {
    Write-Host "找到 dskcache.exe，準備執行..." -ForegroundColor Green
} else {
    Write-Host "找不到檔案，請確認 dskcache.exe 是否在當前資料夾！" -ForegroundColor Red
    return
}

# 1. 取得非系統磁碟
$targetDisks = Get-Disk | Where-Object { $_.IsSystem -eq $false } | Sort-Object Number

foreach ($disk in $targetDisks) {
    $driveName = "PhysicalDrive$($disk.Number)"
    Write-Host "正在設定 $driveName..." -ForegroundColor Cyan
    
    # 使用 & 調用路徑變數執行
    & $dskcachePath -w $driveName
}