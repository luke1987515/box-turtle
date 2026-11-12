#!/usr/bin/env bash
#
# ZV2 AC cycle + 溫控設備測試
# 執行位置：AC ON/OFF server（遠端控制待測物電源、記錄狀態）
#
# 流程：
#   0. AC ON → 等 TEMP_Sys_Inlet ≤ 10°C（chamber 低溫段 0°C）
#   1. 跑 cycle 1..LOW_CYCLES（開關循環 + PCIe/NVMe + SDR 記錄）
#   2. 保持 AC ON → 等 TEMP_Sys_Inlet ≥ 35°C（chamber 高溫段 35°C）
#   3. 跑 cycle 1..HIGH_CYCLES（編號重新從 1 起）
#   4. 收尾：AC ON → 抓 SEL（依 record ID 分段：low 檔=低溫段、high 檔=高溫段）→ AC OFF
#
# 單段測試：
#   LOW_CYCLES=0 → 跳過階段 0/1，直接進階段 2（等高溫）
#   HIGH_CYCLES=0 → 跳過階段 2/3，直接進收尾
#
# Log：低溫段與高溫段各一份，同一時間戳記配對
#   ZV2_temp_low_<開始時間>.txt / ZV2_temp_high_<開始時間>.txt
#   階段 0/1（等低溫 + 低溫循環）寫 low 檔；
#   階段 2/3（等高溫 + 高溫循環）寫 high 檔；
#   SEL 只在收尾抓一次（BMC 全量），依 record ID 分段寫入：
#     low 檔  = (測試開始 mark, 高溫段開始 mark]
#     high 檔 = (高溫段開始 mark, 收尾時最大]
#     跑測試前會對每台 BMC 做一次 `sel clear`（清他人測試殘留；只在第一個 mark 前清一次）；
#     測試期間仍不清 SEL。mark 讀取失敗的 BMC → 該台 fallback 全量 dump（log 有 WARN）。
#
# SSH bootstrap（開跑前自動執行，新 AC server＋新 DUT 環境免手動建鑰）：
#   金鑰對不存在 → ssh-keygen 建（SSH_REKEY=1 強制重建，舊金鑰先備份 .bak）；
#   每台 DUT 先試免密（在就跳過），不在則用 expect＋DUT_PASS 裝公鑰；
#   失敗 → 互動詢問密碼重試（最多 SSH_RETRY_MAX 次，Enter 放棄），需前台終端機；
#   全部成功才進入測試，任一 DUT 授權失敗即中止。
#
# 保護（背景 watchdog，每 30s 輪詢兩台 BMC 的 TEMP_Sys_Inlet）：
#   任一 ≥ 50°C → 警告 log（邊緣觸發，不重複刷屏）
#   任一 ≥ 55°C → 立即 AC OFF + 中止整場測試
#   讀不到溫度（BMC 未上線）= unknown：等待不算達標，保護不動作
#
# Degraded mode（DEGRADED_MODE=on，預設）：某台 BMC 未上線時 per-machine 判定
#   該機 OS 可達  → DEGRADED：照跑 OS 腳本；SDR 先試 KCS 救援（BMC 本體活、
#                    只是 lanplus 網路掛），KCS 也失敗才標 SDR MISSING；
#                    該機改由 OS 端 hwmon 溫度備援 watchdog 保護
#                    （≥OS_CPU_WARN WARN、≥OS_CPU_CRIT 立即 AC OFF + 中止整場）
#   該機 OS 不可達 → POWER-FAIL：relay ON 但 BMC/OS 皆不可達，供電鏈嫌疑
#                    （relay 接點 / PSU），該輪跳過
#   DEGRADED_MODE=off → 完全回到舊行為（任一台 BMC 下線 = 整輪跳過）
#
# 用法：./zv2_temp_ac_cycle_loop.sh [低溫段輪數] [高溫段輪數]   # DEGRADED_MODE=off 可禁用降級模式
#   預設 300 300

set -uo pipefail

# ── 參數 ──────────────────────────────────────────────
LOW_CYCLES="${1:-300}"
HIGH_CYCLES="${2:-300}"
TOTAL_CYCLES=$((LOW_CYCLES + HIGH_CYCLES))

LOW_TEMP=10          # 低溫等待門檻（入風口讀值）
HIGH_TEMP=35         # 高溫等待門檻（入風口讀值；含 ~4°C 自熱偏差，見討論）
WARN_TEMP=50         # 警告門檻
CRIT_TEMP=55         # 保護門檻（AC OFF + 中止整場）

POLL_SECS=30                 # watchdog 讀溫間隔
STABLE_COUNT=2               # 連續 N 次達標才算溫度到位（防抖動）
WAIT_TIMEOUT_SECS=86400      # 單次等溫逾時（24 小時；chamber 無固定開始時間）
BMC_BOOT_TIMEOUT_SECS=180    # AC ON 後等 BMC sensor 上線
WAIT_BOOT_SECS=300           # 開機後等系統穩定
PING_RETRY_SECS=30
MAX_PING_RETRIES=40          # 網路等待上限 20 分鐘
AC_OFF_DELAY_SECS=60         # AC OFF 後等待放電
DEGRADED_MODE="${DEGRADED_MODE:-on}"  # on = BMC 下線時 per-machine 降級判定；off = 舊行為
OS_BOOT_DEADLINE_SECS=300    # DEGRADED 時等 OS ping 通上限（實測 596 輪 max 216s + margin）
OS_CPU_WARN=85               # OS 端備援溫度 WARN 門檻（CPU °C，暫定值；DUT 上電後依 sensors 調整）
OS_CPU_CRIT=95               # OS 端備援溫度 PROTECT 門檻（≥ 即 AC OFF + 中止整場）
KCS_TIMEOUT_SECS=30          # KCS 救援 SDR 的 timeout

