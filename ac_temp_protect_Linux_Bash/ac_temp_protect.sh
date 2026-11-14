#!/bin/bash
# ============================================================================
# ac_temp_protect.sh — BMC 入口溫度持續過高時切斷 AC（不斷自動回電）
# Provenance: designed & validated by luke1987515 (AIC DQA); developed with
# AI assistance (Hermes Agent by Nous Research, self-hosted Qwen model
# family — earlier sessions may have used other models). See README.
#
# 目標環境   : CentOS 7/8 / bash 4.2+ / ipmitool
#              與 AC relay helper 放在同一台機器（目錄見下方 AC_HELPER_DIR）
#
# 用法:
#   ./ac_temp_protect.sh setup           跑一次：問 BMC IP、列出溫度 sensor 供選擇
#   ./ac_temp_protect.sh run             開始監控（前台執行，Ctrl+C 停止）
#   ./ac_temp_protect.sh run --dry-run   試跑：只記錄 log，不會真正斷電
#   ./ac_temp_protect.sh status          查看目前狀態
#   ./ac_temp_protect.sh power-on        手動回電（斷電後唯一回電途徑）
#   ./ac_temp_protect.sh clean           重置狀態回 NORMAL 基準（relay OFF 時問是否回電，
#                                        --yes 跳過詢問；不碰 conf、log 只追加）
#
# 行為:
#   每 POLL_SECONDS 讀一次 BMC SDR 中選定的溫度 sensor。
#   溫度 >= THRESHOLD 時累計高溫秒數；累計達 WINDOW_SECONDS 即斷 AC
#   （在 $AC_HELPER_DIR 內執行 021.ac_power_off.sh）。
#   斷電後不會自動回電，只能用 power-on 手動回電。
#   BMC 讀取失敗時不動作，累計時鐘暫停（中斷間隔不計入窗口）。
#   TRIPPED 期間每輪回看 relay 實際狀態；若發現斷電已被外部解除會警告。
#   run 啟動檢查（純讀取）：state 仍為 TRIPPED → 拒絕啟動並指路 clean；
#   relay OFF 但 state NORMAL → 大警告（AC 可能仍斷電中）但放行。
#   clean：顯示 status+relay；relay OFF 時問「要回電? [y/N]」（--yes 跳過），
#   選 y 才執行 022 回電、relay 讀回 ON 才重置 state；relay ON 且 TRIPPED →
#   log「外部已回電」；最後無條件重置 state 回 NORMAL 基準（ACCUM=0、TRIP_AT
#   清空；不碰 conf，log 追加不刪）。
#
# 檔案（與腳本同目錄）:
#   ac_temp_protect.conf   設定檔（setup 產生，含 BMC 密碼，權限 600）
#   ac_temp_protect.state  執行狀態（TRIPPED 等，重跑後仍保留）
#   ac_temp_protect.log    log（時間戳記為台北時間）
# ============================================================================

set -u
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="$SCRIPT_DIR/ac_temp_protect.conf"
STATE_FILE="$SCRIPT_DIR/ac_temp_protect.state"
LOG_FILE="$SCRIPT_DIR/ac_temp_protect.log"
RAW_FILE="$SCRIPT_DIR/.ac_temp_protect_raw"   # 最近一次 ipmitool 原始輸出（診斷用）

# AC 電源 helper（目錄可用環境變數 AC_HELPER_DIR 覆蓋；helper 需自行提供，見 README）
AC_HELPER_DIR="${AC_HELPER_DIR:-/ED/QT_Cycling_Multi-SVR-AC}"
AC_POWER_OFF_HELPER="021.ac_power_off.sh"
AC_POWER_ON_HELPER="022.ac_power_on.sh"
AC_STATE_HELPER="013.read.gpiod7_state.sh"

# IPMI over LAN 介面（多數 BMC 需 lanplus；若連不上可設 IPMI_INTERFACE=lan 重試）
IPMI_INTERFACE="${IPMI_INTERFACE:-lanplus}"

IPMITOOL="${IPMITOOL:-ipmitool}"   # 可用環境變數指到別的路徑（測試用）

STATE="NORMAL"
ACCUM=0
LAST_GOOD_EPOCH=0
TRIP_AT=""
LAST_TEMP=""
LAST_TEMP_AT=""
CONSEC_FAILS=0
DRY_RUN=0

