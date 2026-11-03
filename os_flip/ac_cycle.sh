#!/usr/bin/env bash
# ac_cycle.sh -- one real AC power cycle via the relay, using KNOWN site
# config (os_flip.env or exported env). No sweep, no re-identification:
# for a board whose DUT_IP/DUT_MAC/BMC_IP are already known (e.g. from a
# prior discovery.sh run).
#
# Provenance: designed & validated by luke1987515; AI-assisted development
# (Hermes Agent by Nous Research; self-hosted Qwen3.8-27B). Verified on real
# hardware 2026-11-02 (TUCANA dual-OS DUT): 3/3 AC cycles PASS with the
# graceful-shutdown default (PRE_SHUTDOWN=1); legacy hard cut (PRE_SHUTDOWN=0)
# re-verified in sandbox (case I).
#
# Flow: precheck (DUT ping + BMC answers IPMI) -> graceful OS shutdown
# (identify the live OS via ssh probe, fire the shutdown, confirm
# "Chassis Power is off" via the BMC; forced chassis power off fallback
# if the clean path times out) -> cut relay -> settle -> confirm DUT down
# -> restore relay -> wait for BMC (IPMI probe; real BMCs block ICMP) ->
# power on via BMC if it stayed off -> wait for DUT ping -> refresh DUT_IP
# from DUT_MAC -> summary.
#
# Why the graceful shutdown (2026-11-02, TUCANA incident): a hard AC cut
# while the OS is running is an unclean shutdown; on that machine it
# dropped Windows into the no-network Recovery environment (WinRE) and the
# DUT stayed unreachable for >20 min. The relay is therefore never cut
# until the BMC has confirmed the power is OFF. PRE_SHUTDOWN=0 restores
# the legacy hard-cut behavior (do NOT use it on Windows machines).
#
# Safety:
#   - the relay cut is trap-guarded: ANY exit path (error, Ctrl-C, early
#     return) restores the relay if it is still cut
#   - precheck refuses to cut if the BMC does not answer IPMI before the
#     cut (the post-restore recovery depends on it)
#   - the cut is further refused unless the OS probe identified a live OS
#     AND the BMC confirmed power off after the shutdown
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
PRE_SHUTDOWN=${PRE_SHUTDOWN:-1}    # 1 (default): confirm power off before the cut
SHUTDOWN_TIMEOUT=${SHUTDOWN_TIMEOUT:-60}   # budget for the clean OS shutdown
PROBE_TIMEOUT=${PROBE_TIMEOUT:-15}  # per ssh probe attempt
ID_PROBE_BUDGET=${ID_PROBE_BUDGET:-120}   # total budget for OS identification
PY3=${PY3:-python3}

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
      DUT_IP|DUT_MAC|BMC_IP|BMC_USER|BMC_PASS|RELAY_OFF_CMD|RELAY_ON_CMD|BMC_DEFAULT_USER|BMC_DEFAULT_PASS|WIN_USER|WIN_PASS|UBU_USER|UBU_PASS)
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

# ---- graceful OS shutdown (confirm OFF via BMC before the AC cut) ----
# Same patterns as os_flip.sh's clean mode (probe_one / ssh_fire /
# shut_down_os); the OSFLIPPROBE77/SUDONOK77 markers are shared.

# power_is_off: BMC confirms the system power is off (either ipmitool
# output format: "Chassis Power is off" / "System Power : off").
power_is_off() {
  ipmi_try "$BMC_IP" chassis power status 2>/dev/null | grep -Eq "Chassis Power is off" && return 0
  ipmi_try "$BMC_IP" chassis status 2>/dev/null | grep -Eq "System Power[[:space:]]*:[[:space:]]*off"
}

# ssh_fire USER PASS CMD: send CMD and tolerate a marker-less session (the
# shutdown command kills its own session; EOF is the expected ending).
# rc 0 = auth+send OK (or session ended early) | 1 = spawn error
ssh_fire() {
  local user=$1 pass=$2 cmd=$3 rc
  "$PY3" "$SCRIPT_DIR/ssh_cmd.py" "$user" "$pass" "$DUT_IP" "$cmd" "-" 20 >/dev/null 2>&1
  rc=$?
  case $rc in
    0|1|2) return 0;;   # marker / EOF / timeout: all "sent, let the poll decide"
    *) log "ssh_fire: spawn error (rc=$rc) sending '$cmd'"; return 1;;
  esac
}

# shut_down_os OS: clean shutdown via SSH, then wait for power off.
# Fallback: forced chassis power off if the clean path does not reach off
# within SHUTDOWN_TIMEOUT (hung OS, dead SSH, ...).
# rc 0 = power is off (clean or forced) | 1 = even the forced off timed out
shut_down_os() {
  local os=$1 t0 deadline forced=0
  t0=$(date +%s); deadline=$((t0 + SHUTDOWN_TIMEOUT))
  log "clean shutdown: sending shutdown to $os (budget ${SHUTDOWN_TIMEOUT}s)"
  if [ "$os" = "windows" ]; then
    ssh_fire "$WIN_USER" "$WIN_PASS" "shutdown /s /t 0 /f" || return 1
  else
    # Ubuntu: shutdown needs root. Try passwordless sudo first; otherwise
    # feed the password through sudo -S (backtick in the password is safe:
    # the command travels as one ssh argv element, quoted for the remote shell).
    if "$PY3" "$SCRIPT_DIR/ssh_cmd.py" "$UBU_USER" "$UBU_PASS" "$DUT_IP" \
        "sudo -n true && echo SUDONOK77" "SUDONOK77" 10 2>/dev/null | grep -q "SUDONOK77"; then
      log "clean shutdown: ubuntu dqa has passwordless sudo"
      ssh_fire "$UBU_USER" "$UBU_PASS" "sudo shutdown -h now" || return 1
    else
      log "clean shutdown: ubuntu dqa needs sudo password"
      ssh_fire "$UBU_USER" "$UBU_PASS" "echo '$UBU_PASS' | sudo -S shutdown -h now" || return 1
    fi
  fi
  while :; do
    if power_is_off; then
      [ $forced -eq 1 ] && log "clean shutdown: forced off confirmed"
      log "clean shutdown: System Power off after $(( $(date +%s) - t0 ))s"
      return 0
    fi
    if [ "$(date +%s)" -ge $deadline ] && [ $forced -eq 0 ]; then
      log "WARN: clean shutdown did not reach off within ${SHUTDOWN_TIMEOUT}s (SSH dead or OS hung) -- forcing chassis power off"
      ipmi_try "$BMC_IP" chassis power off >/dev/null 2>&1
      forced=1
      deadline=$(( $(date +%s) + 30 ))
    fi
    if [ "$(date +%s)" -ge $deadline ]; then
      log "FATAL: DUT never reached power off (clean ${SHUTDOWN_TIMEOUT}s + forced 30s)"
      return 1
    fi
    sleep 2
  done
}