NETWORK_HOSTS=("192.168.11.82" "192.168.11.85")
BMC_HOSTS=("192.168.11.222" "192.168.11.234")
# AC 電源 helper（021/022 呼叫相對路徑的 lxRW_x64，必須在該目錄內執行）
AC_HELPER_DIR="${AC_HELPER_DIR:-/ED/QT_Cycling_Multi-SVR-AC}"

OS_USER="root"
OS_KEY="/root/.ssh/id_ed25519"   # AC server → 待測物 OS 的金鑰（免密 ssh）
BMC_USER="admin"
BMC_PASS="adminvastdata"

# SSH bootstrap（新 AC server＋新 DUT 環境用；舊環境已免密時自動跳過）
DUT_PASS="rootvastdata"   # 只用於首次裝公鑰（expect）；已免密則完全不用
SSH_REKEY=0               # 1 = 強制在本機重建金鑰對（舊金鑰先備份 .bak.<時間戳>）
SSH_RETRY_MAX=3           # 裝公鑰失敗後，互動詢問新密碼的重試次數

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_STAMP="$(date '+%Y%m%d_%H%M%S')"
LOW_LOG_FILE="${SCRIPT_DIR}/ZV2_temp_low_${LOG_STAMP}.txt"
HIGH_LOG_FILE="${SCRIPT_DIR}/ZV2_temp_high_${LOG_STAMP}.txt"
LOG_FILE="$LOW_LOG_FILE"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zv2_temp.XXXXXX")"
ABORT_FILE="$WORK_DIR/abort"
CURRENT_LOG="$WORK_DIR/current_log"

declare -A PREV_TEMP=()      # watchdog 內部：各 BMC 上次讀值（50°C 邊緣偵測用）
declare -A PREV_OS_TEMP=()   # OS 備援 watchdog 內部：各 DUT 上次 CPU 讀值（邊緣偵測用）
declare -a MACHINE_STATE=()  # 本輪各機狀態：normal|degraded|powerfail（未設定 = normal）
declare -a SDR_SOURCE=()     # degraded 機的 SDR 來源：kcs|missing
declare -a DEGRADED_WD_PIDS=()  # 本輪啟動的 OS 備援 watchdog PID
declare -A SEL_START=()       # M0：測試開始時各 BMC 的 SEL 最大 record ID（空 = 讀取失敗）
declare -A SEL_HIGH_START=()  # M2：高溫段開始時各 BMC 的 SEL 最大 record ID（跳過高溫段/低溫段時可能為空）

CYCLE=0
FAIL_COUNT=0
DEGRADED_COUNT=0       # 台次：BMC 下線但走 OS 路徑（有跑 OS 腳本）
POWER_FAIL_COUNT=0     # 台次：relay ON 但 BMC/OS 皆不可達（供電鏈嫌疑）
WATCHDOG_PID=""

# ── 基本工具 ──────────────────────────────────────────
set_log() {   # $1=low|high — 切換目前 log 檔
    if [ "$1" = low ]; then LOG_FILE="$LOW_LOG_FILE"; else LOG_FILE="$HIGH_LOG_FILE"; fi
    printf '%s' "$LOG_FILE" > "$CURRENT_LOG"
}

# 目前 log 檔（含 watchdog 子 shell 也能跟隨切換）
cur_log() { cat "$CURRENT_LOG" 2>/dev/null || echo "$LOG_FILE"; }

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$(cur_log)"
}

section() {
    {
        echo "================================================================================"
        echo "====== $*"
        echo "================================================================================"
    } >> "$(cur_log)"
}

ac_on()  { log "AC ON";  ( cd "$AC_HELPER_DIR" && ./022.ac_power_on.sh )  >>"$(cur_log)" 2>&1; }
ac_off() { log "AC OFF"; ( cd "$AC_HELPER_DIR" && ./021.ac_power_off.sh ) >>"$(cur_log)" 2>&1; }

cleanup() {
    [ -n "$WATCHDOG_PID" ] && kill "$WATCHDOG_PID" 2>/dev/null
    cleanup_degraded_watchers
    rm -rf "$WORK_DIR"
}
trap 'log "中斷：停在 cycle $CYCLE，watchdog 已停止，目前 AC 狀態請人工確認。"; cleanup; exit 130' INT TERM

set_log low

# ── 溫度讀取 ──────────────────────────────────────────
bmc_sdr() {
    ipmitool -I lanplus -H "$1" -U "$BMC_USER" -P "$BMC_PASS" sdr 2>/dev/null
}

# 讀 TEMP_Sys_Inlet；成功回傳整數（可負數），失敗回傳 "unknown"
read_temp() {
    local v
    v="$(bmc_sdr "$1" | awk '/TEMP_Sys_Inlet/ {print $3; exit}')"
    if [[ "$v" =~ ^-?[0-9]+$ ]]; then echo "$v"; else echo "unknown"; fi
}

