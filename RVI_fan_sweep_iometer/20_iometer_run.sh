# =============================================================================
# 20_iometer_run.sh — shared helpers + IOMeter batch-mode runner
# Sourced by 00_preflight.sh and 10_fan_sweep.sh (do NOT execute directly).
#
# Batch mode (verified in IOMeter 1.1.0 source, GalileoApp.cpp / Galileo.rc):
#   iometer.exe /c <config.icf> /r <results.csv> /t <login_timeout>
# loads the ICF, starts the test, stops it (run time from Test Setup tab),
# writes the results CSV and exits — no GUI interaction required.
# The MFC app still needs an X display under Wine -> Xvfb (headless).
# Provenance: designed & validated by Luke Chen; developed with AI assistance
# (Hermes Agent by Nous Research, self-hosted Qwen model family).
# =============================================================================

if [ -z "${_RVI_LOADED:-}" ]; then
    _RVI_LOADED=1
    [ -f "${BASH_SOURCE[0]%/*}/rvi.conf" ] && source "${BASH_SOURCE[0]%/*}/rvi.conf"
    mkdir -p "$LOG_DIR"
fi

# --- Logging ------------------------------------------------------------------
iso_now() { date '+%Y-%m-%dT%H:%M:%S%:z'; }
RUN_LOG="$LOG_DIR/run_$(date +%Y%m%d_%H%M).log"

log() {
    local lvl=$1; shift
    local line
    line="[$(iso_now)] [$lvl] $*"
    echo "$line" | tee -a "$RUN_LOG"
}

timeline() {
    # level=<L> test=<TYPE> event=<E>
    echo "$(iso_now) epoch=$(date +%s) $*" >> "$LOG_DIR/fan_timeline.log"
}

# --- Environment: Xvfb + Wine + dynamo ----------------------------------------
# NOTE (verified 2026-11-17): on this DUT the `wine` symlink fails with
# "could not exec the wine loader"; always invoke `wine64` directly.
WINE_BIN="wine64"

ensure_xvfb() {
    if ! pgrep -f "Xvfb $XVFB_DISPLAY" >/dev/null 2>&1; then
        log INFO "starting Xvfb $XVFB_DISPLAY"
        nohup Xvfb "$XVFB_DISPLAY" -screen 0 1024x768x24 -nolisten tcp \
            >>"$LOG_DIR/xvfb.log" 2>&1 &
        sleep 2
    fi
    export DISPLAY="$XVFB_DISPLAY"
}

ensure_eula() {
    # IOMeter 1.1.0 (GalileoApp.cpp InitInstance) shows the EULA dialog on
    # startup unless HKCU\Software\iometer.org\Iometer\Settings\Version ==
    # IOVER_FILEVERSION ("1.1.0"). MFC LoadStdProfileSettings nests the key
    # under the app name "Iometer" — seeding the UN-nested path
    # (iometer.org\Settings) does NOT suppress the dialog (verified: dialog
    # re-appeared). The dialog is modal and blocks batch mode forever, so the
    # registry value must exist before the first launch. Idempotent.
    local rc
    "$WINE_BIN" reg add 'HKCU\Software\iometer.org\Iometer\Settings' \
        /v Version /t REG_SZ /d '1.1.0' /f \
        >/dev/null 2>>"$LOG_DIR/wine_reg.log"
    rc=$?
    [ $rc -ne 0 ] && log WARN "EULA registry seed rc=$rc (prefix may be broken)"
    return 0
}

wine_w() {
    # Translate a unix path to a Windows path for the wine prefix.
    # Prefer winepath; fall back to manual Z:\ mapping (wine64-only installs
    # do not ship winepath).
    local w
    w=$(WINEPREFIX="$WINEPREFIX" winepath -w "$1" 2>/dev/null)
    if [ -n "$w" ]; then
        echo "$w"
    else
        printf 'Z:\\%s' "${1#/}" | tr '/' '\\'
    fi
}

