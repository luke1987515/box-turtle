# os_flip — 雙 OS Boot Override 循環測試

針對雙 OS DUT（例如 **Windows Server 2022 + Ubuntu 24.04** 同碟）的自動化
可靠度測試：用 UEFI **Boot Override** 一次性開機切換在兩個 OS 之間循環，
驗證實際開出來的 OS，並抓取該 OS 的系統資訊——每一圈完整落 log。

一次性 override **不碰持久開機順序**：每圈消耗自己的 override，全場結束時
機器停在最後開出的 OS、持久順序維持不變。

## Provenance（出處）

由 **luke1987515** 設計並驗證；以 AI agent（Nous Research 的 **Hermes Agent**；
self-hosted **Qwen3.8-27B** 模型——早期開發 session 可能使用其他模型）輔助開發。

公開前已驗證：sandbox **8/8** 測試案例 + 實機 **10/10** 圈 PASS（**2026-11-01**，
FAIL_COUNT=0；持久開機順序未動；機器停在最後開出的 OS）。

## 每圈的動作

```
SSH clean shutdown（或 legacy warm reset）
  -> 等 System Power: off
  -> 斷電中 latch `chassis bootdev bios option=efiboot`
  -> 冷開機
  -> SOL pty: 等 "Aptio Setup" -> RIGHT x7 (Save & Exit tab)
     -> DOWN x10 (Ubuntu) / DOWN x9 (Windows) -> ENTER  （一次性交接）
  -> 串 SOL + poll ping 到 DUT UP
  -> 鑑定開機 OS（SOL "EFI stub" 線索 + SSH probe + hostname）
  -> 抓該 OS 系統資訊
```

開機確認 = **SOL 串流 + ping**；ping 是 ground truth（有些平台開機期 SOL
會完全靜音）。OS 鑑定以重試輪次進行，因為 SSH daemon 可能比第一次 ping
晚很多才起來。

## 執行機（runner）需求

- Linux：`bash`、`ip`、`ping`、`ipmitool`（到 DUT BMC 的 RMCP+）
- `python3` + `pexpect`（SOL/SSH 驅動是 Python）
- 與 DUT、BMC 同 L2 廣播域
- 有 SOL 的 BMC（key path 已在 AMI Aptio UEFI 實機驗證）

## 快速開始

```bash
git clone <此 repo>
cd os_flip
./discovery.sh        # 首次執行：找 DUT/BMC，問一次密碼
./os_flip.sh 10       # 跑 10 圈
```

首次執行時 `discovery.sh` 把缺的站點設定填入 **`os_flip.env`**（與腳本同
目錄、`chmod 600`、gitignored），之後不再問。優先序：

```
CLI 環境變數  >  ./os_flip.env  >  互動式 discovery
```

## 首次執行偵測（discovery）

兩種身份偵測模式，依序自動：

1. **斷電指紋法** — 當 `RELAY_OFF_CMD` + `RELAY_ON_CMD` 都設定時（各為一個
   完整 shell command，是你 runner 切/還 DUT AC 的指令）：掃段收 MAC（以
   vendor OUI 過濾）→ 切 relay → 再掃 → **MAC 差集**就是這組 relay 供電域
   內的機器。同一塊板的 MAC 是連號的一小段（預設每板 3 個、`BLOCK_GAP=2`）；
   組內以「IPMI 用公開預設帳密可通」判出 BMC，剩下的就是 DUT。relay 立即
   還電並等待 DUT 回來。
2. **手動模式**（無 relay、或指紋法找不到）：你給 DUT 當下 IP → 從
   ARP/neigh cache 讀它的 MAC（**存的是 MAC**，DHCP 漂移無感）→ BMC 在
   「活著、同 OUI、同連號組、IPMI 預設帳密可通」的候選中自動搜，你確認或
   覆蓋。

密碼：BMC 先試公開預設帳密（通就不問）；Windows/Ubuntu 帳號問一次存進
`os_flip.env`。開機確認完成**之後**若撞 auth 失敗，會停下重問該組一次
（boot 等待期間的失敗純重試——機器可能還沒起完）。