# 背景保護：每 30s 讀兩台 BMC；≥50 邊緣警告；≥55 立即 AC OFF + 中止
watchdog() {
    local ip t prev
    while [ ! -f "$ABORT_FILE" ]; do
        for ip in "${BMC_HOSTS[@]}"; do
            t="$(read_temp "$ip")"
            echo "$t" > "$WORK_DIR/temp_${ip}"
            [ "$t" = "unknown" ] && continue
            if [ "$t" -ge "$CRIT_TEMP" ]; then
                log "PROTECT: $ip TEMP_Sys_Inlet ${t}°C ≥ ${CRIT_TEMP}°C — 立即 AC OFF，中止整場測試"
                ac_off
                touch "$ABORT_FILE"
                return
            fi
            prev="${PREV_TEMP[$ip]:-unknown}"
            if [ "$t" -ge "$WARN_TEMP" ] && { [ "$prev" = "unknown" ] || [ "$prev" -lt "$WARN_TEMP" ]; }; then
                log "WARN: $ip TEMP_Sys_Inlet ${t}°C ≥ ${WARN_TEMP}°C（上次 ${prev}）"
            fi
            PREV_TEMP[$ip]="$t"
        done
        sleep "$POLL_SECS"
    done
}

check_abort() {
    if [ -f "$ABORT_FILE" ]; then
        log "偵測到中止訊號（watchdog 已動作），結束測試。"
        cleanup
        exit 1
    fi
}

# 等所有 BMC sensor 上線（AC ON 後）
wait_bmc_ready() {
    local i ip ok
    for i in $(seq 1 $((BMC_BOOT_TIMEOUT_SECS / 5))); do
        ok=1
        for ip in "${BMC_HOSTS[@]}"; do
            [ "$(read_temp "$ip")" = "unknown" ] && { ok=0; break; }
        done
        [ "$ok" -eq 1 ] && return 0
        sleep 5
    done
    log "BMC 於 ${BMC_BOOT_TIMEOUT_SECS}s 內未上線"
    return 1
}

# 等溫度：$1=le|ge  $2=門檻  $3=標籤
# 條件 = 兩台 BMC 皆 known 且皆達標，且連續 STABLE_COUNT 次
# 每次輪詢直接讀 BMC（與 watchdog 同節奏），把每次讀值寫進 log
wait_for_temp() {
    local op="$1" target="$2" label="$3"
    local op_str; [ "$op" = le ] && op_str="≤" || op_str="≥"
    local elapsed=0 stable=0
    log "等待${label}：TEMP_Sys_Inlet ${op_str} ${target}°C（兩台皆達標，逾時 $((WAIT_TIMEOUT_SECS / 3600))h）"
    while [ "$elapsed" -lt "$WAIT_TIMEOUT_SECS" ]; do
        check_abort
        local ip t all_ok=1
        for ip in "${BMC_HOSTS[@]}"; do
            t="$(read_temp "$ip")"
            log "  ${ip}: ${t}°C"
            if [ "$t" = "unknown" ]; then all_ok=0; continue; fi
            local pass=0
            [ "$op" = le ] && [ "$t" -le "$target" ] && pass=1
            [ "$op" = ge ] && [ "$t" -ge "$target" ] && pass=1
            [ "$pass" -eq 1 ] || all_ok=0
        done
        if [ "$all_ok" -eq 1 ]; then
            stable=$((stable + 1))
            log "  達標 ${stable}/${STABLE_COUNT}"
            if [ "$stable" -ge "$STABLE_COUNT" ]; then
                log "${label}達成（連續 ${stable} 次達標），繼續執行"
                for ip in "${BMC_HOSTS[@]}"; do dump_sdr "$ip"; done
                return 0
            fi
        else
            stable=0
        fi
        sleep "$POLL_SECS"
        elapsed=$((elapsed + POLL_SECS))
    done
    log "FAIL: ${label}逾時 $((WAIT_TIMEOUT_SECS / 3600))h，疑似 chamber 異常，中止測試"
    touch "$ABORT_FILE"
    return 1
}

# ── 測試步驟 ──────────────────────────────────────────
wait_for_hosts() {
    local i host ok
    for i in $(seq 1 "$MAX_PING_RETRIES"); do
        check_abort
        ok=1
        for host in "${NETWORK_HOSTS[@]}"; do
            ping -c 1 -W 2 "$host" >/dev/null 2>&1 || { ok=0; break; }
        done
        [ "$ok" -eq 1 ] && return 0
        log "有網絡不可達，${PING_RETRY_SECS}s 後重試 ($i/$MAX_PING_RETRIES)"
        sleep "$PING_RETRY_SECS"
    done
    log "FAIL: 開機後 $((MAX_PING_RETRIES * PING_RETRY_SECS / 60)) 分鐘仍未連通"
    return 1
}

# 長 sleep 中每 30s 檢查中止訊號（保護本身由 watchdog 負責）
monitored_sleep() {
    local total="$1" left="$1" chunk
    while [ "$left" -gt 0 ]; do
        check_abort
        chunk="$POLL_SECS"; [ "$left" -lt "$chunk" ] && chunk="$left"
        sleep "$chunk"
        left=$((left - chunk))
    done
}

run_os_script() {
    local host="$1"
    section "cycle $CYCLE @ $host"
    ssh -i "$OS_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=15 "$OS_USER@$host" \
        "cd /root/tools/scripts && ./pcie_link_control_ceres.py -a enable -g default \
         && sleep 30 && ./slot_to_nvme_ceres.py -a" >> "$(cur_log)" 2>&1
    local rc=$?
    [ "$rc" -eq 0 ] || log "FAIL: $host OS script exited $rc"
    return "$rc"
}