log() {
    local ts
    ts="$(TZ='Asia/Taipei' date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] $*" | tee -a "$LOG_FILE"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
用法:
  ./ac_temp_protect.sh setup           跑一次：問 BMC IP、列出溫度 sensor 供選擇
  ./ac_temp_protect.sh run             開始監控（前台執行，Ctrl+C 停止）
  ./ac_temp_protect.sh run --dry-run   試跑：只記錄 log，不會真正斷電
  ./ac_temp_protect.sh status          查看目前狀態
  ./ac_temp_protect.sh power-on        手動回電（斷電後唯一回電途徑）
  ./ac_temp_protect.sh clean           重置狀態回 NORMAL 基準（relay OFF 時問是否回電，
                                       --yes 跳過詢問；不碰 conf、log 只追加）
EOF
    exit 1
}

load_conf() {
    [ -f "$CONF_FILE" ] || die "找不到設定檔 ($CONF_FILE)，請先執行 setup"
    # shellcheck disable=SC1090
    . "$CONF_FILE"
    [ -n "${BMC_IP:-}" ] || die "BMC_IP 為空，請重新執行 setup"
    [ -n "${SENSOR_NAME:-}" ] || die "SENSOR_NAME 為空，請重新執行 setup"
    [ -n "${THRESHOLD:-}" ] || die "THRESHOLD 未設定"
    [ -n "${WINDOW_SECONDS:-}" ] || die "WINDOW_SECONDS 未設定"
    [ -n "${POLL_SECONDS:-}" ] || die "POLL_SECONDS 未設定"
}

save_state() {
    {
        echo "STATE=\"$STATE\""
        echo "ACCUM=\"$ACCUM\""
        echo "LAST_GOOD_EPOCH=\"$LAST_GOOD_EPOCH\""
        echo "TRIP_AT=\"$TRIP_AT\""
        echo "LAST_TEMP=\"$LAST_TEMP\""
        echo "LAST_TEMP_AT=\"$LAST_TEMP_AT\""
        echo "CONSEC_FAILS=\"$CONSEC_FAILS\""
    } > "$STATE_FILE"
}

load_state() {
    STATE="NORMAL"
    ACCUM=0
    LAST_GOOD_EPOCH=0
    TRIP_AT=""
    LAST_TEMP=""
    LAST_TEMP_AT=""
    CONSEC_FAILS=0
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$STATE_FILE"
    fi
    case "$STATE" in NORMAL|TRIPPED) ;; *) STATE="NORMAL" ;; esac
    case "$ACCUM" in ''|*[!0-9]*) ACCUM=0 ;; esac
    case "$LAST_GOOD_EPOCH" in ''|*[!0-9]*) LAST_GOOD_EPOCH=0 ;; esac
    case "$CONSEC_FAILS" in ''|*[!0-9]*) CONSEC_FAILS=0 ;; esac
}

