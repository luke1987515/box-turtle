# os_flip Site Profile + Auto-Discovery 設計 v1

日期：2026-11-07　狀態：**已核准**（2026-11-07）→ 已實作（2026-11-07：
sol_boot.py / os_flip.sh / sites/ ×2 / env.example / README ×2 / AGENTS.md /
tests/test_site_profiles.py 12/12 PASS；實機 --check / --discover /
shakedown 待逐步授權）

## 1. 目標

1. 同一套代碼支援多台 DUT（不同 UEFI 版面）
2. 新 DUT 不用人工 SOL 掃描——`--discover` 自動校準（約 5 分鐘）
3. 版面漂移（韌體更新）會被偵測並安全中止，**永不**靜默選錯 OS
4. setup 階段與跑測階段分離；跑測階段對 profile **唯讀**

## 2. 檔案佈局

**Repo（box-turtle/os_flip/）：**

```
os_flip.sh               # 單一入口：--check / --discover / <N>
os_flip_common.sh
sol_boot.py              # 導航 + discover + profile 載入
ssh_cmd.py               # 不變
os_flip.env.example      # 新增 SITE_NAME / LINUX_NAME
sites/                   # 基準 profile（無機密；IP/MAC 是測試 LAN 內址）
  tucana.conf
  aic_1x.conf
DESIGN-site-profiles.md  # 本文件
README.md / README.zh-TW.md  # 新增「新 DUT 五步動線」
```

**Runner 端（例：103 的 ~/os_flip/）：**

```
os_flip.env              # site env（有機密，不上 repo）
profiles/                # 本地 profile，優先級最高
  aic_1x.conf            # --discover 寫入
```

**Profile 解析順序**（依 `SITE_NAME`）：
1. `profiles/<SITE_NAME>.conf`（runner 本地，最新校準）
2. `sites/<SITE_NAME>.conf`（repo 基準）
3. 都沒有 → cycle 拒絕啟動，訊息指示跑 `--discover`

## 3. Profile schema v1

```
# 由 --discover 產生或手動收錄的基準；無機密，可 commit
site=aic_1x
bmc_ip=192.168.1.116
dut_mac=00:15:b2:b0:51:17
firmware=Tuca_0.09.0            # 資訊欄（SOL banner/BMC），不作為 gate
discovered_at=2026-11-07T04:50+08:00
power_entry=warm_reset          # 見下方說明（schema v1.1，2026-11-07 增）
item_count=15
# item_N：第 N-1 次 DOWN 後高亮的項目（item_1 = tab 第一項）。
# 格式：name::desc_fragment（boot override 行沒有描述欄，desc 為 -）
item_1=Save Changes and Exit::...
item_2=Discard Changes and Exit::without saving any changes
item_3=Save Changes and Reset::Reset the system after saving the changes
item_4=Discard Changes and Reset::Reset system setup without saving any changes
item_5=Save Changes::Save Changes done so far to any of the setup option
item_6=Discard Changes::Discard Changes done so far
item_7=Restore Defaults::Restore/Load Default values for all the setup options
item_8=Save as User Defaults::Save the changes done so far as User Defaults
item_9=Restore User Defaults::Restore the User Defaults to all the setup options
item_10=Windows Boot Manager::...          # target_windows_down=9
item_11=UEFI: PXE IPv4 Intel::...
item_12=UEFI: PXE IPv4 American::...
item_13=UEFI: Built-in EFI Shell::...
item_14=ubuntu::...                        # target_linux_down=13
item_15=Launch EFI Shell from filesystem device::...
# 目標：從 tab 頂端開始的 DOWN 按數（與既有 TARGET_DOWNS 語意相同）
target_windows_down=9
target_linux_down=13
target_linux_name=ubuntu
```

比對規則沿用既有 `squash()`（去所有空白 + lowercase）子串比對。