# ── SSH bootstrap：新 AC server＋新 DUT 環境自動建鑰＋授權 ──────────
# 1) 本機金鑰對：不存在就建；SSH_REKEY=1 強制重建（舊金鑰先備份）
# 2) 每台 DUT：已免密 → 跳過；否 → expect 用 DUT_PASS 登入把公鑰裝進
#    /root/.ssh/authorized_keys（公鑰走 base64 傳輸，免引號問題）
# 3) 失敗 → 互動詢問密碼重試（最多 SSH_RETRY_MAX 次，Enter 放棄）
#    重試只問新密碼、不重蓋金鑰（重蓋會作廢 DUT 上既有授權）。
# 互動詢問需要前台 TTY；nohup/背景執行時偵測不到就中止。
stdin_is_tty() { [ -t 0 ]; }

os_try_key() {   # $1=host — 免密驗證（成功回 0）
    ssh -i "$OS_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=15 "$OS_USER@$1" 'true' >/dev/null 2>&1
}

ensure_local_key() {
    if [ "$SSH_REKEY" -eq 1 ] && [ -f "$OS_KEY" ]; then
        cp -p "$OS_KEY" "$OS_KEY.bak.$(date +%s)" && rm -f "$OS_KEY" "$OS_KEY.pub"
        log "SSH_REKEY=1：舊金鑰已備份，強制重建"
    fi
    [ -f "$OS_KEY" ] && return 0
    mkdir -p "$(dirname "$OS_KEY")" && chmod 700 "$(dirname "$OS_KEY")"
    ssh-keygen -t ed25519 -N '' -q -f "$OS_KEY" || return 1
    chmod 600 "$OS_KEY"
    log "SSH 金鑰已建立：$OS_KEY"
}