# 從 BMC 讀取選定的 sensor 溫度
# 成功：輸出數字（回傳 0）；失敗：回傳 1，且 $RAW_FILE 存下原始輸出供診斷
read_temp() {
    local out val
    # 注意：不用 `sdr list "名稱"` 過濾——舊版 ipmitool（如 RHEL7 的 1.8.18）不支援名稱參數，
    # 會回 "Invalid SDR list command"；改為拉完整清單後由下方 awk 端做字串匹配
    "$IPMITOOL" -I "$IPMI_INTERFACE" -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" \
        sdr list >"$RAW_FILE" 2>&1 || true
    out="$(cat "$RAW_FILE" 2>/dev/null)"
    # 純字串比較第 1 欄（sensor 名稱）——不依賴空格數、不需 regex escape
    val="$(printf '%s\n' "$out" \
        | awk -v n="$SENSOR_NAME" '
            $1 == n { for (i = 1; i <= NF; i++) if ($i == "degrees") { print $(i - 1); exit } }')"
    [ -n "$val" ] || return 1
    [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
    printf '%s\n' "$val"
}

# ---- AC 電源 helper（固定）-----------------------------------------------------
# helper 呼叫相對路徑的 lxRW_x64，必須在 AC_HELPER_DIR 內執行
ac_helper_run() {
    (cd "$AC_HELPER_DIR" 2>/dev/null && "./$1") 2>&1
}

# 讀 AC relay 狀態（原樣輸出，僅供 log/status 參考，不做解讀）
get_relay_state() {
    [ -f "$AC_HELPER_DIR/$AC_STATE_HELPER" ] || { echo "(helper 不存在)"; return 0; }
    local out
    if out="$(ac_helper_run "$AC_STATE_HELPER")" && [ -n "$out" ]; then
        printf '%s' "$out"
    else
        echo "(讀取失敗)"
    fi
}

do_trip() {
    local now
    now="$(TZ='Asia/Taipei' date '+%Y-%m-%d %H:%M:%S')"
    log "TRIP: [$SENSOR_NAME] 已持續 >= ${THRESHOLD}C 達 ${ACCUM}s（窗口 ${WINDOW_SECONDS}s）— 切斷 AC"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: 未實際斷電"
    else
        if ac_helper_run "$AC_POWER_OFF_HELPER"; then
            log "已執行 AC 斷電: $AC_HELPER_DIR/$AC_POWER_OFF_HELPER"
        else
            log "ERROR: AC 斷電指令執行失敗: $AC_HELPER_DIR/$AC_POWER_OFF_HELPER — 請立即手動檢查 AC 狀態！"
        fi
    fi
    STATE="TRIPPED"
    TRIP_AT="$now"
    ACCUM=0
    RELAY_LAST=""   # trip 後重新基準化 relay 回看
    save_state
    log "狀態為 TRIPPED，不會自動回電；確認後請手動回電: ./$(basename "$0") power-on"
}

cmd_run() {
    [ "${1:-}" = "--dry-run" ] && DRY_RUN=1
    load_conf
    load_state

    # 啟動檢查（純讀取，不碰 relay）：
    # 1) state 仍為 TRIPPED → 拒絕啟動，指路 clean
    # 2) relay OFF 但 state NORMAL → 大警告（AC 可能仍斷電中）但放行
    RS_START="$(get_relay_state)"
    if [ "$STATE" = "TRIPPED" ]; then
        die "狀態為 TRIPPED（$TRIP_AT 斷電）— 不能直接開始監控；請先執行 ./$(basename "$0") clean 確認回電並重置狀態"
    fi
    case "$RS_START" in
        *"AC Power OFF"*)
            log "!! 大警告: relay 顯示 AC Power OFF（斷電中）但狀態為 NORMAL — DUT 的 AC 供電可能仍被切斷，請立即確認！監控依要求繼續"
            ;;
    esac

    if [ ! -x "$AC_HELPER_DIR/$AC_POWER_OFF_HELPER" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "警告: 找不到 AC 斷電 helper: $AC_HELPER_DIR/$AC_POWER_OFF_HELPER（dry-run 不影響）"
        else
            die "找不到 AC 斷電 helper: $AC_HELPER_DIR/$AC_POWER_OFF_HELPER — 正式 run 拒絕啟動"
        fi
    fi

    trap 'log "收到停止訊號，監控結束"; exit 0' INT TERM

    log "===== 開始監控 ====="
    log "BMC=$BMC_IP user=$BMC_USER sensor=[$SENSOR_NAME] 門檻=${THRESHOLD}C 窗口=${WINDOW_SECONDS}s 輪詢=${POLL_SECONDS}s dry_run=$DRY_RUN"
    log "relay 狀態: $RS_START"
    if [ "$STATE" = "TRIPPED" ]; then
        log "注意：目前為斷電狀態（$TRIP_AT 斷電），監控繼續但不會再執行斷電"
    fi

    local now temp elapsed rs raw
    RELAY_LAST=""
    while :; do
        now="$(date +%s)"
        # B: TRIPPED 期間每輪回看 relay 實際狀態，防止斷電被外部（如 harness）靜默解除
        if [ "$STATE" = "TRIPPED" ]; then
            rs="$(get_relay_state)"
            case "$rs" in
                *"AC Power ON"*)
                    if [ "$DRY_RUN" -eq 0 ] && [ "${RELAY_LAST:-}" != "ON" ]; then
                        log "!! 警告: TRIPPED 中但 relay 顯示 AC Power ON — 斷電已被解除（可能被 harness 或手動開回），保護已失效，請立即人工處理"
                    fi
                    RELAY_LAST="ON"
                    ;;
                *"AC Power OFF"*)
                    RELAY_LAST="OFF"
                    ;;
            esac
        fi
        if temp="$(read_temp)"; then
            if [ "$LAST_GOOD_EPOCH" -eq 0 ]; then
                elapsed=0
            elif [ "$CONSEC_FAILS" -gt 0 ]; then
                # A: 讀取恢復——中斷期間溫度未知，該間隔不計入窗口
                elapsed=0
            else
                elapsed=$(( now - LAST_GOOD_EPOCH ))
                [ "$elapsed" -gt "$POLL_SECONDS" ] && elapsed="$POLL_SECONDS"
                [ "$elapsed" -lt 0 ] && elapsed=0
            fi
            LAST_GOOD_EPOCH=$now
            LAST_TEMP="$temp"
            LAST_TEMP_AT="$(TZ='Asia/Taipei' date '+%Y-%m-%d %H:%M:%S')"
            if [ "$CONSEC_FAILS" -gt 0 ]; then
                log "BMC 讀取已恢復（之前連續失敗 $CONSEC_FAILS 次）— 中斷間隔不計入窗口"
            fi
            CONSEC_FAILS=0

            if [ "$STATE" = "NORMAL" ]; then
                if awk -v t="$temp" -v th="$THRESHOLD" 'BEGIN { exit (t >= th) ? 0 : 1 }'; then
                    ACCUM=$(( ACCUM + elapsed ))
                    log "溫度 ${temp}C >= ${THRESHOLD}C，高溫累計 ${ACCUM}s / 窗口 ${WINDOW_SECONDS}s"
                    if [ "$ACCUM" -ge "$WINDOW_SECONDS" ]; then
                        do_trip
                    fi
                else
                    if [ "$ACCUM" -gt 0 ]; then
                        log "溫度 ${temp}C 已低於 ${THRESHOLD}C，重置高溫累計（原 ${ACCUM}s）"
                    else
                        log "溫度 ${temp}C — 正常（門檻 ${THRESHOLD}C）"
                    fi
                    ACCUM=0
                fi
            else
                log "TRIPPED 狀態，目前溫度 ${temp}C（等待手動回電）"
            fi
        else
            CONSEC_FAILS=$(( CONSEC_FAILS + 1 ))
            if [ "$CONSEC_FAILS" -eq 1 ]; then
                raw="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$RAW_FILE" 2>/dev/null | head -c 400)"
                [ -n "$raw" ] && \
                    log "BMC 讀取失敗原始訊息: $raw" || \
                    log "BMC 讀取失敗（ipmitool 無任何輸出）"
            fi
            log "BMC 讀取失敗（連續 $CONSEC_FAILS 次）— 本輪不計入、不動作"
        fi
        save_state
        sleep "$POLL_SECONDS"
    done
}

