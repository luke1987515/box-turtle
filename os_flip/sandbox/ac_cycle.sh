#!/usr/bin/env bash
# ac_cycle.sh -- one real AC power cycle via the relay, using KNOWN site
# config (os_flip.env or exported env). No sweep, no re-identification:
# for a board whose DUT_IP/DUT_MAC/BMC_IP are already known (e.g. from a
# prior discovery.sh run).
#
# Flow: precheck (DUT ping + BMC answers IPMI) -> cut relay -> settle ->
# confirm DUT down -> restore relay -> wait for BMC (IPMI probe; real
# BMCs block ICMP) -> power on via BMC if it stayed off -> wait for DUT
# ping -> refresh DUT_IP from DUT_MAC -> summary.
#
# Safety:
#   - the relay cut is trap-guarded: ANY exit path (error, Ctrl-C, early
#     return) restores the relay if it is still cut
#   - precheck refuses to cut if the BMC does not answer IPMI before the
#     cut (the post-restore recovery depends on it)
#   - never touches the persistent boot order, the BMC config, or the OSes
#   - read-only toward the env file (no writes)
#
# Usage:
#   RELAY_OFF_CMD='...' RELAY_ON_CMD='...' ./ac_cycle.sh
#   (or keep RELAY_OFF_CMD / RELAY_ON_CMD in os_flip.env)
# Exit: 0 = PASS (DUT back, BMC back) | 1 = FAIL
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ENV_FILE=${OS_FLIP_ENV_FILE:-$SCRIPT_DIR/os_flip.env}

AC_SETTLE=${AC_SETTLE:-6}      # seconds the relay stays cut
BMC_WAIT=${BMC_WAIT:-180}     # budget for BMC to answer IPMI after restore
DUT_WAIT=${DUT_WAIT:-180}     # budget for DUT ping after restore

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ac_cycle] $*"
  echo "$msg"
  [ -n "${LOG_FILE:-}" ] && echo "$msg" >> "$LOG_FILE"
}

# load_env_file: fill only EMPTY variables from the env file (CLI wins).
# Strict KEY=VALUE parsing -- the file is never sourced/executed.
load_env_file() {
  [ -f "$ENV_FILE" ] || return 1
  local line k v
  while IFS= read -r line; do
    case $line in ''|\#*) continue;; esac
    k=${line%%=*}; v=${line#*=}
    case $k in
      DUT_IP|DUT_MAC|BMC_IP|BMC_USER|BMC_PASS|RELAY_OFF_CMD|RELAY_ON_CMD|BMC_DEFAULT_USER|BMC_DEFAULT_PASS)
        [ -n "${!k:-}" ] && continue
        export "$k=$v";;
    esac
  done < "$ENV_FILE"
  return 0
}
load_env_file

# ipmi_try IP CMD...: IPMI with the best-known credentials -- site creds
# (BMC_PASS) first if set, then the public vendor defaults. rc 0 = success.
ipmi_try() {
  local h=$1; shift
  if [ -n "${BMC_PASS:-}" ]; then
    timeout 15 ipmitool -I lanplus -H "$h" -U "${BMC_USER:-admin}" -P "$BMC_PASS" "$@" 2>/dev/null && return 0
  fi
  timeout 15 ipmitool -I lanplus -H "$h" -U "${BMC_DEFAULT_USER:-admin}" -P "${BMC_DEFAULT_PASS:-admin}" "$@" 2>/dev/null && return 0
  return 1
}

RELAY_STATE=on     # "cut" while the relay is known to be off (trap-guarded)
relay_safety_restore() {
  [ "${RELAY_STATE:-on}" = "cut" ] || return 0
  [ -n "${RELAY_ON_CMD:-}" ] || return 0
  log "SAFETY: relay still cut at exit -- restoring: bash -c \"$RELAY_ON_CMD\""
  bash -c "$RELAY_ON_CMD" >/dev/null 2>&1 || log "SAFETY: restore command failed -- restore the relay MANUALLY"
  RELAY_STATE=on
}
trap relay_safety_restore EXIT

fail() { log "FATAL: $*"; exit 1; }

# ---- prerequisites ----
[ -n "${RELAY_OFF_CMD:-}" ] && [ -n "${RELAY_ON_CMD:-}" ] || \
  fail "RELAY_OFF_CMD / RELAY_ON_CMD not set (env or os_flip.env)"
[ -n "${DUT_IP:-}" ] || fail "DUT_IP unknown -- run discovery.sh first"
[ -n "${BMC_IP:-}" ] || fail "BMC_IP unknown -- run discovery.sh first"