**`power_entry`（schema v1.1，2026-11-07 增）**：每站的 UEFI 進入方式，
`cold_on`（預設）或 `warm_reset`。

- `cold_on` = clean shutdown → 斷電時 latch bootdev → **冷開機**進 setup
  （TUCANA 基準平台，2026-10-28 驗證、20/20 cycles PASS）。
- `warm_reset` = 機器**保持開機** → 開機中設 bootdev → **暖 reset** 進 setup。
  必要條件：aic_1x DUT（Tuca_0.09.0）的冷開機會**忽略 one-shot latch**——
  2026-11-07 三次 cold-on attempt 全超時（SOL 顯示 "Press <DEL> or <ESC> to
  enter setup" 後直接進 persistent order）；2026-11-06 驗證的進入路徑是
  bootdev-while-running + 暖 reset。

profile 的 `power_entry` 是進入方式的**唯一來源**（取代 env 記憶）：
`--discover` 從既有 profile（profiles/ > sites/）讀它決定 S1/S2 路徑，
cycle 也照它走（`SHUTDOWN_MODE` 只在 profile 為 `cold_on` 時才生效）。
舊 profile 沒有這個欄位 → 預設 `cold_on`（向後相容）。

## 4. Env 新增

| 變數 | 說明 | 必填 |
|---|---|---|
| `SITE_NAME` | profile 名稱（如 `aic_1x`） | cycle/discover 必填 |
| `LINUX_NAME` | Linux 側 OS 名稱 token（`ubuntu`、`centos`…） | discover 必填（找目標用），cycle 建議填 |

其餘（BMC/DUT IP、DUT_MAC、帳密、各 timeout、SHUTDOWN_MODE）維持現況。

## 5. 入口與階段

### 5.1 `--check`（不斷電、不關機、不改任何狀態）

1. env 檢查：SITE_NAME、DUT_MAC 必填，缺則列舉
2. 連通性：DUT ping、BMC `chassis status`
3. profile 解析：不存在 → exit 2（訊息：先跑 `--discover`）；MAC/BMC 與 env 不符 → exit 3（訊息：site 搬遷或 env 用錯，重跑 `--discover`）
4. 雙向 SSH probe 報目前 OS
5. 印 readiness 摘要；exit 0 = 可跑 cycle

### 5.2 `--discover`（setup 階段，約 5 分鐘）

前置（不滿足即拒絕）：env 完整（SITE_NAME、DUT_MAC、BMC 帳密、LINUX_NAME）、無 cycle 在跑（lock）、BMC 可達、DUT ping 通、已識別目前 OS（安全還原基準）。

State machine：

```
S0 前置檢查
S1 乾淨關機（沿用 cycle 現行路徑：shutdown → ping loss）
S2 SOL attach，等 UEFI Setup（SETUP_TIMEOUT；進 setup 的機制與 cycle 相同：
   power off + bootdev efiboot latch）
S3 導航到 Save & Exit tab：RIGHT 直到 tab 列出現 "Save & Exit" 文字
   （上限 12 次；取代今天寫死的按數；沿用 tab arrival verify）
S4 列舉：逐次 DOWN，每步抓 (highlight name, desc fragment)；
   終止條件 = 高亮回到第一項（wrap 偵測）或 N > 24（安全上限）
S5 配對目標：
   windows = name 含 "windows boot manager"（錨定，避開 Recovery entry）
   linux   = name 含 LINUX_NAME（squash 比對；若多項命中 → 列出全部，
             採第一項並在對照表標註，由人確認）
   缺任一 → 中止（印出實際看到的全部項目供診斷）
S6 寫 profile：tmp + mv 原子寫入 profiles/<SITE_NAME>.conf；
   印出人類可讀對照表（15 項全列，兩個目標標記 → DOWN n）
S7 安全退出 Setup：Discard Changes and Exit（Yes/No 對話框 LEFT→ENTER，
   沿用已校準序列）
S8 等 ping 回來 + 識別 OS == S0 記錄的 OS（BOOT_TIMEOUT）
S9 釋放 lock，報「setup 完成，機台已回到 <os>」
```