ensure_wine_prefix() {
    ensure_xvfb
    if [ ! -d "$WINEPREFIX" ]; then
        # No wineboot in wine64-only installs; the loader auto-initializes
        # the prefix on first app launch (first run takes ~30-60s).
        log INFO "wine prefix $WINEPREFIX not yet created — will auto-initialize on first run"
        mkdir -p "$WINEPREFIX"
    fi
}

_start_dynamo() {
    log INFO "starting dynamo agent"
    # dynamo links libaio.so.1, which lives in /opt/iometer (not on the
    # standard loader path) — LD_LIBRARY_PATH is mandatory (verified).
    # -n must match the manager name in the ICF (rvi-dut).
    nohup env LD_LIBRARY_PATH="$(dirname "$DYNAMO_BIN")" \
        "$DYNAMO_BIN" -n "$MANAGER_NAME" -i "$DYNAMO_SELF_IP" -m "$DYNAMO_MANAGER_IP" \
        >>"$LOG_DIR/dynamo.log" 2>&1 &
    sleep 2
    pgrep -x dynamo >/dev/null || { log CRITICAL "dynamo failed to start (see $LOG_DIR/dynamo.log)"; return 1; }
    return 0
}

ensure_dynamo() {
    # Fresh dynamo per IOMeter run: a leftover dynamo from a previous run
    # either exits when its manager (the dead iometer) closes the socket, or
    # sits holding state; a clean start avoids both. dynamo exits on its own
    # when the manager stops it ("Ending execution."), and it does NOT retry
    # a failed login — the keeper below restarts it every 5s until the run
    # finishes, which also absorbs the ~15-30s gap between dynamo start and
    # iometer's login port opening.
    pkill -x dynamo 2>/dev/null
    sleep 1
    if ! _start_dynamo; then
        return 1
    fi
    local loops
    loops=$(( (RUN_WATCHDOG_S + 60) / 5 ))
    (
        for i in $(seq 1 "$loops"); do
            pgrep -x dynamo >/dev/null 2>&1 || _start_dynamo
            sleep 5
        done
    ) &
    DYNAMO_KEEPER_PID=$!
    return 0
}

stop_dynamo() {
    [ -n "${DYNAMO_KEEPER_PID:-}" ] && kill "$DYNAMO_KEEPER_PID" 2>/dev/null
    DYNAMO_KEEPER_PID=""
    pkill -x dynamo 2>/dev/null
}

