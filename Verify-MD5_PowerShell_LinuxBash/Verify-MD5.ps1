# ==========================================================
# 程式目的：自動掃描當前目錄下的 .md5sum 檔案並驗證原始檔案完整性
# ==========================================================

# 1. 取得目錄下所有副檔名為 .md5sum 的檔案
Get-ChildItem *.md5sum | ForEach-Object {
    
    $sumFile = $_.Name
    # 移除 .md5sum 後綴，還原原始檔案名稱
    $targetFile = $sumFile -replace '\.md5sum$', '' 

    # 2. 檢查原始檔案是否存在
    if (Test-Path $targetFile) {
        
        # 讀取預期雜湊值
        $expectedHash = (Get-Content $sumFile).Trim() -split ' ' | Select-Object -First 1
        
        # 計算實際雜湊值
        $actualHash = (Get-FileHash $targetFile -Algorithm MD5).Hash

        # 3. 比對並顯示結果 (全面使用 ${} 包圍變數以防冒號解析錯誤)
        if ($actualHash -eq $expectedHash) {
            Write-Host "Check ${targetFile}: [PASS]" -ForegroundColor Green
        } else {
            Write-Host "Check ${targetFile}: [FAIL]" -ForegroundColor Red
            Write-Host "  - Expected: $expectedHash"
            Write-Host "  - Actual:   $actualHash"
        }
    } else {
        # 修正這裡的 $sumFile: 變數解析問題
        Write-Host "Check ${sumFile}: [SKIPPED] (Target file '${targetFile}' not found)" -ForegroundColor Yellow
    }
}