cmd_status() {
    load_conf
    load_state
    echo "設定  : BMC=$BMC_IP sensor=[$SENSOR_NAME] 門檻=${THRESHOLD}C 窗口=${WINDOW_SECONDS}s 輪詢=${POLL_SECONDS}s"
    echo "狀態  : $STATE"
    [ -n "$TRIP_AT" ] && echo "斷電時間: $TRIP_AT"
    echo "高溫累計: ${ACCUM}s"
    echo "最後讀取: ${LAST_TEMP:-（無）}（於 ${LAST_TEMP_AT:-}）"
    echo "連續讀取失敗: $CONSEC_FAILS"
    echo "relay 狀態: $(get_relay_state)"
    echo "log     : $LOG_FILE"
}

cmd_power_on() {
    load_conf
    load_state
    [ -x "$AC_HELPER_DIR/$AC_POWER_ON_HELPER" ] || \
        die "找不到 AC 回電 helper: $AC_HELPER_DIR/$AC_POWER_ON_HELPER"
    if [ "$STATE" != "TRIPPED" ]; then
        log "注意：目前狀態為 $STATE（非 TRIPPED），仍執行回電指令"
    fi
    if ac_helper_run "$AC_POWER_ON_HELPER"; then
        log "已執行 AC 回電: $AC_HELPER_DIR/$AC_POWER_ON_HELPER"
        STATE="NORMAL"
        ACCUM=0
        TRIP_AT=""
        save_state
        log "狀態恢復為 NORMAL"
    else
        die "AC 回電指令執行失敗: $AC_HELPER_DIR/$AC_POWER_ON_HELPER"
    fi
}

