# Host Configuration Report Helper (取得主機硬體資訊腳本)

## 📝 簡介
這是一個使用 PowerShell 寫成的自動化腳本，專門為測試人員 (QA / Tester) 設計。
它會自動從 Windows 系統 (Host PC) 中抓取底層的硬體與系統資訊，並統整成測試報告所需的表格格式，省去手動開啟多個視窗查詢、截圖與抄寫的麻煩。

## 🔍 抓取的項目
腳本會自動抓取以下五項資訊，並整理出 **Vender / Model**、**Detail** 與 **Qty (數量)**：
1. **Motherboard (主機板)**
2. **Operation System (作業系統)**
3. **CPU (處理器)**
4. **Memory (記憶體)**
5. **Hard Disk Drive (硬碟)**

> 💡 **自動加總功能**：如果有安裝多條相同型號的記憶體、多顆相同的 CPU 或硬碟，腳本會自動將它們的數量合併計算在 `Qty` 欄位中，不會產生重複的行數。

## 🚀 如何使用

### 方法一：右鍵快速執行 (推薦)
1. 找到你的腳本檔案 (例如：`Get-HostInfo.ps1`)。
2. 對著檔案點擊 **滑鼠右鍵**。
3. 選擇 **「使用 PowerShell 執行」** (Run with PowerShell)。

### 方法二：透過 PowerShell 視窗執行
1. 點擊 Windows 開始按鈕，搜尋 `PowerShell` 並開啟。
2. 將腳本檔案直接 **拖曳** 到 PowerShell 視窗中，或者手動輸入腳本的路徑，然後按下 `Enter` 執行。
   *(例如輸入: `C:\Users\Desktop\Get-HostInfo.ps1`)*

## 📊 產出結果
執行成功後，腳本會完成兩件事：
1. **螢幕顯示**：在 PowerShell 畫面上印出排版好的表格，方便你快速預覽。
2. **匯出 CSV 檔**：在**腳本所在的同一個資料夾**下，自動產生一個名為 `HostConfiguration.csv` 的檔案。

你可以直接用 Excel 開啟 `HostConfiguration.csv`，將裡面的表格內容複製，直接貼上到你的測試報告中！

## ⚠️ 常見問題 (Troubleshooting)

**Q: 為什麼點擊右鍵執行時，視窗一閃而過，而且沒有產生 CSV 檔案？**
* **解答**：這通常是因為權限問題或執行原則被阻擋。建議先將腳本放在「桌面」或「文件」資料夾再執行。

**Q: 在 PowerShell 中執行時，出現紅字錯誤「無法載入檔案，因為這個系統已停用指令碼執行」？**
* **解答**：這是 Windows 預設的安全保護機制。請依照以下步驟解除限制：
  1. 搜尋 PowerShell，並選擇 **「以系統管理員身分執行」**。
  2. 貼上並執行以下指令：`Set-ExecutionPolicy RemoteSigned`
  3. 系統會詢問是否要變更原則，輸入 `Y` 並按下 `Enter` 即可。之後你的腳本就能順利運作了。