install_pubkey() {   # $1=host $2=密碼 — expect 登入並附加公鑰；成功回 0
    command -v expect >/dev/null || { log "FAIL: AC server 沒有 expect（yum install expect）"; return 1; }
    local host="$1" pass="$2"
    [ -f "$OS_KEY.pub" ] || { log "FAIL: 缺公鑰 $OS_KEY.pub"; return 1; }
    # 值走環境變數傳入 expect（$env()），heredoc 用引號 EOF 免被 bash 展開
    EXPECT_USER="$OS_USER" EXPECT_HOST="$host" EXPECT_PASS="$pass" \
    EXPECT_B64="$(base64 -w0 < "$OS_KEY.pub")" expect <<'EOF'
set timeout 30
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=15 $env(EXPECT_USER)@$env(EXPECT_HOST)
expect {
    -re {(?i)password} { send "$env(EXPECT_PASS)\r" }
    timeout { exit 1 }
    eof     { exit 1 }
}
expect {
    -re {(?i)password} { exit 1 }   # 第二次要密碼 = 密碼錯
    -re {(?i)\][#\$]|\$$} {}        # shell prompt（root: ]#）
    timeout { exit 1 }
    eof     { exit 1 }
}
send "install -d -m 700 ~/.ssh && printf '%s\\n' \"$env(EXPECT_B64)\" | base64 -d >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo KEY-INSTALLED\r"
expect {
    "KEY-INSTALLED" {}
    timeout { exit 1 }
    eof     { exit 1 }
}
send "exit\r"
expect eof
EOF
}

bootstrap_ssh() {
    log "===== SSH bootstrap：金鑰對＋DUT 免密授權 ====="
    ensure_local_key || { log "FAIL: 本機 SSH 金鑰建立失敗（ssh-keygen）"; return 1; }
    local host attempt pass ok
    for host in "${NETWORK_HOSTS[@]}"; do
        if os_try_key "$host"; then
            log "SSH $host: 已免密，跳過"
            continue
        fi
        if install_pubkey "$host" "$DUT_PASS" && os_try_key "$host"; then
            log "SSH $host: 公鑰安裝成功（DUT_PASS），免密驗證 OK"
            continue
        fi
        log "WARN: SSH $host: 首次裝公鑰失敗（密碼錯 / 連不到 / 無 expect）"
        ok=0
        for ((attempt = 1; attempt <= SSH_RETRY_MAX && ! ok; attempt++)); do
            if stdin_is_tty; then
                printf '輸入 %s 的 root 密碼（重試 %d/%d，Enter 放棄）: ' \
                    "$host" "$attempt" "$SSH_RETRY_MAX"
                IFS= read -rs pass
                printf '\n'
            else
                log "FAIL: 非前台 TTY（nohup/背景執行），無法互動詢問密碼"
                break
            fi
            [ -n "$pass" ] || break
            if install_pubkey "$host" "$pass" && os_try_key "$host"; then
                log "SSH $host: 公鑰安裝成功（互動密碼），免密驗證 OK"
                ok=1
            fi
        done
        [ "$ok" -eq 1 ] || { log "FAIL: SSH $host 免密授權建立失敗，中止"; return 1; }
    done
    log "SSH bootstrap: 全部 DUT 免密 OK"
}

dump_sdr() {
    local ip="$1" out rc
    section "cycle $CYCLE BMC SDR $ip"
    out="$(bmc_sdr "$ip")"; rc=$?
    if [ $rc -eq 0 ]; then
        printf '%s\n' "$out" | sed 's/^/  /' >> "$(cur_log)"
    else
        log "FAIL: ipmitool sdr $ip exited $rc"
    fi
    sleep 10
    return "$rc"
}

# 讀某台 BMC 目前 SEL 的最大 record ID（4 位 hex）；失敗回傳 1
sel_max_id() {
    local ip="$1" out
    out="$(ipmitool -I lanplus -H "$ip" -U "$BMC_USER" -P "$BMC_PASS" sel elist 2>/dev/null)" || return 1
    printf '%s\n' "$out" | awk '
        ($1"") ~ /^0x[0-9A-Fa-f]+$/ { if (($1"") > (m"")) m=$1 }
        END { if (m != "") print m; else exit 1 }
    '
}

# 跑測試前一次性清 SEL（DUT 之前有他人測試殘留）：
# 必須在記第一個 mark（M0）之前執行（先清、再記 mark）；
# 絕不在 M2 前重清（會洗掉低溫段 SEL）。
SEL_PRETEST_CLEARED=0
clear_sel_pretest() {
    [ "$SEL_PRETEST_CLEARED" -eq 1 ] && return
    local ip out
    for ip in "${BMC_HOSTS[@]}"; do
        if out=$(ipmitool -I lanplus -H "$ip" -U "$BMC_USER" -P "$BMC_PASS" sel clear 2>&1); then
            log "SEL pretest clear $ip: OK${out:+ ($out)}"
        else
            log "WARN: SEL pretest clear $ip 失敗（${out:-無訊息}）—— 測試前舊歷史可能混入本場 log"
        fi
    done
    SEL_PRETEST_CLEARED=1
}

# 記錄分界 mark：$1=M0（測試開始）| M2（高溫段開始）
record_mark() {
    local tag="$1" ip v
    for ip in "${BMC_HOSTS[@]}"; do
        if v="$(sel_max_id "$ip")"; then
            if [ "$tag" = M0 ]; then SEL_START[$ip]="$v"; else SEL_HIGH_START[$ip]="$v"; fi
            log "SEL mark($tag) $ip: 目前最大 record ID $v"
        else
            log "WARN: SEL mark($tag) $ip 讀取失敗（收尾時該台 fallback 全量 dump）"
        fi
    done
}

# 過濾 elist 輸出：保留 (lo, hi] 的 entry（hi="MAX" = 無上限）；lexicographic 比較 4 位 hex
sel_filter() {
    printf '%s\n' "$1" | awk -v lo="$2" -v hi="$3" '
        NR==1 { print; next }
        ($1"") ~ /^0x[0-9A-Fa-f]+$/ &&
        ($1"") > (lo"") && (hi=="MAX" || ($1"") <= (hi""))
    '
}

# 寫入一個 SEL 區塊：$1=檔  $2=標題  $3=elist  $4=elist -v
write_sel() {
    local n
    n="$(printf '%s\n' "$3" | awk 'NR>1' | wc -l)"
    {
        echo "================================================================================"
        echo "====== $2"
        echo "================================================================================"
        printf '%s\n' "$3"
        [ "$n" -eq 0 ] && echo "（此段區間內無 SEL 記錄）"
        echo
        printf '%s\n' "$4"
        echo
    } >> "$1"
}

# 收尾：抓全量 SEL，依 mark 分段寫入 low/high 兩份 log
dump_sel() {
    local ip="$1"
    local m0="${SEL_START[$ip]:-}" m2="${SEL_HIGH_START[$ip]:-}"
    local full fullv rc hist
    full="$(ipmitool -I lanplus -H "$ip" -U "$BMC_USER" -P "$BMC_PASS" sel elist 2>&1)"; rc=$?
    if [ $rc -ne 0 ]; then
        log "FAIL: ipmitool sel $ip exited $rc，無法抓 SEL"
        return 1
    fi
    sleep 5
    fullv="$(ipmitool -I lanplus -H "$ip" -U "$BMC_USER" -P "$BMC_PASS" sel elist -v 2>&1)"; rc=$?
    if [ $rc -ne 0 ]; then
        log "FAIL: ipmitool sel -v $ip exited $rc"
        return 1
    fi
    sleep 5

    if [ -z "$m0" ]; then
        log "WARN: $ip 缺測試開始 mark，SEL 全量（含測試前歷史）寫入兩份 log"
        write_sel "$LOW_LOG_FILE"  "BMC SEL（全量）$ip" "$full" "$fullv"
        write_sel "$HIGH_LOG_FILE" "BMC SEL（全量）$ip" "$full" "$fullv"
        return 0
    fi

    if [ -n "$m2" ]; then
        log "SEL $ip: 低溫段 (ID >$m0 ≤$m2) + 高溫段 (ID >$m2) 分段寫入"
        write_sel "$LOW_LOG_FILE"  "BMC SEL $ip（低溫段，record ID $m0..$m2）"  "$(sel_filter "$full"  "$m0" "$m2")"  "$(sel_filter "$fullv" "$m0" "$m2")"
        write_sel "$HIGH_LOG_FILE" "BMC SEL $ip（高溫段，record ID >$m2）"       "$(sel_filter "$full"  "$m2" "MAX")" "$(sel_filter "$fullv" "$m2" "MAX")"
    elif [ "$HIGH_CYCLES" -eq 0 ]; then
        # 跳過高溫段：(m0, max] 全屬低溫段（m2 必然為空，故須先於 WARN 判斷）
        log "SEL $ip: 跳過高溫段，(ID >$m0) 全數寫入 low 檔"
        write_sel "$LOW_LOG_FILE" "BMC SEL $ip（全部，record ID >$m0）" "$(sel_filter "$full" "$m0" "MAX")" "$(sel_filter "$fullv" "$m0" "MAX")"
        { echo "===== 跳過高溫段（HIGH_CYCLES=0），無高溫段 SEL ====="; echo; } >> "$HIGH_LOG_FILE"
    elif [ "$LOW_CYCLES" -eq 0 ]; then
        # 跳過低溫段：測試直接從高溫段開始，(m0, max] 全屬高溫段
        log "SEL $ip: 跳過低溫段，(ID >$m0) 全數寫入 high 檔"
        write_sel "$HIGH_LOG_FILE" "BMC SEL $ip（全部，record ID >$m0）" "$(sel_filter "$full" "$m0" "MAX")" "$(sel_filter "$fullv" "$m0" "MAX")"
        { echo "===== 跳過低溫段（LOW_CYCLES=0），無低溫段 SEL ====="; echo; } >> "$LOW_LOG_FILE"
    else
        log "WARN: $ip 缺高溫段開始 mark，SEL 全量（含測試前歷史）寫入兩份 log"
        write_sel "$LOW_LOG_FILE"  "BMC SEL（全量）$ip" "$full" "$fullv"
        write_sel "$HIGH_LOG_FILE" "BMC SEL（全量）$ip" "$full" "$fullv"
    fi

    hist="$(printf '%s\n' "$full" | awk -v m0="$m0" '($1"") ~ /^0x[0-9A-Fa-f]+$/ && ($1"") <= (m0"") {n++} END{print n+0}')"
    if [ "$hist" -gt 0 ]; then
        log "SEL $ip: 測試前既有歷史 $hist 筆（ID ≤ $m0），未寫入本場 log（BMC 內仍保留）"
    fi
}

# ── Degraded mode 函式（DEGRADED_MODE=on 時才走；off 時完全不呼叫）────────
# 等單一 DUT OS ping 通（deadline 秒）；成功回 0
wait_os_ping() {
    local host="$1" deadline="$2" i
    for i in $(seq 1 $((deadline / 5))); do
        ping -c 1 -W 2 "$host" >/dev/null 2>&1 && return 0
        sleep 5
    done
    return 1
}

# 讀 DUT OS 端 CPU 最高溫（hwmon，°C）；失敗回 "unknown"
os_temp() {
    local host="$1" v
    v="$(ssh -i "$OS_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=10 "$OS_USER@$host" \
        'for f in /sys/class/hwmon/hwmon*/temp*_input; do t=$(cat "$f" 2>/dev/null); [ -n "$t" ] && echo $((t / 1000)); done' \
        2>/dev/null | sort -rn | head -1)"
    if [[ "$v" =~ ^-?[0-9]+$ ]]; then echo "$v"; else echo "unknown"; fi
}

