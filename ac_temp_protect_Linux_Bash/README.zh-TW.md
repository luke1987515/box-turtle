# ac_temp_protect — BMC 入口溫度 AC 保護（不自動回電）

當指定的 BMC 溫度 sensor 持續達到門檻溫度超過可設定的窗口時間，就切斷
AC——然後**保持斷電**。回電永遠是刻意的人工動作。為長時間高溫測試而做：
過溫之後絕不悄悄把 DUT 重新供電。
English version: [README.md](README.md)

## Provenance（出處）

由 **luke1987515**（AIC DQA）設計並驗證；以 AI agent（Nous Research 的
**Hermes Agent**；self-hosted **Qwen** 模型家族——早期開發 session 可能
使用其他模型）輔助開發。

公開前已驗證（**2026-11-14**）：sandbox **7/7** 功能場景 PASS（TRIPPED
die 路徑；relay OFF 大警告但放行；`clean` 三分支全測、含 `--yes` 與回電
後 relay 複讀；setup 清檔前資訊顯示——relay 以檔案 flag 模擬，零硬體）+
實機 **3/3** 台 AC server（CentOS 7/8）部署：`bash -n` 3/3、dry-run 數輪
PASS、`clean` 3/3 PASS（一筆 2026-10-30 真實 trip 留下的過期 TRIPPED，
在 relay 已 ON 的情況下清除，log 記錄「外部已回電」）、relay 以暫存器
讀取確認 **ON 3/3**。全程 **零 relay 寫操作**：驗證期間斷電/回電 helper
從未在實機執行。

## 運作方式

- 每 `POLL_SECONDS` 讀一次 BMC 溫度 sensor（`ipmitool sdr list`）。
- `temp >= THRESHOLD`：累計高溫秒數；累計達 `WINDOW_SECONDS` 即執行斷電
  helper，狀態轉為 `TRIPPED`。
- **絕不自動回電。** trip 後監控繼續（讀取不停），且每輪回看 relay 實體
  狀態；若斷電已被外部解除（harness 或手動開回），會大聲警告「保護已
  失效」。
- BMC 讀取失敗：不動作；累計時鐘暫停（中斷間隔不計入窗口）。
- 啟動檢查（純讀取）：state `TRIPPED` → 拒絕啟動並指路 `clean`；relay
  讀到 OFF 但 state `NORMAL` → 大警告（DUT 的 AC 可能仍斷電中）但放行。
- `clean`：顯示 status + relay；relay OFF 時問「要回電? [y/N]」（`--yes`
  跳過詢問）；只有答 `y` 才執行回電 helper **且**複讀 relay——relay 讀回
  ON 才重置 state；relay ON 且 `TRIPPED` → log「外部已回電」。最後無條件
  重置 state 回 NORMAL 基準（`ACCUM=0`、`TRIP_AT` 清空）。不碰 `conf`，
  log 只追加不刪。

## 檔案（建在腳本同目錄）

| 檔案 | 用途 |
|---|---|
| `ac_temp_protect.conf` | `setup` 產生的設定檔（**含 BMC 密碼**；chmod 600——絕不上 repo） |
| `ac_temp_protect.state` | 執行狀態（`NORMAL`/`TRIPPED`、累計值）——重跑仍保留 |
| `ac_temp_protect.log` | log（台北時間戳記） |
| `.ac_temp_protect_raw` | 最近一次 `ipmitool` 原始輸出（診斷用） |

## 需要的 AC relay helpers（未隨附）

腳本透過 `$AC_HELPER_DIR`（可用環境變數覆蓋；預設
`/ED/QT_Cycling_Multi-SVR-AC`）裡的三個 helper 控制 AC。它們是各環境
專用的硬體驅動腳本，**刻意不公開**——需自行提供。要求：

- 狀態讀取（`013.read.gpiod7_state.sh`）：只讀 relay 狀態；輸出必須含
  `AC Power ON` 或 `AC Power OFF`；
- 斷電（`021.ac_power_off.sh`）：切斷 AC；
- 回電（`022.ac_power_on.sh`）：恢復 AC；
- 全部以**自身所在目錄為 CWD** 執行（helper 內部以相對路徑呼叫兄弟
  工具）；exit 0 = 成功。

上述檔名是開發環境的既有 layout；若你的不同，改腳本頭部的常數（或
`AC_HELPER_DIR` 環境變數）即可。

## 用法

```bash
./ac_temp_protect.sh setup            # 一次：BMC IP/帳號密碼、選溫度 sensor、
                                      # 門檻 / 窗口 / 輪詢間隔
./ac_temp_protect.sh run              # 開始監控（前台；Ctrl+C 停止）
./ac_temp_protect.sh run --dry-run    # 試跑：只記錄 log，絕不斷電
./ac_temp_protect.sh status           # 顯示目前狀態 + relay 狀態
./ac_temp_protect.sh power-on         # trip 後手動回電
./ac_temp_protect.sh clean            # 重置 state 回 NORMAL 基準
                                      #（relay OFF 時問是否回電；--yes 跳過詢問）
```

建議流程：`setup` → `run --dry-run` 觀察一陣 → `run` 正式啟用。

## 安全注意事項

- 先 `--dry-run`；dry-run 絕不碰 relay。
- trip 之後沒有任何東西會自動給 DUT 回電——這就是設計目的。
- `ac_temp_protect.conf` 含真實 BMC 憑證：chmod 600、絕不上 repo、
  絕不貼進 log 或工單。
- log 時間戳記為 `Asia/Taipei`。
