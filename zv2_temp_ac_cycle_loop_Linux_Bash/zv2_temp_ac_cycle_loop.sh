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
#   4. 收尾：AC ON → 抓 SEL（兩份 log 各存一份）→ AC OFF
#
# 單段測試：
#   LOW_CYCLES=0 → 跳過階段 0/1，直接進階段 2（等高溫）
#   HIGH_CYCLES=0 → 跳過階段 2/3，直接進收尾
#
# Log：低溫段與高溫段各一份，同一時間戳記配對
#   ZV2_temp_low_<開始時間>.txt / ZV2_temp_high_<開始時間>.txt
#   階段 0/1（等低溫 + 低溫循環）寫 low 檔；
#   階段 2/3（等高溫 + 高溫循環）寫 high 檔；
#   收尾 SEL 兩份各存一份（含全程 50/55 事件記錄）。
#
# 保護（背景 watchdog，每 30s 輪詢兩台 BMC 的 TEMP_Sys_Inlet）：
#   任一 ≥ 50°C → 警告 log（邊緣觸發，不重複刷屏）
#   任一 ≥ 55°C → 立即 AC OFF + 中止整場測試
#   讀不到溫度（BMC 未上線）= unknown：等待不算達標，保護不動作
#
# 用法：./zv2_temp_ac_cycle_loop.sh [低溫段輪數] [高溫段輪數]
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
WAIT_TIMEOUT_SECS=14400      # 單次等溫逾時（4 小時；chamber 無固定開始時間）
BMC_BOOT_TIMEOUT_SECS=180    # AC ON 後等 BMC sensor 上線
WAIT_BOOT_SECS=300           # 開機後等系統穩定
PING_RETRY_SECS=30
MAX_PING_RETRIES=40          # 網路等待上限 20 分鐘
AC_OFF_DELAY_SECS=60         # AC OFF 後等待放電

NETWORK_HOSTS=("192.168.15.99" "192.168.15.100")
BMC_HOSTS=("192.168.15.74" "192.168.15.73")
# AC 電源 helper（021/022 呼叫相對路徑的 lxRW_x64，必須在該目錄內執行）
AC_HELPER_DIR="${AC_HELPER_DIR:-/ED/QT_Cycling_Multi-SVR-AC}"

OS_USER="root"
OS_KEY="/root/.ssh/id_ed25519"   # AC server → 待測物 OS 的金鑰（免密 ssh）
BMC_USER="admin"
BMC_PASS="adminvastdata"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_STAMP="$(date '+%Y%m%d_%H%M%S')"
LOW_LOG_FILE="${SCRIPT_DIR}/ZV2_temp_low_${LOG_STAMP}.txt"
HIGH_LOG_FILE="${SCRIPT_DIR}/ZV2_temp_high_${LOG_STAMP}.txt"
LOG_FILE="$LOW_LOG_FILE"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zv2_temp.XXXXXX")"
ABORT_FILE="$WORK_DIR/abort"
CURRENT_LOG="$WORK_DIR/current_log"

declare -A PREV_TEMP=()      # watchdog 內部：各 BMC 上次讀值（50°C 邊緣偵測用）

CYCLE=0
FAIL_COUNT=0
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

dump_sel() {
    local ip="$1" out
    section "final BMC SEL $ip"
    out="$(ipmitool -I lanplus -H "$ip" -U "$BMC_USER" -P "$BMC_PASS" sel elist 2>&1)"; sleep 20
    section "final BMC SEL -v $ip"
    out2="$(ipmitool -I lanplus -H "$ip" -U "$BMC_USER" -P "$BMC_PASS" sel elist -v 2>&1)"; sleep 20
    # SEL 是全程記錄：兩份 log 各存一份
    for f in "$LOW_LOG_FILE" "$HIGH_LOG_FILE"; do
        printf '%s\n\n' "$out" "$out2" >> "$f"
    done
}

# 單一循環；回傳 2 = 中止
run_cycle() {
    local ip t
    log "──────── cycle $CYCLE / $TOTAL_CYCLES ────────"

    if ! ac_on; then
        log "FAIL: cycle $CYCLE AC ON 失敗"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
    if ! wait_bmc_ready; then
        log "FAIL: cycle $CYCLE BMC 未上線，跳過"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        ac_off; sleep "$AC_OFF_DELAY_SECS"
        return 1
    fi
    # 開機前溫度雙重保險（watchdog 已在跑，這裡是 AC ON 後第一讀）
    for ip in "${BMC_HOSTS[@]}"; do
        t="$(read_temp "$ip")"
        if [ "$t" != "unknown" ] && [ "$t" -ge "$CRIT_TEMP" ]; then
            log "PROTECT: $ip ${t}°C ≥ ${CRIT_TEMP}°C，本輪未執行即中止"
            ac_off
            touch "$ABORT_FILE"
            return 2
        fi
    done

    if ! wait_for_hosts; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        ac_off; sleep "$AC_OFF_DELAY_SECS"
        return 1
    fi
    log "所有網絡可達，等待 ${WAIT_BOOT_SECS}s 系統穩定"
    monitored_sleep "$WAIT_BOOT_SECS"

    for ip in "${NETWORK_HOSTS[@]}"; do
        run_os_script "$ip" || FAIL_COUNT=$((FAIL_COUNT + 1))
    done
    for ip in "${BMC_HOSTS[@]}"; do
        dump_sdr "$ip" || FAIL_COUNT=$((FAIL_COUNT + 1))
    done
    check_abort

    ac_off
    sleep "$AC_OFF_DELAY_SECS"
}

# ── 主流程 ────────────────────────────────────────────
[ "$TOTAL_CYCLES" -gt 0 ] || { echo "錯誤：LOW_CYCLES + HIGH_CYCLES 必須 > 0"; exit 1; }

log "開始：低溫段 $LOW_CYCLES 輪 + 高溫段 $HIGH_CYCLES 輪"
log "log 檔：$LOW_LOG_FILE / $HIGH_LOG_FILE"
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
log "END — 完成 $TOTAL_CYCLES 輪，累計 $FAIL_COUNT 次步驟失敗（PROTECT/WARN 事件請查 log 與 SEL）"
