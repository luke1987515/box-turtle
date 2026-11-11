# EBOD 4U88 VIB 多碟 fio 寫入測試

適用：eBOD 4U88（88 × SAS HDD，dual-port）/ BF3 DPU OS（Ubuntu），以 raw block device 對全部 88 顆碟同時做整碟順序寫入，用於觀察多碟並寫下的整體 BW、每碟一致性與錯誤。

## 功能

1. 檢查 88 顆盤（`sda..sdcj`）存在，且**未 mount**（有任一封裝 mount 會直接中止，避免 raw 寫入摧毀檔案系統）
2. 檢查 `fio` 已安裝
3. 產生 fio conf（整碟：不限制 size；512k / iodepth=1 / libaio / direct=1 / time_based）
4. 背景啟動 fio（`setsid nohup`，SSH 斷線不會中斷），前台 monitor 每秒印出整體 MB/s + err
5. conf / log / pid 都產生在**腳本所在資料夾**；log 檔名帶時間戳，重跑不會覆蓋舊證據

## 用法

```bash
sudo bash vib_multi_disk_fio.sh         # 預設 900 秒（15 分鐘）
sudo bash vib_multi_disk_fio.sh 60      # 跑 60 秒
sudo bash vib_multi_disk_fio.sh 1800    # 跑 30 分鐘
```

參數 1 = 運行秒數（正整數），亂填會報錯中止。其他參數在腳本頭部「可調參數」區：

| 參數 | 預設 | 說明 |
|---|---|---|
| `RUNTIME` | 900（= 參數 1） | 運行秒數 |
| `BS` | 512k | block size |
| `IODEPTH` | 1 | 每碟 iodepth |
| `STATUS_INTERVAL` | 1 | fio `--status-interval`：每 N 秒在 log 印出 status（只能放 CLI，放 conf 會 Bad option） |
| `N_DISK` | 88 | 盤數（sda..sdcj） |

## 注意事項

- ⚠️ **這是 raw 整碟寫入，會銷毀 88 顆碟上的所有資料**。只對空測試碟使用；腳本內建 mount 檢查（已 mount 會中止），但務必先自行確認盤是空的。
- 需要 root（`sudo`）與已安裝的 fio（`apt install -y fio`，實測 fio 3.28 / 3.36 皆可）。
- 手動停止：`kill $(cat fio_vib_multi_disk.pid)`
- 完整 report 在 log 檔內（`fio_vib_multi_disk_<時間戳>.log`）。

## 實測參考（2026-11，eBOD 4U88，88 × 3.6T SAS，Ubuntu 22.04.5 / 24.04.4）

- 整組 ~7.9–8.1 GB/s，每碟 ~86–88 MB/s，組 clat avg ~5.7ms
- 900 秒全程 err=0，無 >5% BW dip
- 兩台同型機箱（dual-port 對接兩台 OS）結果一致（差異 ~1.5%）
