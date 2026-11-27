# 伺服器風扇鎖速 + IOMeter 自動測試（Windows bat）— ZELUS / Sophos（Pegatron 2MS）

> 繁體中文版本（本文件）｜ English version: [README.md](README.md)

Windows batch 自動化腳本，用於 DQA「風扇鎖速 + IOMeter」測試：
依序跑 13 階 chassis 風扇 PWM（20 → 100%），每一階：

- 用 OEM `raw 0x36 0xFA` 鎖定 chassis 風扇轉速
- 執行 **兩組** IOMeter 場景（4K Random Writes + 256K Sequential Writes）
- 在 3 個時間點（Before 4K / Before 256K / Stage Completed）記錄
  **chassis 風扇轉速**與 **PSU 風扇轉速**到 `Fan_Speed_Log.txt`

全部完成後，風扇轉速還原為 60%。

V03 相對 V02 的增訂：透過 BMC OEM raw 指令記錄 **PSU 風扇轉速**
（方法由 AIC BMC RD 提供，2026-11-26）。V02 只記錄 chassis 風扇。

## PSU 風扇讀法（Zelus / Sophos 專用——參數依系統而異）

```
ipmitool raw 0x3A 0x6A 0x0 <psu_bus> 0x1 <addr> 0x2 0x90
```

| 參數 | 意義 | ZELUS 數值 |
|---|---|---|
| `psu_bus` | PSU 掛載的 i2c bus | `0x7` |
| `<addr>` | PSU 在該 i2c bus 上的實際位置 | PSU1 `0xB0`、PSU2 `0xB2` |

> 這兩個數值**依系統而異**（BMC RD 說明）。用於其他系統時，請修改
> `run_fan_iometer_V03.bat` 頂部的 `psu_bus` / `psu1_addr` / `psu2_addr`，
> 並先與 BMC RD 確認。

### 解碼

回傳兩個 byte `<lo> <hi>`，解讀為 `val = hi*256 + lo`。

```
RPM = 2^(val 高 5 bit) * (val 低 11 bit)
```

範例：回傳 `6c 30` → `val = 0x306C = 12396` →
`exp = 6`、`mult = 108` → `2^6 * 108 = 6912 RPM`。

> 備註：BMC RD 原始 mail 的範例有筆誤（`e7 28` 對不上他寫的 binary
> `0010 1000 1110 0100` = `0x28E4`）；上方的公式已對 BMC Web UI
> PSU 頁的數值驗證過。

## 檔案

| 檔案 | 用途 |
|---|---|
| `run_fan_iometer_V03.bat` | 主測試（互動式：輸入 BMC IP／帳號／密碼） |
| `psu_fan_test.bat` | 30 秒只讀檢查 PSU 風扇讀取（不鎖風扇、不跑 IOMeter） |
| `README.md` | 英文版說明 |
| `README.zh-TW.md` | 本文件（中文版） |

## 需求（同一資料夾內）

- `ipmitool.exe`（實驗室使用的 Cygwin 版可用）
- `IOmeter.exe`（IOMeter 1.1.0）
- `4K_Random_Writes.icf`、`256K_Sequential_Writes.icf`

## 使用方式

雙擊 `run_fan_iometer_V03.bat`，輸入 BMC IP／帳號／密碼。
產出：`Fan_Speed_Log.txt` + 26 支 CSV（`Fan_<pct>pct_<test>.csv`）。
完整測試約 75 分鐘（13 階 × 約 5.5 分鐘）。

Log 行格式：`PSU1 Fan1: 6912 RPM (raw 6c 30)`

## 來源（Provenance）

設計：Luke Chen（luke1987515）；開發過程有 AI agent 輔助
（Nous Research 的 Hermes Agent）。PSU 風扇 OEM raw 指令與解碼公式
由 AIC BMC RD（Jonny Chung）於 2026-11-26 提供。

驗證記錄（2026-11-26，Pegatron 2MS / ZELUS DUT，BMC 192.168.15.57）：
完整 13 階測試 19:23:51 → 20:36:28——39/39 記錄點齊全、26/26 IOMeter
CSV、0 筆 N/A、0 筆解碼不符；chassis 風扇隨 PWM 階梯 5700 → 20700 RPM；
PSU 風扇全程 6784–6976 RPM（PSU 自管，不受 chassis 鎖速影響）；
測試結束後風扇還原 60%。

Author: Luke.Chen <luke1987515@gmail.com>
Date:   2026-11-26