# KCS 探測：DUT OS 本地 ipmitool 是否可用（輕量，一次快讀）
kcs_probe() {
    local host="$1" out
    out="$(timeout "$KCS_TIMEOUT_SECS" ssh -i "$OS_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=10 "$OS_USER@$host" \
        'ipmitool sdr 2>/dev/null | head -2' 2>/dev/null)"
    [ -n "$out" ]
}

# KCS 抓全量 SDR（BMC 本體活著、lanplus 掛時的救援）
kcs_sdr() {
    local host="$1" out rc
    section "cycle $CYCLE BMC SDR (via KCS) $host"
    out="$(timeout "$KCS_TIMEOUT_SECS" ssh -i "$OS_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=10 "$OS_USER@$host" 'ipmitool sdr' 2>/dev/null)"; rc=$?
    if [ $rc -eq 0 ] && [ -n "$out" ]; then
        printf '%s\n' "$out" | sed 's/^/  /' >> "$(cur_log)"
        return 0
    fi
    log "FAIL: KCS sdr $host exited $rc"
    return 1
}

# SDR 缺失標記（KCS 也失敗）＋ OS 端 hwmon 輸出當備援
sdr_missing() {
    local host="$1"
    section "cycle $CYCLE BMC SDR MISSING $host"
    log "SDR MISSING: $host（BMC 不可達且 KCS 失敗，本輪 SDR 缺失）"
    ssh -i "$OS_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o BatchMode=yes -o ConnectTimeout=10 "$OS_USER@$host" \
        'sensors 2>/dev/null; for p in /sys/class/hwmon/hwmon*; do
            [ -d "$p" ] && { echo "== $p"; for t in "$p"/temp*_label "$p"/temp*_input; do [ -e "$t" ] && echo "$t: $(cat "$t" 2>/dev/null)"; done; };
         done' >> "$(cur_log)" 2>&1 || true
    return 1
}

# OS 端備援溫度 watchdog（per DEGRADED 機，背景執行）
os_temp_watcher() {
    local host="$1" t prev
    while [ ! -f "$ABORT_FILE" ]; do
        t="$(os_temp "$host")"
        echo "$t" > "$WORK_DIR/ostemp_${host}"
        if [ "$t" != "unknown" ]; then
            if [ "$t" -ge "$OS_CPU_CRIT" ]; then
                log "PROTECT: $host OS CPU ${t}°C ≥ ${OS_CPU_CRIT}°C（BMC 下線備援 watchdog）— 立即 AC OFF，中止整場測試"
                ac_off
                touch "$ABORT_FILE"
                return
            fi
            prev="${PREV_OS_TEMP[$host]:-unknown}"
            if [ "$t" -ge "$OS_CPU_WARN" ] && { [ "$prev" = "unknown" ] || [ "$prev" -lt "$OS_CPU_WARN" ]; }; then
                log "WARN: $host OS CPU ${t}°C ≥ ${OS_CPU_WARN}°C（BMC 下線備援 watchdog）"
            fi
            PREV_OS_TEMP[$host]="$t"
        fi
        sleep "$POLL_SECS"
    done
}

