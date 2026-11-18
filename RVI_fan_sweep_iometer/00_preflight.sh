#!/bin/bash
# =============================================================================
# 00_preflight.sh — pre-test self-check. Run before 10_fan_sweep.sh (it also
# runs this automatically). Any FAIL aborts; WARN is logged but continues.
# Provenance: designed & validated by Luke Chen; developed with AI assistance
# (Hermes Agent by Nous Research, self-hosted Qwen model family).
# =============================================================================
set -u

cd "$(dirname "$0")"
source ./20_iometer_run.sh   # loads rvi.conf + helpers (idempotent)
mkdir -p "$RESULT_DIR" "$REPORT_DIR" "$LOG_DIR"

FAILS=0
WARNS=0

pass() { log INFO  "PASS: $*"; }
warn() { log WARN  "WARN: $*"; WARNS=$((WARNS + 1)); }
fail() { log ERROR "FAIL: $*"; FAILS=$((FAILS + 1)); }

# --- 1. OS / kernel (target: Ubuntu 24.04.1, kernel 6.8.0-149) ----------------
OS_LINE=$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")
KERN=$(uname -r)
if [[ "$OS_LINE" == *"24.04"* && "$KERN" == 6.8.0-149* ]]; then
    pass "OS: $OS_LINE kernel $KERN"
else
    warn "OS: $OS_LINE kernel $KERN (target 24.04.1 / 6.8.0-149)"
fi

# --- 2. Wine + prefix ------------------------------------------------------------
if command -v Xvfb >/dev/null 2>&1; then
    pass "Xvfb present"
else
    fail "Xvfb not found (apt install xvfb)"
fi
if command -v "$WINE_BIN" >/dev/null 2>&1; then
    pass "wine present: $("$WINE_BIN" --version 2>/dev/null | head -1)"
    if ! ensure_wine_prefix; then
        fail "wine prefix init failed (see $LOG_DIR/wineboot.log)"
    else
        pass "wine prefix $WINEPREFIX ready"
    fi
    if [ -z "$(wine_w "$RESULT_DIR" 2>/dev/null)" ]; then
        fail "winepath translation broken"
    else
        pass "winepath works"
    fi
else
    fail "wine not found (apt install wine64)"
fi

# --- 3. iometer.exe + ICFs --------------------------------------------------------
if [ -f "$IOMETER_EXE" ]; then pass "iometer.exe: $IOMETER_EXE"; else fail "iometer.exe missing: $IOMETER_EXE"; fi
for f in "$ICF_4K" "$ICF_SEQ" "$ICF_SMOKE" "$ICF_SMOKE24"; do
    if [ -f "$f" ]; then pass "ICF: $f"; else fail "ICF missing: $f"; fi
done

# --- 4. dynamo --------------------------------------------------------------------
if [ -x "$DYNAMO_BIN" ] || [ -f "$DYNAMO_BIN" ]; then
    pass "dynamo binary: $DYNAMO_BIN"
    if ensure_dynamo; then pass "dynamo running"; else fail "dynamo not running"; fi
else
    fail "dynamo binary missing: $DYNAMO_BIN"
fi

# --- 5. Drives present ---------------------------------------------------------------
DRIVE_SNAPSHOT="$LOG_DIR/drives_baseline.txt"
DRIVES=$(snapshot_drives)
echo "$DRIVES" > "$DRIVE_SNAPSHOT"
DRIVE_COUNT=$(echo "$DRIVES" | grep -c . || true)
if [ "$DRIVE_COUNT" -eq 0 ]; then
    fail "no test disks detected by lsblk"
elif [ "$DRIVE_COUNT" -ne "$EXPECTED_DRIVES" ]; then
    MISSING=$(comm -23 <(echo "$TEST_DISKS" | tr ' ' '\n' | sort) <(echo "$DRIVES" | sort) | tr '\n' ' ')
    fail "drive count $DRIVE_COUNT != EXPECTED_DRIVES $EXPECTED_DRIVES — missing: [$MISSING]"
else
    pass "drives present: $DRIVE_COUNT [$TEST_DISKS]"
fi