cmd_clean() {
    local yes=0
    [ "${1:-}" = "--yes" ] && yes=1
    load_conf
    load_state

    echo "=== clean: 目前狀態（純讀取） ==="
    echo "設定  : BMC=$BMC_IP sensor=[$SENSOR_NAME] 門檻=${THRESHOLD}C 窗口=${WINDOW_SECONDS}s 輪詢=${POLL_SECONDS}s"
    echo "狀態  : $STATE"
    [ -n "$TRIP_AT" ] && echo "斷電時間: $TRIP_AT"
    echo "高溫累計: ${ACCUM}s"
    local rs
    rs="$(get_relay_state)"
    echo "relay 狀態: $rs"
    echo

    case "$rs" in
        *"AC Power OFF"*)
            local ans="n"
            if [ "$yes" -eq 1 ]; then
                ans="y"
                log "clean --yes: 跳過詢問，將執行回電"
            elif [ -t 0 ]; then
                read -rp "relay 為 OFF（斷電中）— 要回電? [y/N] " ans
                case "$ans" in
                    y|Y|yes|YES) ans="y" ;;
                    *) ans="n" ;;
                esac
            else
                echo "（非互動環境：預設不回電；要自動回電請加 --yes）"
            fi
            if [ "$ans" = "y" ]; then
                [ -x "$AC_HELPER_DIR/$AC_POWER_ON_HELPER" ] || \
                    die "無法回電: 找不到 AC 回電 helper: $AC_HELPER_DIR/$AC_POWER_ON_HELPER"
                if ac_helper_run "$AC_POWER_ON_HELPER"; then
                    log "clean: 已執行 AC 回電: $AC_HELPER_DIR/$AC_POWER_ON_HELPER"
                else
                    die "clean: AC 回電指令執行失敗 — 狀態未重置，請檢查 relay 後重試"
                fi
                local rs2
                rs2="$(get_relay_state)"
                echo "relay 狀態（回電後）: $rs2"
                case "$rs2" in
                    *"AC Power ON"*) ;;
                    *) die "clean: 回電指令已執行但 relay 未顯示 AC Power ON — 狀態未重置，請立即人工檢查" ;;
                esac
            else
                log "clean: relay 為 OFF，選擇不回電（AC 保持斷電）"
            fi
            ;;
        *"AC Power ON"*)
            if [ "$STATE" = "TRIPPED" ]; then
                log "clean: 狀態為 TRIPPED 但 relay 已顯示 ON — 外部已回電"
            fi
            ;;
        *)
            log "clean: relay 狀態讀回異常（$rs）— 依要求繼續重置"
            ;;
    esac

    # 無條件重置 state 回 NORMAL 基準（不碰 conf；log 只追加不刪）
    STATE="NORMAL"
    ACCUM=0
    TRIP_AT=""
    save_state
    log "clean: 狀態已重置為 NORMAL 基準（ACCUM=0、TRIP_AT 清空；conf 未更動、log 保留）"
    echo "完成：state 已重置為 NORMAL 基準。"
}