# --- Fan control (ZELUS BMC) ---------------------------------------------------
# read_fan_state: print the two fan-level bytes from 0xFB (one per line,
# uppercase, bare hex — ipmitool raw prints bare hex). 0-based indices in
# the 34-byte response: FAN_PWM_IDX_1 (system, exact), FAN_PWM_IDX_2 (PSU,
# +-1 drift). Prints nothing on failure.
read_fan_state() {
    local flat
    flat=$(eval "$FAN_READ_CMD" 2>/dev/null | tr -d ' \n')
    [ -n "$flat" ] || return 1
    [ ${#flat} -ge $((FAN_PWM_IDX_2 * 2 + 2)) ] || return 1
    printf '%s\n' "${flat:$((FAN_PWM_IDX_1 * 2)):2}"
    printf '%s\n' "${flat:$((FAN_PWM_IDX_2 * 2)):2}"
}

set_fan_all() {
    # $1 = PWM level (0-100). Sends FAN_BYTE_COUNT values (value[0] drives
    # both physical fans; the rest are padding, see rvi.conf protocol note).
    local L=$1
    local hex i
    local -a cmd
    hex=$(printf '0x%02X' "$L")
    read -r -a cmd <<< "$FAN_SET_PREFIX"
    for ((i = 0; i < FAN_BYTE_COUNT; i++)); do cmd+=("$hex"); done
    "${cmd[@]}" >/dev/null 2>&1
}

set_and_verify_fan() {
    # $1 = PWM level (0-100). Returns 0 on verified, 1 on failure.
    local L=$1
    local hex hex_bare rc attempt ok g1 g2
    hex=$(printf '0x%02X' "$L")
    hex_bare=$(printf '%02X' "$L")
    for ((attempt = 1; attempt <= FAN_VERIFY_RETRIES; attempt++)); do
        log INFO "fan set level=$L attempt=$attempt ($FAN_BYTE_COUNT x $hex)"
        set_fan_all "$L"; rc=$?
        if [ $rc -ne 0 ]; then
            log WARN "fan set rc=$rc (attempt $attempt)"
            sleep 2
            continue
        fi
        sleep 1
        mapfile -t got < <(read_fan_state)
        if [ "${#got[@]}" -ne 2 ]; then
            log WARN "fan readback parse failed: got ${#got[@]} bytes, expected 2 (attempt $attempt)"
            sleep 2
            continue
        fi
        g1="${got[0]^^}"
        g2="${got[1]^^}"
        # fan 1 must match exactly; fan 2 may drift +-FAN_VERIFY_TOLERANCE
        local d
        d=$(( (0x${g2}) - (0x${hex_bare}) ))
        [ $d -lt 0 ] && d=$(( -d ))
        ok=1
        [ "$g1" = "$hex_bare" ] || ok=0
        [ $d -le "$FAN_VERIFY_TOLERANCE" ] || ok=0
        if [ $ok -eq 1 ]; then
            log INFO "fan verified level=$L (readback fan1=$g1 fan2=$g2)"
            return 0
        fi
        log WARN "fan readback mismatch: expected $hex, got fan1=$g1 fan2=$g2 (attempt $attempt)"
        sleep 2
    done
    log CRITICAL "fan set/verify FAILED for level=$L after $FAN_VERIFY_RETRIES attempts"
    return 1
}

restore_fan() {
    # $1 = fan1 hex  $2 = fan2 hex (original readback, two bytes).
    # value[0] drives both physical fans; use fan1's original level.
    # If the two originals differ, both are still applied where possible.
    local f1=$1 f2=$2
    log INFO "restoring fan state: fan1=$f1 fan2=$f2"
    if set_fan_all "$((16#$f1))"; then
        sleep 1
        if read_fan_state | tr -d '\n' | grep -qiE "^${f1}${f2}$"; then
            log INFO "fan state restored (verified)"
        else
            log WARN "fan restore sent but readback differs from original [$f1 $f2] — verify manually"
        fi
    else
        log WARN "fan restore FAILED (manual check required)"
    fi
}

# --- Drives --------------------------------------------------------------------
snapshot_drives() {
    # Present TEST_DISKS (bare names, sorted). Other disks on the DUT
    # (nvme0n1 = OS boot, sda = 0B BMC virtual) are deliberately excluded.
    local present d
    present=$(lsblk -dnpo NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}' \
        | sed 's|^/dev/||' | sort)
    for d in $TEST_DISKS; do
        printf '%s\n' "$present" | grep -qx "$d" && printf '%s\n' "$d"
    done | sort
}

check_drives_again() {
    # $1 = expected snapshot file
    local now expected
    now=$(snapshot_drives)
    expected=$(cat "$1")
    if [ "$now" != "$expected" ]; then
        log CRITICAL "drive list CHANGED during test!"
        log CRITICAL "expected: [$(echo "$expected" | tr '\n' ' ')]"
        log CRITICAL "actual:   [$(echo "$now" | tr '\n' ' ')]"
        return 1
    fi
    return 0
}

dmesg_scan() {
    # $1 = current level label; append new error lines to errors.log, update offset
    local cur new
    cur=$(dmesg 2>/dev/null | wc -l)
    new=$(dmesg 2>/dev/null | tail -n +"$((DMESG_OFFSET + 1))" \
        | grep -iE 'I/O error|task abort|medium error|sense key|hard resetting|soft resetting' )
    if [ -n "$new" ]; then
        { echo "=== $(iso_now) level=$1 ==="; echo "$new"; echo; } >> "$LOG_DIR/errors.log"
        log WARN "dmesg error events at level=$1 (appended to errors.log)"
    fi
    DMESG_OFFSET=$cur
}

# --- IOMeter batch run -----------------------------------------------------------
validate_csv() {
    # $1 = csv path; 0 = valid batch results.
    # Batch CSV layout (verified 2026-11-17, 24-disk run): ~10 metadata lines,
    # ALL, MANAGER, one PROCESSOR per CPU, then one WORKER row + one DISK row
    # per worker, then 'End Test. Total rows for 24 disks: ~130 — so row-count
    # floors are useless; validate the DISK rows instead.
    local f=$1
    [ -s "$f" ] || return 1
    grep -q "^'End Test" "$f" 2>/dev/null || return 1
    local disk_rows
    disk_rows=$(grep -c '^DISK,' "$f" 2>/dev/null)
    if [ "$disk_rows" -lt "$EXPECTED_DRIVES" ]; then
        log WARN "csv $f has only $disk_rows DISK rows (< EXPECTED_DRIVES=$EXPECTED_DRIVES)"
        return 1
    fi
    return 0
}

run_iometer_batch() {
    # $1 = icf (unix path)  $2 = results csv (unix path)
    local icf=$1 csv=$2 wicf wcsv rc
    wicf=$(wine_w "$icf")
    wcsv=$(wine_w "$csv")
    if [ -z "$wicf" ] || [ -z "$wcsv" ]; then
        log CRITICAL "winepath translation failed for ICF/CSV"
        return 2
    fi
    log INFO "iometer batch: /c $wicf /r $wcsv /t $IOMETER_LOGIN_TIMEOUT"
    timeout "$RUN_WATCHDOG_S" env WINEPREFIX="$WINEPREFIX" DISPLAY="$XVFB_DISPLAY" \
        "$WINE_BIN" "$IOMETER_EXE" /c "$wicf" /r "$wcsv" /t "$IOMETER_LOGIN_TIMEOUT" \
        >>"$LOG_DIR/iometer_$(basename "$csv").log" 2>&1
    rc=$?
    if [ $rc -eq 124 ]; then
        log WARN "iometer run hit watchdog timeout ($RUN_WATCHDOG_S s)"
    fi
    return $rc
}

run_level_test() {
    # $1 = TYPE (4K|SEQ)  $2 = level. Idempotent: skips when a valid CSV exists.
    # On total failure: records FAILURES and returns 1 (caller continues).
    local TYPE=$1 L=$2
    local icf fmt csv attempt rc
    if [ "$TYPE" = "4K" ]; then fmt="$CSV_4K_FMT"; icf="$ICF_4K"; else fmt="$CSV_SEQ_FMT"; icf="$ICF_SEQ"; fi
    csv="$RESULT_DIR/$(printf "$fmt" "$L")"

    if validate_csv "$csv" 2>/dev/null; then
        log INFO "level=$L test=$TYPE already done, skipping ($csv)"
        return 0
    fi

    for ((attempt = 1; attempt <= MAX_RETRY_PER_LEVEL + 1; attempt++)); do
        timeline "level=$L test=$TYPE event=run_start attempt=$attempt"
        ensure_xvfb
        ensure_eula
        if ! ensure_dynamo; then
            log WARN "dynamo down before attempt $attempt — retry after 10s"
            sleep 10
            continue
        fi
        rc=0
        run_iometer_batch "$icf" "$csv" || rc=$?
        stop_dynamo
        if [ $rc -eq 0 ] && validate_csv "$csv"; then
            log INFO "level=$L test=$TYPE OK (DISK rows=$(grep -c '^DISK,' "$csv")) attempt=$attempt"
            timeline "level=$L test=$TYPE event=run_ok"
            return 0
        fi
        log WARN "level=$L test=$TYPE attempt=$attempt FAILED (rc=$rc)"
        tail -n 20 "$LOG_DIR/iometer_$(basename "$csv").log" 2>/dev/null | tee -a "$RUN_LOG"
        rm -f "$csv"
        sleep 5
    done
    log CRITICAL "level=$L test=$TYPE FAILED after $((MAX_RETRY_PER_LEVEL + 1)) attempts — continuing, will list in summary"
    timeline "level=$L test=$TYPE event=run_failed"
    FAILURES+=("$L/$TYPE")
    return 1
}
