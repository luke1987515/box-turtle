這是一個為您準備的 README.md，旨在協助使用者與技術人員快速了解並操作此腳本。

# ---

**伺服器硬碟 LED 測試工具 (v10.4)**

這是一個專為 Linux 伺服器環境設計的硬碟定位與點燈測試工具。它整合了多種硬碟控制協議，幫助系統管理員在機房中快速找出特定序號或名稱的物理硬碟。

## **📖 目錄**

* [功能特性](https://www.google.com/search?q=%23%E5%8A%9F%E8%83%BD%E7%89%B9%E6%80%A7)  
* [系統需求](https://www.google.com/search?q=%23%E7%B3%BB%E7%B5%B1%E9%9C%80%E6%B1%82)  
* [安裝與準備](https://www.google.com/search?q=%23%E5%AE%89%E8%A3%9D%E8%88%87%E6%BA%96%E5%82%99)  
* [使用說明](https://www.google.com/search?q=%23%E4%BD%BF%E7%94%A8%E8%AA%AA%E6%98%8E)  
* [核心邏輯](https://www.google.com/search?q=%23%E6%A0%B8%E5%BF%83%E9%82%8F%E8%BC%AF)

## ---

**✨ 功能特性**

* **多層級自動掃描**：支援 Broadcom (LSI) StorCLI、SCSI Enclosure Services (SES) 以及標準 Linux LEDCTL。  
* **智慧比對**：透過序列號 (Serial Number) 或 WWN 自動將系統內的 /dev/sdX 裝置對應到控制器的物理插槽 (Slot)。  
* **自動化測試**：提供批次自動測試模式，輪流點亮機櫃中所有硬碟的指示燈。  
* **模糊匹配技術**：在 sg\_ses 模式下使用特定的結尾字串比對，提高 AIC 等特殊背板的識別率。

## **🛠 系統需求**

執行此腳本需要以下工具（視您的硬體架構而定）：

| 工具名稱 | 用途 | 預設路徑 |
| :---- | :---- | :---- |
| **StorCLI2** | 新型 Broadcom RAID/HBA 控制器 | /opt/MegaRAID/storcli2/storcli2 |
| **StorCLI64** | 傳統 MegaRAID 控制器 | /opt/MegaRAID/storcli/storcli64 |
| **sg\_utils** | SES 背板控制 (sg\_ses) | /usr/bin/sg\_ses |
| **ledmon** | Linux 標準 LED 控制 (ledctl) | /usr/sbin/ledctl |
| **smartmontools** | 取得磁碟 WWN 資訊 | smartctl |

## **🚀 安裝與準備**

1. **下載腳本**：將 disk\_led\_tool\_10\_4.sh 上傳至伺服器。  
2. **賦予執行權限**：  
   Bash  
   chmod \+x disk\_led\_tool\_10\_4.sh

3. **以 root 權限執行**：  
   Bash  
   sudo ./disk\_led\_tool\_10\_4.sh

## **📝 使用說明**

### **1\. 手動點燈測試 (Manual Mode)**

選擇特定磁碟名稱（例如 sdb），並選擇控制模式：

* **Broadcom StorCLI**：最穩定，適用於有陣列卡或 HBA 卡的環境。  
* **通用 sg\_ses**：適用於直連 JBOD 或 AIC 背板環境。  
* **通用 ledctl**：使用 Linux 核心標準指令。

### **2\. 批次自動點燈 (Batch Auto-Test)**

腳本會掃描系統中所有非 Loop 裝置，並嘗試自動找出最佳點燈路徑。每顆硬碟會點亮 **3 秒** 後熄滅，方便人員巡檢整台機器的硬碟排列順序。

### **3\. 顯示磁碟清單**

即時列出目前系統偵測到的：

* 裝置名稱 (Name)  
* 型號 (Model)  
* 序號 (Serial Number)  
* 介面類型 (SAS/SATA)

## ---

**🔍 核心邏輯**

腳本採用的偵測優先順序如下：

1. **StorCLI2/64**：透過 lsblk 取得 SN，與 storcli /cX/eX/sX show all 的輸出結果進行對比。  
2. **SG\_SES**：透過 smartctl 取得 LU WWN，並使用 WWN 的後 8 碼與 SES 描述符進行模糊匹配。  
3. **LEDCTL**：作為最後的通用手段。

## ---

**⚠️ 注意事項**

* 執行點燈指令時，若硬碟正在進行高負載讀寫，部分控制器的燈號可能會與讀取燈產生衝突。  
* 若發生「匹配失敗」，請確認對應的 storcli 或 sg\_ses 工具是否已安裝且版本與硬體相容。

---

**想進一步修改點燈時間（目前為 3 秒），或是需要增加支援的控制器品牌嗎？我可以為您調整程式碼。**