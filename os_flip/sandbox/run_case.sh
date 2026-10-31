#!/usr/bin/env bash
# Sandbox case runner. Usage: run_case.sh A|B|C|D|E|F|G|H
#   A = normal 2 cycles (win->ubuntu->windows), RESET mode (legacy)
#   B = nav verify fail on DOWN 5 (no ENTER, safe exit, abort), RESET
#   C = boot timeout after ENTER handoff (FAIL, abort), RESET
#   D = collect failure on cycle 1 (PARTIAL, continue, cycle 2 PASS), RESET
#   E = normal 2 cycles, CLEAN mode (ssh shutdown -> off -> bootdev off ->
#       power on -> nav), both the windows and the ubuntu shutdown path
#   F = CLEAN mode, SSH hangs mid-cycle (SB_SSH_DIE_AFTER=1): forced cold
#       off/on fallback, cycle still PASS with a WARN
#   G = CLEAN mode, BIOS drops the one-shot latch on the first attempt
#       (SB_NOSUPE): setup retry (off -> re-latch -> power on) recovers
#   H = discovery.sh E3 power-off fingerprint (relay ON->OFF->ON): DUT MAC
#       vanishes, BMC survives (independent power); the fingerprint must
#       identify DUT+BMC, restore the relay, and write the env file
set -u
CASE=${1:?case name A|B|C|D|E|F}
ROOT=$(cd "$(dirname "$0")" && pwd)

export SB_STATE=$ROOT/state_$CASE
rm -rf "$SB_STATE" "$ROOT/work_$CASE"
mkdir -p "$SB_STATE" "$ROOT/work_$CASE"
export SB_BOOT_SECS=2
date +%s > "$SB_STATE/boot_at"          # machine already up at precheck
echo windows > "$SB_STATE/bootsed"      # precheck OS = windows (persistent default)
date +%s > "$SB_STATE/power_on"         # power-state epoch for the stubs
date +%s > "$SB_STATE/last_event_seen"  # ssh stub: hang-model epoch baseline
echo on > "$SB_STATE/power"

export PATH="$ROOT/bin:$PATH"
export WORK_DIR=$ROOT/work_$CASE   # keep sandbox logs OUT of the prod dir
export DUT_IP=192.168.1.20             # fake DUT (sandbox-local only)
export BMC_IP=127.0.0.1                 # fake BMC
# stub credentials -- the sandbox stubs never authenticate, but the public
# os_flip.sh ships with no built-in defaults, so every case supplies these
export BMC_USER=admin BMC_PASS=stubpass
export WIN_USER=Administrator WIN_PASS=stubpass
export UBU_USER=dqa UBU_PASS=stubpass
export SOL_DEACT_WAIT=1 SOL_PRE_RESET_WAIT=1 SOL_KEY_SETTLE=0.6 SOL_DOWN_SETTLE=0.8 SOL_UP_TAIL=2
export SETUP_TIMEOUT=20 BOOT_TIMEOUT=25 PROBE_TIMEOUT=15 COLLECT_TIMEOUT=15 PRE_PING_TRIES=2

case $CASE in
  A) export CYCLES=2 SHUTDOWN_MODE=reset ;;
  B) export CYCLES=1 SHUTDOWN_MODE=reset SB_NAVFAIL_AT=5 ;;
  C) export CYCLES=1 SHUTDOWN_MODE=reset SB_NOBOOT=1 BOOT_TIMEOUT=10 ;;
  D) export CYCLES=2 SHUTDOWN_MODE=reset SB_COLLECT_FAIL=1 COLLECT_TIMEOUT=8 ;;
  E) export CYCLES=2 SHUTDOWN_MODE=clean SOL_PRE_POWERON_WAIT=1 ;;
  F) export CYCLES=1 SHUTDOWN_MODE=clean SHUTDOWN_TIMEOUT=5 SB_SSH_DIE_AFTER=1 \
       SOL_PRE_POWERON_WAIT=1 ;;
  G) export CYCLES=1 SHUTDOWN_MODE=clean SETUP_TIMEOUT=15 \
       SOL_PRE_POWERON_WAIT=1 SB_NOSUPE=1 ;;
  H) ;;
  *) echo "unknown case $CASE"; exit 2;;
esac

pkill -f "$ROOT/bin/ssh" 2>/dev/null
pkill -f "$ROOT/bin/ipmitool" 2>/dev/null
if [ "$CASE" = "H" ]; then
  # identity env must be empty so the fingerprint finds everything itself;
  # OS passwords are fakes so ask_credentials never prompts (non-tty)
  unset DUT_IP DUT_MAC BMC_IP BMC_PASS
  export SB_DUT_IP=192.168.1.20 DUT_NET=192.168.1.0/24
  export WIN_PASS=stubpass UBU_PASS=stubpass
  export RELAY_OFF_CMD="echo off > $SB_STATE/relay"
  export RELAY_ON_CMD="echo on > $SB_STATE/relay"
  export OS_FLIP_ENV_FILE=$ROOT/work_H/os_flip.env
  bash "$ROOT/discovery.sh" --auto | tee "$ROOT/work_H/discovery.out"
  rc=${PIPESTATUS[0]}
  if [ $rc -ne 0 ] || ! grep -q "fingerprint result: DUT 192.168.1.20 (00:15:b2:aa:bb:01) | BMC 127.0.0.1 (00:15:b2:aa:bb:03)" "$ROOT/work_H/discovery.out"; then
    echo "CASE H: fingerprint failed or result mismatch"
    rc=1
  elif ! grep -q "^DUT_MAC=00:15:b2:aa:bb:01" "$ROOT/work_H/os_flip.env" 2>/dev/null \
       || ! grep -q "^BMC_IP=127.0.0.1" "$ROOT/work_H/os_flip.env" 2>/dev/null; then
    echo "CASE H: env file missing DUT_MAC/BMC_IP"
    rc=1
  fi
else
  bash "$ROOT/os_flip.sh"
  rc=$?
fi
echo "=== case $CASE rc=$rc ==="
pkill -f "$ROOT/bin/ssh" 2>/dev/null
pkill -f "$ROOT/bin/ipmitool" 2>/dev/null
exit $rc