`./discovery.sh --dry-run`：唯讀掃段 + 分組（不斷電、不寫檔），適合先健檢
環境。`./discovery.sh --reauth`：丟掉已存設定重來。

## 設定（環境變數 / os_flip.env）

| 變數 | 預設 | 意義 |
|---|---|---|
| `DUT_IP` / `DUT_MAC` | —（二擇一必填） | DUT 身份；MAC 會在 DHCP 漂移時重解 IP |
| `BMC_IP`, `BMC_USER`, `BMC_PASS` | —（必填） | BMC IPMI 存取 |
| `WIN_USER`/`WIN_PASS`, `UBU_USER`/`UBU_PASS` | 帳號有預填 | DUT OS 帳號 |
| `DUT_NET` | runner 自己的 /24 | MAC 掃段範圍（`a.b.c.d/24`） |
| `KNOWN_OUI` | `00:15:b2` | vendor OUI 前綴（逗號分隔） |
| `RELAY_OFF_CMD` / `RELAY_ON_CMD` | 未設 | 都設才啟用斷電指紋法 |
| `BLOCK_GAP` | `2` | 同板 MAC 連號組寬（3 個 → gap ≤ 2） |
| `CYCLES` | `10`（或 argv 1） | 切換圈數 |
| `SHUTDOWN_MODE` | `clean` | `clean` = SSH 關機 → 斷電 → 斷電中 latch bootdev → 開機（COLD）；`reset` = legacy warm reset |
| `SETUP_TIMEOUT` / `BOOT_TIMEOUT` | `120` / `240` | UEFI setup / 開機確認預算（秒） |
| `PROBE_TIMEOUT` / `ID_PROBE_BUDGET` | `30` / `240` | 單次 SSH probe / 整體鑑定預算（秒） |
| `COLLECT_TIMEOUT` | `120` | 系統資訊收集預算（秒） |
| `BMC_DEFAULT_USER` / `BMC_DEFAULT_PASS` | vendor 預設 | 只用於 discovery 的首次試探 |

## 失敗語義

- **nav verify fail** → 絕不送 ENTER，安全退出（關 SOL + plain reset 回
  正常開機），該圈 FAIL，**中止全場**
- **boot timeout / 鑑定失敗 / 開錯 OS** → 該圈 FAIL，中止
- **開機正確但收集失敗** → 該圈 **PARTIAL**，繼續

每圈落檔：nav 按鍵 trace（`t/key/+bytes/text`）、開機耗時（reset → ping
UP）、OS 鑑定證據、完整系統資訊輸出、失敗原因。全部放在
`$WORK_DIR/os_flip_<ts>/`（預設 `~/os_flip/`）。中停用 `pkill -f os_flip`。

## Sandbox（無硬體自測）

`sandbox/` 用 `ssh`/`ping`/`ipmitool`/`ip` 的 stub（狀態機模擬 DUT 的
power/boot/OS 狀態）跑完整控制邏輯，完全不碰硬體：

```bash
cd sandbox
./run_case.sh A    # 正常 2 圈（reset 模式）
./run_case.sh B    # nav verify fail -> 安全退出、中止
./run_case.sh C    # ENTER 交接後 boot timeout
./run_case.sh D    # 收集失敗 -> PARTIAL、繼續
./run_case.sh E    # 正常 2 圈（clean 模式，兩條關機路徑）
./run_case.sh F    # clean 模式 SSH 掛死 -> 強制 off/on、PASS + WARN
./run_case.sh G    # clean 模式 BIOS 掉 latch -> setup retry 救回
./run_case.sh H    # 首次執行 discovery（手動模式）+ 1 圈
```

所有 case 都必須 exit 0。

## 安全說明

- relay 只經**你自己設定**的兩條指令（`RELAY_OFF_CMD`/`RELAY_ON_CMD`）
  操作，絕不猜測；指紋法取得差集後立即還電。
- `os_flip.env` 含真密碼：`chmod 600` 且 gitignored，**絕不可 commit**。
  本 repo 不含任何站點 IP、憑證、專案代號。
- 測試不改持久開機順序；若要讓 DUT 停在特定 OS，一個 plain
  `chassis power reset` 就回持久預設。