cmd_setup() {
    echo "=== AC 溫度保護 setup ==="
    echo "設定將寫入: $CONF_FILE"
    # 純資訊：清除前顯示上一輪 state / relay（只讀，不動作）
    load_state
    echo "--- 上一輪狀態（即將清除，僅供參考） ---"
    echo "上一輪 STATE  : $STATE"
    echo "上一輪 TRIP_AT: ${TRIP_AT:-（無）}"
    echo "relay 狀態    : $(get_relay_state)"
    echo
    # 清除之前的 log 及暫存檔（state / raw），每次 setup 從乾淨狀態開始
    rm -f "$LOG_FILE" "$STATE_FILE" "$RAW_FILE"
    echo "已清除之前的 log 及暫存檔"
    echo

    local ip user pass out
    read -rp "BMC IP: " ip
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "BMC IP 格式不正確: $ip"

    read -rp "BMC 使用者 [admin]: " user
    [ -z "$user" ] && user="admin"

    read -rsp "BMC 密碼: " pass
    echo
    [ -n "$pass" ] || die "密碼不可為空"

    echo "正在測試 BMC SDR 讀取..."
    if ! out="$("$IPMITOOL" -I lanplus -H "$ip" -U "$user" -P "$pass" sdr list 2>&1)"; then
        echo "ERROR: 無法從 BMC ($ip) 讀取 sdr：" >&2
        printf '%s\n' "$out" >&2
        exit 1
    fi

    local sensors=() s
    while IFS= read -r s; do
        sensors+=("$s")
    done < <(printf '%s\n' "$out" \
        | awk -F'|' 'tolower($0) ~ /degrees c/ { gsub(/^[ \t]+|[ \t]+$/, "", $1); if ($1 != "") print $1 }' \
        | sort -u)
    [ "${#sensors[@]}" -gt 0 ] || die "SDR 中找不到溫度 sensor（含 degrees C 的項目）"

    echo
    echo "SDR 中的溫度 sensor:"
    local i
    for i in "${!sensors[@]}"; do
        printf '  %2d) %s\n' "$((i + 1))" "${sensors[i]}"
    done
    echo

    local n
    while true; do
        read -rp "請選擇要監控的 sensor 編號: " n
        [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#sensors[@]}" ] && break
        echo "輸入不正確，請輸入 1 到 ${#sensors[@]} 之間的數字"
    done
    local sensor="${sensors[n - 1]}"

    local th wmin ps wsec
    read -rp "門檻溫度 (C) [55]: " th
    [ -z "$th" ] && th=55
    [[ "$th" =~ ^[0-9]+$ ]] || die "門檻必須為整數"
    read -rp "觸發窗口 (分鐘) [1]: " wmin
    [ -z "$wmin" ] && wmin=1
    [[ "$wmin" =~ ^[0-9]+$ ]] || die "窗口必須為整數（分鐘）"
    wsec=$(( wmin * 60 ))
    read -rp "輪詢間隔 (秒) [30]: " ps
    [ -z "$ps" ] && ps=30
    [[ "$ps" =~ ^[0-9]+$ ]] || die "輪詢間隔必須為整數"

    echo
    echo "AC 電源 helpers（固定，不問）:"
    echo "  目錄: $AC_HELPER_DIR"
    [ -x "$AC_HELPER_DIR/$AC_POWER_OFF_HELPER" ] || \
        echo "  [警告] $AC_POWER_OFF_HELPER 不存在 — run 只能以 --dry-run 執行"
    [ -x "$AC_HELPER_DIR/$AC_POWER_ON_HELPER" ] || \
        echo "  [警告] $AC_POWER_ON_HELPER 不存在 — power-on 無法使用"

    {
        echo "BMC_IP=\"$ip\""
        echo "BMC_USER=\"$user\""
        echo "BMC_PASS=\"$pass\""
        echo "SENSOR_NAME=\"$sensor\""
        echo "THRESHOLD=$th"
        echo "WINDOW_SECONDS=$wsec"
        echo "POLL_SECONDS=$ps"
    } > "$CONF_FILE"
    chmod 600 "$CONF_FILE"

    echo
    echo "=== setup 完成 ==="
    echo "  BMC      : $ip ($user)"
    echo "  sensor   : $sensor"
    echo "  門檻/窗口: ${th}C / ${wmin} 分鐘，輪詢 ${ps} 秒"
    echo "  斷電 helper: $AC_HELPER_DIR/$AC_POWER_OFF_HELPER"
    echo "  回電 helper: $AC_HELPER_DIR/$AC_POWER_ON_HELPER"
    echo
    echo "建議：先跑  ./ac_temp_protect.sh run --dry-run  觀察一段時間，"
    echo "     確認無誤後再跑  ./ac_temp_protect.sh run  正式啟用。"
}

case "${1:-}" in
    setup)    cmd_setup ;;
    run)      cmd_run "${2:-}" ;;
    status)   cmd_status ;;
    power-on) cmd_power_on ;;
    clean)    cmd_clean "${2:-}" ;;
    *)        usage ;;
esac