# --- 6. Drive write-cache off (spec step 3) -----------------------------------------
# hdparm -W does NOT work on these SAS drives behind the mpt3sas HBA
# (ATA IDENTIFY is rejected — verified on DUT 2026-11-17). sdparm (SCSI
# pass-through) reads/sets WCE correctly.
if [ "$DRIVE_COUNT" -gt 0 ]; then
    command -v sdparm >/dev/null 2>&1 || apt-get install -y sdparm >/dev/null 2>&1
    if ! command -v sdparm >/dev/null 2>&1; then
        warn "sdparm unavailable (offline?) — write-cache state not verifiable"
    else
        while IFS= read -r d; do
            [ -z "$d" ] && continue
            wce=$(sdparm --get=WCE "/dev/$d" 2>/dev/null | awk '/^WCE/ {print $2}')
            case "$wce" in
                0) pass "cache off: /dev/$d (WCE=0)" ;;
                1)
                    warn "cache ON: /dev/$d — setting WCE=0"
                    if sdparm --set=WCE=0 "/dev/$d" >/dev/null 2>&1; then
                        wce2=$(sdparm --get=WCE "/dev/$d" 2>/dev/null | awk '/^WCE/ {print $2}')
                        [ "$wce2" = "0" ] && pass "cache off (fixed): /dev/$d" \
                            || fail "WCE set failed on /dev/$d (still WCE=$wce2)"
                    else
                        fail "cannot disable write-cache: /dev/$d"
                    fi
                    ;;
                *) warn "WCE unreadable on /dev/$d (got '$wce') — verify manually" ;;
            esac
        done <<< "$DRIVES"
    fi
fi

# --- 7. Fan readback format (0xFB) -----------------------------------------------------
FAN_ORIG=$(read_fan_state)
FAN_ORIG_COUNT=$(printf '%s\n' "$FAN_ORIG" | grep -c . || true)
if [ "$FAN_ORIG_COUNT" -eq 2 ] && [ -n "$FAN_ORIG" ]; then
    pass "fan readback: 2 levels [$(echo "$FAN_ORIG" | tr '\n' ' ')]"
    # Save original state (fan1 fan2, two hex bytes) for restore after sweep
    printf '%s\n' "$FAN_ORIG" > "$LOG_DIR/fan_original.txt"
else
    fail "fan readback: got $FAN_ORIG_COUNT levels, expected 2 — check FAN_PWM_IDX_* vs this BMC (0xFB = 34 bytes)"
fi

# --- 8. Time source -----------------------------------------------------------------
if timedatectl 2>/dev/null | grep -qiE 'System clock synchronized: yes'; then
    pass "clock synchronized"
else
    warn "clock sync state unknown (timeline timestamps may drift)"
fi

# --- 9. Disk space -------------------------------------------------------------------
AVAIL_MB=$(df -BM "$RESULT_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'M')
if [ -n "${AVAIL_MB:-}" ] && [ "$AVAIL_MB" -ge 500 ]; then
    pass "free space ${AVAIL_MB}MB"
else
    fail "insufficient free space in $RESULT_DIR (${AVAIL_MB:-?}MB < 500MB)"
fi

# --- 10. IOMeter batch-mode smoke test (THE critical check) ----------------------------
# Uses the real production path: full 24-disk ICF through run_iometer_batch
# (wine64 + EULA seed + dynamo keeper), then validate_csv (24 DISK rows).
# Verified end-to-end on the DUT: 24/24 DISK rows, 0 errors, ~81s wall clock.
if [ "$FAILS" -eq 0 ]; then
    ensure_xvfb
    ensure_eula
    SMOKE_CSV="$RESULT_DIR/smoke_$(date +%Y%m%d_%H%M).csv"
    rm -f "$SMOKE_CSV"
    log INFO "smoke test: batch mode, 24-disk ICF ($ICF_SMOKE24)"
    ensure_dynamo || { fail "dynamo down before smoke test"; }
    if run_iometer_batch "$ICF_SMOKE24" "$SMOKE_CSV"; then
        SMOKE_RC=0
    else
        SMOKE_RC=$?
    fi
    stop_dynamo
    if [ "$SMOKE_RC" -eq 0 ] && validate_csv "$SMOKE_CSV"; then
        pass "batch mode smoke: rc=0, $(grep -c '^DISK,' "$SMOKE_CSV") DISK rows in $SMOKE_CSV"
        log INFO "smoke CSV kept for 30_report.py parser calibration: $SMOKE_CSV"
    elif [ "$SMOKE_RC" -eq 124 ]; then
        fail "smoke: iometer did not exit by itself (hung in waiting dialog?) — see $LOG_DIR/iometer_$(basename "$SMOKE_CSV").log"
    else
        fail "smoke: rc=$SMOKE_RC or CSV invalid — see $LOG_DIR/iometer_$(basename "$SMOKE_CSV").log"
    fi
else
    warn "skipping smoke test (earlier FAILs)"
fi

# --- Summary -------------------------------------------------------------------------
echo "============================================================"
if [ "$FAILS" -eq 0 ]; then
    log INFO "PREFLIGHT: PASS ($WARNS warnings)"
    exit 0
else
    log ERROR "PREFLIGHT: FAIL ($FAILS failures, $WARNS warnings) — do NOT start the sweep"
    exit 1
fi
