# 1. 取得所有不是系統碟 (IsSystem = False) 且目前在離線的磁碟
$targetDisks = Get-Disk | Where-Object { $_.IsSystem -eq $false -and $_.OperationalStatus -eq 'Offline' } | Sort-Object Number

# 2. 執行離線動作
if ($targetDisks) {
    $targetDisks | ForEach-Object {
        Write-Host "正在將磁碟 $($_.Number) ($($_.FriendlyName)) 設為線上..." -ForegroundColor Cyan
        Set-Disk -Number $_.Number -IsOffline $false
    }
    Write-Host "操作完成。" -ForegroundColor Green
} else {
    Write-Host "沒有找到需要上線的非系統磁碟。" -ForegroundColor Yellow
}