失敗路徑：S2–S7 任何一步失敗 → 只要人在 setup 裡就**一律先嘗試安全退出**（Discard）；連 Discard 都失敗 → 明確大字警示「機台停在 UEFI Setup，需物理介入」。全程 SOL 抓包留檔（sol.raw/sol.txt），中止也可事後診斷。

### 5.3 `<N>` cycle（跑測階段）

- precheck = 現行（ping、BMC、OS 識別）＋新 gate：
  - profile 不存在 → 拒絕，印 `--discover` 指令
  - bmc_ip/dut_mac 與 env 不符 → 拒絕
- 導航首項驗證：第一次 DOWN 後比對 `item_2`（name+desc），不符 → **中止當個 cycle**、安全退出、訊息「layout drift，重跑 `--discover`」。其後各項維持現有逐步 verify。
- profile 唯讀開啟；cycle 全程不寫 profiles/。

## 6. 漂移語意

- 身份 gate = MAC/BMC（防 site 搬遷/env 錯配）
- 版面 gate = 首項 live 驗證（防韌體更新改版面）——權威來源
- `firmware` 欄僅資訊用途
- 文件明寫：韌體更新或 UEFI 重置後 → 預期第一個 cycle 會在 item_2 中止 → 重跑 `--discover` → `os_flip.sh 1` shakedown

## 7. 改動範圍

| 檔案 | 改動 |
|---|---|
| `sol_boot.py` | 移除 hardcode ITEMS/ITEM_NAMES/TARGET_DOWNS → `load_profile()`；新增 discover 模式（複用既有導航原語）；tab arrival 改文字搜索 loop；cycle 首項驗證 gate |
| `os_flip.sh` | 子命令解析（--check / --discover / <N>）；SITE_NAME/LINUX_NAME；profile 解析（profiles/ → sites/）；gate 訊息 + exit code；lock 延伸 |
| `os_flip.env.example` | 新變數 + 註解 |
| `sites/*.conf` | 兩個基準（TUCANA 用上游現值；aic_1x 用今天校準值） |
| README ×2 | 新 DUT 五步動線、階段表、漂移處理 |
| `DESIGN-site-profiles.md` | 本文件 |
| `ssh_cmd.py`、`ac_cycle.sh` | **不變** |

## 8. 測試計畫（實機，逐步授權）

1. 本地（無硬體）：profile parser + 解析順序 + gate 邏輯的單元驗證
2. 103 + 真 DUT：`--check`（用 repo 的 aic_1x 基準）→ 全綠
3. `--discover` 真機跑一次 → 產生物與 `sites/aic_1x.conf` 逐行比對（應一致；同時驗證 discover 輸出格式）
4. `os_flip.sh 1` → PASS（profile 驅動的 shakedown）
5. 負向測試：env 改錯 DUT_MAC → `--check` 拒絕；移走 profile → cycle 拒絕
6. TUCANA 回歸（可選，看機台檔期）：tucana 基準跑 1 cycle

## 9. 風險與緩解

| 風險 | 緩解 |
|---|---|
| DOWN 列舉的 wrap 偵測失敗（不同固件繞圈行為不同） | 雙條件：回第一項 或 N>24 硬上限；兩種都不滿足 → 中止而非死迴圈 |
| 非 AMI/Aptio 廠商：bold/highlight 解碼不同 | discover 抓到垃圾 → S5 目標配對失敗 → 乾淨中止 + sol.raw 存檔，人工評估後加廠商支援 |
| LINUX_NAME 多項命中（如 Ubuntu + Ubuntu recovery） | 採第一項 + 對照表標註全部命中，S6 前由人確認（dry-run 本來就要人看對照表） |
| SOL 不穩 | 沿用既有重試；中止必留抓包 |
