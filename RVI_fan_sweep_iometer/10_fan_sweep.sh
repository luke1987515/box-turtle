#!/bin/bash
# =============================================================================
# 10_fan_sweep.sh — RVI fan-sweep main loop
#
# Per PWM level: set fan (vendor raw cmd) -> verify readback -> settle ->
# run 4K Random Writes ICF -> run 256K Sequential Writes ICF.
# Idempotent: re-running resumes from the first missing level (valid CSVs
# are skipped), so power loss / aborts can simply re-launch this script.
# Provenance: designed & validated by Luke Chen; developed with AI assistance
# (Hermes Agent by Nous Research, self-hosted Qwen model family).
# =============================================================================
set -u

cd "$(dirname "$0")"
source ./20_iometer_run.sh    # loads rvi.conf + helpers
declare -a FAILURES=()

abort() {
    log CRITICAL "ABORT: $*"
    timeline "event=abort reason=$*"
    exit 1
}

# --- Preflight ------------------------------------------------------------------
bash ./00_preflight.sh || abort "preflight failed (see above)"

mkdir -p "$RESULT_DIR" "$REPORT_DIR"
DRIVE_SNAPSHOT="$LOG_DIR/drives_baseline.txt"
[ -f "$DRIVE_SNAPSHOT" ] || snapshot_drives > "$DRIVE_SNAPSHOT"
DMESG_OFFSET=$(dmesg 2>/dev/null | wc -l)
FAN_ORIG_F1=""
FAN_ORIG_F2=""
if [ -f "$LOG_DIR/fan_original.txt" ]; then
    FAN_ORIG_F1=$(sed -n 1p "$LOG_DIR/fan_original.txt")
    FAN_ORIG_F2=$(sed -n 2p "$LOG_DIR/fan_original.txt")
fi

timeline "event=sweep_start levels=$PWM_LEVELS"
log INFO "=== RVI fan sweep starting: levels [$PWM_LEVELS] ==="

# --- Main loop --------------------------------------------------------------------
for L in $PWM_LEVELS; do
    if [ "$L" -lt "$MIN_PWM_LEVEL" ]; then
        log INFO "level=$L skipped (below MIN_PWM_LEVEL=$MIN_PWM_LEVEL)"
        timeline "level=$L event=skip"
        continue
    fi

    set_and_verify_fan "$L" || abort "fan state unverified at level=$L — data would be invalid, sweep stopped"
    timeline "level=$L event=fan_ok"
    log INFO "settling fan for $FAN_SETTLE_S s ..."
    sleep "$FAN_SETTLE_S"

    run_level_test "4K"  "$L" || log WARN "level=$L test=4K incomplete (continuing)"
    run_level_test "SEQ" "$L" || log WARN "level=$L test=SEQ incomplete (continuing)"

    check_drives_again "$DRIVE_SNAPSHOT" || abort "drive list changed — preserving scene for failure analysis"
    dmesg_scan "$L"
done

# --- Wrap-up ------------------------------------------------------------------------
timeline "event=sweep_done"
[ -n "$FAN_ORIG_F1" ] && restore_fan "$FAN_ORIG_F1" "$FAN_ORIG_F2"

check_drives_again "$DRIVE_SNAPSHOT" || log WARN "drive list differs at end (already flagged above)"
dmesg_scan "end"

python3 ./30_report.py || log WARN "30_report.py failed (raw CSVs in $RESULT_DIR are intact)"

# --- Summary -------------------------------------------------------------------------
TOTAL_EXPECTED=0
for L in $PWM_LEVELS; do
    [ "$L" -lt "$MIN_PWM_LEVEL" ] && continue
    TOTAL_EXPECTED=$((TOTAL_EXPECTED + 2))
done
DONE_4K=$(ls "$RESULT_DIR"/$(printf "$CSV_4K_FMT" '*') 2>/dev/null | wc -l)
DONE_SEQ=$(ls "$RESULT_DIR"/$(printf "$CSV_SEQ_FMT" '*') 2>/dev/null | wc -l)

echo "============================================================"
echo " RVI FAN SWEEP SUMMARY"
echo "   levels expected: $(echo "$TOTAL_EXPECTED" | awk '{print $1/2}') x 2 tests = $TOTAL_EXPECTED runs"
echo "   4K CSVs present: $DONE_4K / $((TOTAL_EXPECTED / 2))"
echo "   SEQ CSVs present: $DONE_SEQ / $((TOTAL_EXPECTED / 2))"
if [ ${#FAILURES[@]} -gt 0 ]; then
    echo "   FAILED (re-run 10_fan_sweep.sh to retry only these):"
    for f in "${FAILURES[@]}"; do echo "     - level=$f"; done
else
    echo "   no failed runs this pass"
fi
echo "   raw CSVs : $RESULT_DIR (untouched)"
echo "   report   : $REPORT_DIR"
echo "   logs     : $LOG_DIR (run log, timeline, errors, iometer per-run logs)"
echo "============================================================"
log INFO "=== RVI fan sweep finished ==="