# ---- precheck (refuse to cut unless both endpoints look sane) ----
log "precheck: DUT $DUT_IP pingable"
ping -c1 -W2 "$DUT_IP" >/dev/null 2>&1 || \
  fail "DUT $DUT_IP not pingable before the cut (wrong IP / already down?)"
log "precheck: BMC $BMC_IP answers IPMI"
ipmi_try "$BMC_IP" chassis power status >/dev/null 2>&1 || \
  fail "BMC $BMC_IP does not answer IPMI before the cut -- post-restore recovery depends on it; aborting"

# ---- the AC cycle ----
log "cutting relay: bash -c \"$RELAY_OFF_CMD\" (settle ${AC_SETTLE}s)"
bash -c "$RELAY_OFF_CMD" || fail "relay OFF command failed"
RELAY_STATE=cut
sleep "$AC_SETTLE"

if ping -c1 -W2 "$DUT_IP" >/dev/null 2>&1; then
  log "WARN: DUT $DUT_IP still pingable with the relay cut (relay does not control this DUT?)"
else
  log "DUT confirmed down"
fi

log "restoring relay: bash -c \"$RELAY_ON_CMD\""
if bash -c "$RELAY_ON_CMD"; then
  RELAY_STATE=on
else
  # stay honest: the relay may still be cut; the exit trap will retry
  log "WARN: relay ON command failed -- continuing with relay state = cut (exit trap will retry the restore)"
fi

# ---- post-restore: BMC (IPMI probe; real BMCs block ICMP) ----
log "waiting for BMC $BMC_IP to come back (${BMC_WAIT}s budget) ..."
bmc_up=0 praw="" pstat=""
t0=$(date +%s)
while :; do
  now=$(date +%s)
  if [ $((now - t0)) -ge "$BMC_WAIT" ]; then log "WARN: BMC $BMC_IP not back within ${BMC_WAIT}s"; break; fi
  praw=$(ipmi_try "$BMC_IP" chassis power status 2>/dev/null)
  if [ -n "$praw" ]; then bmc_up=1; log "BMC $BMC_IP is back"; break; fi
  sleep 3
done
if [ "$bmc_up" -eq 1 ]; then
  # real ipmitool prints "Chassis Power is on/off" (no colon -- that
  # format is chassis *status*, not power status)
  case "$praw" in
    *"is on"*)  pstat=on ;;
    *"is off"*) pstat=off ;;
    *)          pstat="" ;;
  esac
  case "$pstat" in
    off) log "system is OFF after AC loss -- powering on via BMC"
         ipmi_try "$BMC_IP" chassis power on >/dev/null 2>&1 || \
           log "WARN: BMC power on failed -- power the system on manually" ;;
    on) log "system already ON (auto power-restore in effect)" ;;
    "") log "WARN: could not parse BMC power state (output: '$praw')" ;;
  esac
else
  log "WARN: BMC unavailable after restore -- cannot verify/force the power state"
fi

# ---- post-restore: DUT ----
log "waiting for DUT $DUT_IP ping UP (${DUT_WAIT}s budget) ..."
dut_up=0
t0=$(date +%s)
while :; do
  now=$(date +%s)
  if [ $((now - t0)) -ge "$DUT_WAIT" ]; then log "WARN: DUT ping not UP within ${DUT_WAIT}s (it may still be booting)"; break; fi
  if ping -c1 -W1 "$DUT_IP" >/dev/null 2>&1; then dut_up=1; log "DUT ping UP"; break; fi
  sleep 3
done

# refresh the DUT IP from its MAC (DHCP drift), the way discovery.sh does
if [ -n "${DUT_MAC:-}" ] && [ "$dut_up" -eq 1 ]; then
  nmac=$(echo "$DUT_MAC" | tr 'A-Z' 'a-z')
  nip=$(ip neigh show 2>/dev/null | awk -v m="$nmac" 'index(tolower($0), m) && $1 ~ /^[0-9]/ {print $1; exit}')
  if [ -n "$nip" ] && [ "$nip" != "$DUT_IP" ]; then
    log "DUT IP refreshed after boot: $DUT_IP -> $nip"
    DUT_IP=$nip
  fi
fi

# ---- summary ----
if [ "$dut_up" -eq 1 ] && [ "$bmc_up" -eq 1 ]; then
  log "==== ac_cycle done: result=PASS dut=$DUT_IP bmc=$BMC_IP pstat=$pstat ===="
  exit 0
fi
log "==== ac_cycle done: result=FAIL dut_up=$dut_up bmc_up=$bmc_up pstat=$pstat ===="
exit 1
