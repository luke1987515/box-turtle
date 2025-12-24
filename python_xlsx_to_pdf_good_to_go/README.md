這是一份為您的自動化工具量身打造的 **README.md** 說明文件。它包含了專案簡介、安裝步驟、使用說明以及資料夾結構，方便您未來維護或分享給同事使用。

# ---

**Excel 轉專業測試報告 (xlsx-to-pdf-report)**

這是一個基於 Python 的自動化工具，旨在將 Excel 格式的測試案例（Test Cases）批次轉換為**一頁一個 Test Case** 的專業 PDF 報告。

## **核心功能**

* **自動化轉換**：一鍵掃描資料夾內所有 .xlsx 檔案並產出 PDF。  
* **專業排版**：採用 HTML/CSS 模板，提供深色標題列、灰色資訊欄及分頁處理。  
* **智慧結果判斷**：自動識別 Test Result 欄位，若包含 "Pass" 則顯示綠色徽章，否則顯示紅色。  
* **支援多行文本**：完美支援 Excel 內（Alt+Enter）的換行格式。

## **系統環境需求**

1. **Python 3.x**  
2. **wkhtmltopdf**：這是一個將 HTML 轉為 PDF 的渲染引擎。  
   * 請從 [wkhtmltopdf 官網](https://wkhtmltopdf.org/downloads.html) 下載並安裝。  
   * 預設安裝路徑應為：C:\\Program Files\\wkhtmltopdf\\bin\\wkhtmltopdf.exe

## **安裝步驟**

### **1\. 複製此專案**

將相關 .py 腳本放入您的工作目錄。

### **2\. 安裝 Python 依賴套件**

開啟終端機（CMD 或 PowerShell），執行以下指令：

Bash

pip install pandas openpyxl pdfkit jinja2

## **使用方式**

### **1\. 準備 Excel 檔案**

請確保您的 Excel 標題列（Header）包含以下欄位（名稱必須完全一致）：

* No (測試編號)  
* Section (章節)  
* Test Categorization (測試類別)  
* Test Subject (測試主題)  
* Description (詳細描述)  
* Pass Criteria (通過準則)  
* Test Procedures (測試步驟)  
* Test Result (測試結果：包含 "Pass" 字樣會標示為綠色)

### **2\. 執行轉換**

在終端機執行：

Bash

python xlsx\_Jinja2\_to\_pdf.py

## **資料夾結構**

Plaintext

python\_xlsx\_to\_pdf/  
├── xlsx\_Jinja2\_to\_pdf.py   \# 主程式腳本  
├── test\_cases.xlsx         \# 您的 Excel 原始檔  
└── test\_cases\_Report.pdf   \# 產出的 PDF 報告

## **排版自定義**

如果您需要修改報告樣式，可以在 xlsx\_Jinja2\_to\_pdf.py 中的 html\_template 變數裡調整 CSS：

* **顏色**：修改 .header 或 .status-badge 的 background-color。  
* **字體**：在 body 樣式中更換 font-family。  
* **邊距**：調整 options 字典中的 margin-top 等參數。

## **常見問題 (Troubleshooting)**

* **找不到執行檔**：請確認 path\_wkhtmltopdf 的路徑與您電腦安裝的路徑一致。  
* **中文亂碼**：本程式已設定 UTF-8 編碼，若仍有亂碼請確認系統是否安裝「微軟正黑體 (Microsoft JhengHei)」。  
* **標籤判斷失敗**：若您的 Pass 寫法不同（例如 OK），請修改代碼中 {% if 'pass' in ... %} 的判斷條件。

---

**需要我幫您將這份說明存成實體檔案，或是針對特定的 CSS 樣式再做微調嗎？**