cleanup_degraded_watchers() {
    local pid
    [ ${#DEGRADED_WD_PIDS[@]} -gt 0 ] || return 0
    for pid in "${DEGRADED_WD_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    DEGRADED_WD_PIDS=()
    return 0
}

# 等單一 DUT OS 網路通（舊 wait_for_hosts 的單機版）
wait_for_hosts_one() {
    local i host="$1"
    for i in $(seq 1 "$MAX_PING_RETRIES"); do
        check_abort
        ping -c 1 -W 2 "$host" >/dev/null 2>&1 && return 0
        log "  $host 不可達，${PING_RETRY_SECS}s 後重試 ($i/$MAX_PING_RETRIES)"
        sleep "$PING_RETRY_SECS"
    done
    log "FAIL: $host 開機後 $((MAX_PING_RETRIES * PING_RETRY_SECS / 60)) 分鐘仍未連通"
    return 1
}

# per-machine 分類：BMC 下線的機器改試 OS 路徑
# 結果寫入 MACHINE_STATE[i] = normal|degraded|powerfail
# 回 0 = 至少一台有電（normal 或 degraded）；回 1 = 兩台都 powerfail
run_degraded() {
    local i host bmc s any_power
    cleanup_degraded_watchers
    MACHINE_STATE=()
    SDR_SOURCE=()
    for i in 0 1; do
        host="${NETWORK_HOSTS[$i]}"
        bmc="${BMC_HOSTS[$i]}"
        if [ "$(read_temp "$bmc")" != "unknown" ]; then
            MACHINE_STATE[$i]="normal"
            continue
        fi
        log "DEGRADED: cycle $CYCLE $bmc BMC 不可達 → 試 OS 路徑（$host）"
        if wait_os_ping "$host" "$OS_BOOT_DEADLINE_SECS"; then
            MACHINE_STATE[$i]="degraded"
            DEGRADED_COUNT=$((DEGRADED_COUNT + 1))
            if kcs_probe "$host"; then
                SDR_SOURCE[$i]="kcs"
                log "  KCS 探測 OK：SDR 稍後經 KCS 抓取（BMC 本體活著，lanplus 故障）"
            else
                SDR_SOURCE[$i]="missing"
                log "  KCS 探測失敗：BMC 疑似整個下線，SDR 將標記 MISSING"
            fi
            ( os_temp_watcher "$host" ) &
            DEGRADED_WD_PIDS+=("$!")
            log "  OS 備援溫度 watchdog 已啟動（${host}，≥${OS_CPU_WARN}°C WARN / ≥${OS_CPU_CRIT}°C PROTECT）"
        else
            MACHINE_STATE[$i]="powerfail"
            POWER_FAIL_COUNT=$((POWER_FAIL_COUNT + 1))
            log "POWER-FAIL: cycle $CYCLE $host relay ON 但 BMC/OS 皆不可達（BMC 逾時 + OS ${OS_BOOT_DEADLINE_SECS}s）— 供電鏈嫌疑（relay 接點 / PSU）"
        fi
    done
    any_power=0
    for s in "${MACHINE_STATE[@]}"; do
        case "$s" in normal|degraded) any_power=1;; esac
    done
    return $((1 - any_power))
}

# 單一循環；回傳 2 = 中止
run_cycle() {
    local i ip t all_up
    log "──────── cycle $CYCLE / $TOTAL_CYCLES ────────"

    if ! ac_on; then
        log "FAIL: cycle $CYCLE AC ON 失敗"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
    if ! wait_bmc_ready; then
        if [ "$DEGRADED_MODE" != on ]; then
            # 舊行為：整輪跳過
            log "FAIL: cycle $CYCLE BMC 未上線，跳過"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            ac_off; sleep "$AC_OFF_DELAY_SECS"
            return 1
        fi
        # 降級模式：per-machine 判定（BMC 下線的機器改試 OS 路徑）
        log "BMC 未全數上線（DEGRADED_MODE=on）→ per-machine 判定"
        if ! run_degraded; then
            log "FAIL: cycle $CYCLE 兩台皆 POWER-FAIL，跳過"
            ac_off; sleep "$AC_OFF_DELAY_SECS"
            return 1
        fi
    fi
    # 開機前溫度雙重保險（watchdog 已在跑；只查 BMC 在線的機器）
    for i in 0 1; do
        [ "${MACHINE_STATE[$i]:-normal}" = normal ] || continue
        ip="${BMC_HOSTS[$i]}"
        t="$(read_temp "$ip")"
        if [ "$t" != "unknown" ] && [ "$t" -ge "$CRIT_TEMP" ]; then
            log "PROTECT: $ip ${t}°C ≥ ${CRIT_TEMP}°C，本輪未執行即中止"
            ac_off
            cleanup_degraded_watchers
            touch "$ABORT_FILE"
            return 2
        fi
    done

    # 等網路（只有 normal 機要等；degraded 機分類時已 ping 通）
    all_up=1
    for i in 0 1; do
        [ "${MACHINE_STATE[$i]:-normal}" = normal ] || continue
        wait_for_hosts_one "${NETWORK_HOSTS[$i]}" || all_up=0
    done
    if [ "$all_up" -ne 1 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        ac_off; sleep "$AC_OFF_DELAY_SECS"
        cleanup_degraded_watchers
        return 1
    fi
    log "所有網絡可達，等待 ${WAIT_BOOT_SECS}s 系統穩定"
    monitored_sleep "$WAIT_BOOT_SECS"

    # OS 腳本：normal + degraded 各跑各的
    for i in 0 1; do
        case "${MACHINE_STATE[$i]:-normal}" in
            normal|degraded)
                run_os_script "${NETWORK_HOSTS[$i]}" || FAIL_COUNT=$((FAIL_COUNT + 1))
                ;;
        esac
    done
    # SDR：normal 走 lanplus；degraded 走 KCS 或標 MISSING
    for i in 0 1; do
        case "${MACHINE_STATE[$i]:-normal}" in
            normal)
                dump_sdr "${BMC_HOSTS[$i]}" || FAIL_COUNT=$((FAIL_COUNT + 1))
                ;;
            degraded)
                case "${SDR_SOURCE[$i]:-missing}" in
                    kcs)
                        kcs_sdr "${NETWORK_HOSTS[$i]}" || FAIL_COUNT=$((FAIL_COUNT + 1))
                        ;;
                    *)
                        sdr_missing "${NETWORK_HOSTS[$i]}"
                        FAIL_COUNT=$((FAIL_COUNT + 1))
                        ;;
                esac
                ;;
        esac
    done
    check_abort
    cleanup_degraded_watchers

    ac_off
    sleep "$AC_OFF_DELAY_SECS"
}

