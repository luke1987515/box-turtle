#!/usr/bin/env bash
# Functional test for fan logic in 20_iometer_run.sh using a mock ipmitool.
# Mock: state file of 13 bare-hex bytes.
#   raw 0x36 0xFA 0x00 <13 bytes>  -> apply (unless RVI_MOCK_STUCK=1)
#   raw 0x36 0xFB                  -> print state
set -u
T="$(cygpath -w "$1")"
T_FWD="${T//\\//}"
rm -rf "$T"
mkdir -p "$T/bin" "$T/results" "$T/logs"

sed -e "s|^BASE_DIR=.*|BASE_DIR=\"$T_FWD\"|" "${RVI_SRC_DIR:?set RVI_SRC_DIR to this repo dir}/rvi.conf" > "$T/rvi.conf"
cp "${RVI_SRC_DIR:?set RVI_SRC_DIR to this repo dir}/20_iometer_run.sh" "$T/"

cat > "$T/bin/ipmitool" <<'EOF'
#!/bin/bash
STATE="$RVI_TEST_STATE"
case "${2:-} ${3:-}" in
  "0x36 0xFA")
    if [ -n "${RVI_MOCK_STUCK:-}" ]; then exit 0; fi   # BMC ignores the set
    shift 4                                            # drop: raw 0x36 0xFA 0x00
    { for a in "$@"; do printf '%s ' "${a#0x}"; done; echo; } > "$STATE"
    exit 0 ;;
  "0x36 0xFB")
    cat "$STATE" 2>/dev/null; exit 0 ;;
esac
echo "mock ipmitool: unknown command $*" >&2
exit 1
EOF
chmod +x "$T/bin/ipmitool"
echo "28 28 28 28 28 28 28 28 28 28 28 28 28" > "$T/fan_state"
export RVI_TEST_STATE="$T/fan_state"

cd "$T"
export PATH="$T/bin:$PATH"
source ./20_iometer_run.sh

FAILS=0
check() { # label, condition-result
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; else echo "FAIL: $1"; FAILS=$((FAILS+1)); fi
}

# 1. set 40% (0x28) -> verified
set_and_verify_fan 40 >/dev/null 2>&1; check "set_and_verify_fan 40" $?
n=$(grep -o '28' "$T/fan_state" | wc -l); [ "$n" -eq 13 ]; check "state = 13x 28 (got $n)" $?

# 2. set 100% (0x64) -> verified
set_and_verify_fan 100 >/dev/null 2>&1; check "set_and_verify_fan 100" $?
n=$(grep -o '64' "$T/fan_state" | wc -l); [ "$n" -eq 13 ]; check "state = 13x 64 (got $n)" $?

# 3. BMC stuck: readback stays 64 but we request 99 (63) -> must FAIL after retries
echo "64 64 64 64 64 64 64 64 64 64 64 64 64" > "$T/fan_state"
export RVI_MOCK_STUCK=1
set_and_verify_fan 99 >/dev/null 2>&1; [ $? -ne 0 ]; check "stuck BMC -> set_and_verify_fan 99 fails" $?
unset RVI_MOCK_STUCK
attempts=$(grep -c 'fan set level=99 attempt' "$RUN_LOG"); [ "$attempts" -eq 3 ]; check "exactly 3 attempts logged (got $attempts)" $?

# 4. restore_fan writes original bytes
restore_fan "28 28 28 28 28 28 28 28 28 28 28 28 28" >/dev/null 2>&1
n=$(grep -o '28' "$T/fan_state" | wc -l); [ "$n" -eq 13 ]; check "restore_fan -> 13x 28 (got $n)" $?

# 5. CSV naming
name=$(printf "$CSV_4K_FMT" 40); [ "$name" = "fan_40_pct_4K_Random_Writes.csv" ]; check "CSV_4K_FMT -> $name" $?
name=$(printf "$CSV_SEQ_FMT" 100); [ "$name" = "fan_100_pct_256K_Seq_Writes.csv" ]; check "CSV_SEQ_FMT -> $name" $?

# 6. validate_csv: 200 rows pass, 10 rows fail
seq 1 200 > "$T/results/big.csv"; seq 1 10 > "$T/results/small.csv"
validate_csv "$T/results/big.csv" 2>/dev/null; check "validate_csv 200 rows -> pass" $?
validate_csv "$T/results/small.csv" 2>/dev/null; [ $? -ne 0 ]; check "validate_csv 10 rows -> fail" $?

echo "================================================"
if [ "$FAILS" -eq 0 ]; then echo "ALL FAN-LOGIC TESTS PASSED"; else echo "$FAILS TEST(S) FAILED"; exit 1; fi