# probe_one USER PASS OSNAME
# Sets PROBE_RC (0=login+hostname ok) and PROBE_HOST.
# Runs ssh-keygen -R first: switching the booted OS swaps the SSH host key,
# so the previous OS's key would make the client die before the password.
probe_one() {
  local user=$1 pass=$2 os=$3 out rc
  PROBE_RC=1
  PROBE_HOST=""
  ssh-keygen -R "$DUT_IP" >/dev/null 2>&1 || true
  if [ "$os" = "windows" ]; then
    out=$("$PY3" "$SCRIPT_DIR/ssh_cmd.py" "$user" "$pass" "$DUT_IP" \
      "hostname & echo OSFLIPPROBE77" "OSFLIPPROBE77" "$PROBE_TIMEOUT")
    rc=$?
  else
    out=$("$PY3" "$SCRIPT_DIR/ssh_cmd.py" "$user" "$pass" "$DUT_IP" \
      'hostname; echo OSFLIPPROBE77' "OSFLIPPROBE77" "$PROBE_TIMEOUT")
    rc=$?
  fi
  # hostname = last line BEFORE the marker. (The pty echo of the password and
  # any ssh error lines sit before the real output; parsing after the marker
  # would pick up junk.)
  PROBE_HOST=$(printf '%s\n' "$out" | awk 'index($0, "OSFLIPPROBE77") {exit} {last=$0} END {print last}' | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [ $rc -eq 0 ] && [ -n "$PROBE_HOST" ] && ! printf '%s' "$PROBE_HOST" | grep -qi 'denied'; then
    PROBE_RC=0
  fi
  return $PROBE_RC
}

# identify_os: probe windows then ubuntu in retry rounds until ID_PROBE_BUDGET.
# After a fresh boot the OS SSH daemon may come up well after the first ping
# (field observation: Ubuntu ping UP, port 22 dead at +15..31s).
# Sets IDENT_OS (windows|ubuntu) / IDENT_HOST. rc 0 = identified.
identify_os() {
  local attempt=0 t0 deadline
  t0=$(date +%s); deadline=$((t0 + ID_PROBE_BUDGET))
  IDENT_OS=""; IDENT_HOST=""
  while :; do
    attempt=$((attempt+1))
    if [ -z "$IDENT_OS" ] && [ -n "${WIN_USER:-}" ] && [ -n "${WIN_PASS:-}" ] && probe_one "$WIN_USER" "$WIN_PASS" windows; then
      IDENT_OS=windows; IDENT_HOST=$PROBE_HOST
    fi
    if [ -z "$IDENT_OS" ] && [ -n "${UBU_USER:-}" ] && [ -n "${UBU_PASS:-}" ] && probe_one "$UBU_USER" "$UBU_PASS" ubuntu; then
      IDENT_OS=ubuntu; IDENT_HOST=$PROBE_HOST
    fi
    [ -n "$IDENT_OS" ] && return 0
    if [ "$(date +%s)" -ge $deadline ]; then
      log "WARN: could not identify a live OS within ${ID_PROBE_BUDGET}s after $attempt round(s)"
      return 1
    fi
    log "identify round $attempt: no live OS yet"
    sleep 5
  done
}

shut_os=""
if [ "${PRE_SHUTDOWN:-1}" = "1" ]; then
  log "identifying live OS on $DUT_IP (windows/ubuntu, budget ${ID_PROBE_BUDGET}s) ..."
  if ! identify_os; then
    fail "no live OS answers ssh on $DUT_IP (win: ${WIN_USER:-<unset>} / ubu: ${UBU_USER:-<unset>}) -- refusing to AC-cut an unidentifiable DUT"
  fi
  log "live OS identified: $IDENT_OS (host: ${IDENT_HOST:-?})"
  if ! shut_down_os "$IDENT_OS"; then
    fail "DUT never reached power off -- NOT cutting the relay; check the DUT manually (BMC SOL console)"
  fi
  shut_os=$IDENT_OS
else
  log "PRE_SHUTDOWN=0 -- legacy hard cut (no graceful OS shutdown)"
fi

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
  log "==== ac_cycle done: result=PASS dut=$DUT_IP bmc=$BMC_IP pstat=$pstat shut_os=$shut_os ===="
  exit 0
fi
log "==== ac_cycle done: result=FAIL dut_up=$dut_up bmc_up=$bmc_up pstat=$pstat shut_os=$shut_os ===="
exit 1