# ── 主流程 ────────────────────────────────────────────
[ "$TOTAL_CYCLES" -gt 0 ] || { echo "錯誤：LOW_CYCLES + HIGH_CYCLES 必須 > 0"; exit 1; }

log "開始：低溫段 $LOW_CYCLES 輪 + 高溫段 $HIGH_CYCLES 輪"
log "log 檔：$LOW_LOG_FILE / $HIGH_LOG_FILE"
bootstrap_ssh || { cleanup; exit 1; }
( watchdog ) &
WATCHDOG_PID=$!

# 階段 0/1：低溫段（LOW_CYCLES=0 時整段跳過）
if [ "$LOW_CYCLES" -gt 0 ]; then
    log "===== 階段 0：AC ON，等低溫（≤ ${LOW_TEMP}°C）====="
    ac_on
    if ! wait_bmc_ready; then
        log "FAIL: 初始 BMC 未上線，中止"
        cleanup; exit 1
    fi
    clear_sel_pretest   # 先清他人測試殘留（在記 M0 之前），避免舊歷史混入
    record_mark M0   # 測試開始 mark：此後產生的 SEL 才算本場
    wait_for_temp le "$LOW_TEMP" "低溫" || { cleanup; exit 1; }
    # 等待期結束：關機，讓每個 cycle 都從 OFF 狀態開始（一致語意）
    ac_off
    sleep "$AC_OFF_DELAY_SECS"

    log "===== 階段 1：低溫段 cycle 1..$LOW_CYCLES ====="
    while [ "$CYCLE" -lt "$LOW_CYCLES" ]; do
        CYCLE=$((CYCLE + 1))
        run_cycle "$CYCLE"
        check_abort
    done
else
    log "===== 跳過低溫段（LOW_CYCLES=0），直接進入高溫等待 ====="
fi

# 階段 2/3：高溫段（HIGH_CYCLES=0 時整段跳過）；cycle 編號重新從 1 起
if [ "$HIGH_CYCLES" -gt 0 ]; then
    set_log high
    log "===== 階段 2：AC ON，等高溫（≥ ${HIGH_TEMP}°C）====="
    ac_on
    if ! wait_bmc_ready; then
        log "FAIL: 高溫等待前 BMC 未上線，中止"
        cleanup; exit 1
    fi
    if [ "$LOW_CYCLES" -gt 0 ]; then
        record_mark M2   # 高溫段開始 mark：之前全數屬低溫段
    else
        clear_sel_pretest   # 跳過低溫段：先清舊 SEL 再記第一個 mark
        record_mark M0   # 跳過低溫段：此 BMC 上線即測試開始
    fi
    wait_for_temp ge "$HIGH_TEMP" "高溫" || { cleanup; exit 1; }

    log "===== 階段 3：高溫段 cycle 1..$HIGH_CYCLES ====="
    for i in $(seq 1 "$HIGH_CYCLES"); do
        CYCLE=$i
        run_cycle "$CYCLE"
        check_abort
    done
else
    log "===== 跳過高溫段（HIGH_CYCLES=0），直接進入收尾 ====="
fi

# 收尾：抓 SEL 並最終關機
log "===== 收尾：抓 SEL ====="
ac_on
if wait_bmc_ready; then
    for ip in "${BMC_HOSTS[@]}"; do
        dump_sel "$ip"
    done
else
    log "FAIL: 收尾 BMC 未上線，無法抓 SEL"
fi
ac_off

kill "$WATCHDOG_PID" 2>/dev/null
rm -rf "$WORK_DIR"
log "END — 完成 $TOTAL_CYCLES 輪（DEGRADED $DEGRADED_COUNT 台次 / POWER-FAIL $POWER_FAIL_COUNT 台次），累計 $FAIL_COUNT 次步驟失敗（PROTECT/WARN 事件請查 log 與 SEL）"
