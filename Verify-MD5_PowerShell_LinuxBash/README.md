沒問題，我為你整合了一份中英文兼具、且同時涵蓋 **Windows (PowerShell)** 與 **Linux (Bash)** 的完整說明頁面。這份 README.md 設計得非常易讀，適合放置在專案根目錄。

# ---

**Cross-Platform MD5 Verification Tools**

### **跨平台 MD5 檔案完整性驗證工具**

本專案提供兩套指令稿（Script），分別用於 **Windows** 與 **Linux** 環境，自動化批次驗證檔案的 MD5 雜湊值。

## ---

**📂 檔案清單 (File Components)**

| 檔案名稱 | 適用平台 | 說明 |
| :---- | :---- | :---- |
| Verify-MD5.ps1 | Windows (PowerShell) | 支援彩色輸出，自動解析 .md5sum 檔案。 |
| verify\_md5.sh | Linux (Bash) | 使用系統內建工具，支援自動化批次比對。 |
| README.md | 所有平台 | 本說明文件。 |

## ---

**🚀 Windows 使用指南 (PowerShell)**

### **執行需求**

* PowerShell 5.1 或更新版本（已於 PowerShell 7.5.4 測試通過）。

### **使用步驟**

1. 將 Verify-MD5.ps1 放入包含 .ima 原始檔與 .md5sum 校驗檔的資料夾。  
2. 點擊右鍵「使用 PowerShell 執行」或在終端機輸入：  
   PowerShell  
   .\\Verify\-MD5.ps1

### **注意事項**

若出現「禁止執行指令碼」錯誤，請先以管理員權限執行以下指令以暫時解除限制：

PowerShell

Set-ExecutionPolicy \-ExecutionPolicy RemoteSigned \-Scope Process

## ---

**🐧 Linux 使用指南 (Bash)**

### **執行需求**

* 系統需內建 md5sum 與 awk 指令（大多數散佈版如 Ubuntu, CentOS, Debian 皆已內建）。

### **使用步驟**

1. 賦予腳本執行權限：  
   Bash  
   chmod \+x verify\_md5.sh

2. 執行腳本：  
   Bash  
   ./verify\_md5.sh

### **注意事項**

若檔案是從 Windows 傳輸至 Linux，請確保檔案換行格式為 **LF**。可使用 dos2unix verify\_md5.sh 進行轉換。

## ---

**🔍 驗證狀態說明 (Status Indicators)**

腳本執行後會針對每個檔案顯示以下狀態：

* **\[PASS\]** (綠色)：檔案完整，雜湊值比對一致。  
* **\[FAIL\]** (紅色)：檔案毀損或內容被更動，腳本將顯示預期與實際的值。  
* **\[SKIPPED\]** (黃色)：偵測到校驗檔但目錄下找不到對應的原始檔案。

## ---

**🛠 技術邏輯 (Technical Logic)**

本工具的核心運作流程如下圖所示：

1. **掃描**：搜尋目錄中所有 \*.md5sum 檔案。  
2. **提取**：從校驗檔中分離出預期的 MD5 數值。  
3. **計算**：對同名的原始檔案進行即時雜湊運算。  
4. **比對**：將「預期值」與「計算值」進行字串比對並輸出結果。

---

**這樣一份整合型的 README 是否符合你的需求？如果你需要針對特定的生產線環境或是 CI/CD 流程做調整，隨時跟我說！**