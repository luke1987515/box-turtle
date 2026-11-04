#!/usr/bin/env bash
# ac_cycle.sh -- one real AC power cycle via the relay, using KNOWN site
# config (os_flip.env or exported env). No sweep, no re-identification:
# for a board whose DUT_IP/DUT_MAC/BMC_IP are already known (e.g. from a
# prior discovery.sh run).
#
# Provenance: designed & validated by luke1987515; AI-assisted development
# (Hermes Agent by Nous Research; self-hosted Qwen3.8-27B). Verified on real
# hardware: 2026-11-02 (dual-OS DUT) 3/3 cycles PASS with the
# graceful-shutdown default (PRE_SHUTDOWN=1); 2026-11-04 (relay-cut
# runner on WiFi) graceful cycle PASS -- Windows clean shutdown in 5s, relay
# cut window 8s, BMC back 75s, DUT pingable 193s after power on, no DHCP
# drift (the post-120s drift search caught the DUT). Hard-cut cycles
# (PRE_SHUTDOWN=0) on the same board run the full flow safely, but the DUT
# stays network-invisible 8-10 min after a hard cut (OS already up on KVM) --
# keep PRE_SHUTDOWN=1 on Windows boards and size DUT_WAIT to network-up time
# (>=600) when hard-cut diagnostics are needed.
#
# Flow: precheck (DUT ping + BMC answers IPMI; an endpoint unreachable at its
# known IP is re-found via ONE arp sweep matched on its MAC) -> graceful OS
# shutdown (identify the live OS via ssh probe, fire the shutdown, confirm
# "Chassis Power is off" via the BMC; forced chassis power off fallback if
# the clean path times out) -> cut relay -> settle -> confirm DUT down ->
# restore relay -> two-stage BMC wait (known IP, then drift search) -> power
# on via BMC if it stayed off -> two-stage DUT wait (known IP, then drift
# search) -> optional persist of verified refreshed identity (PERSIST_IP=1)
# -> summary.
#
# Why the drift handling (2026-11-03): on this site BOTH the DUT and the BMC
# take their IP from DHCP, so either can come back at a new IP after
# the cycle. A fixed-IP wait would then burn its budget and report a false
# FAIL. Both waits are two-stage: probe the known IP first (happy path = zero
# extra traffic), and past a threshold repeat an L2 ARP sweep and match the
# endpoint's MAC (a ping sweep cannot see the BMC -- AIC BMCs block ICMP but
# answer ARP). MACs are learned from the neigh cache at precheck when not in
# the env, so the fallback self-bootstraps without a discovery run.
#
# Why the graceful shutdown (2026-11-02, dual-OS DUT incident): a hard AC cut
# while the OS is running is an unclean shutdown; on that machine it
# dropped Windows into the no-network Recovery environment (WinRE) and the
# DUT stayed unreachable for >20 min. The relay is therefore never cut
# until the BMC has confirmed the power is OFF. PRE_SHUTDOWN=0 restores
# the legacy hard-cut behavior (do NOT use it on Windows machines).
#
# Safety:
#   - the relay cut is trap-guarded: ANY exit path (error, Ctrl-C, early
#     return) restores the relay if it is still cut
#   - precheck refuses to cut unless both endpoints are reachable (known IP
#     or drift-verified) -- the post-restore recovery depends on the BMC
#   - the cut is further refused (PRE_SHUTDOWN=1) unless the OS probe
#     identified a live OS AND the BMC confirmed power off after the shutdown
#   - never touches the persistent boot order, the BMC config, or the OSes
#   - the env file is read-only unless PERSIST_IP=1 (then only the identity
#     lines verified this run are rewritten)
#
# Usage:
#   RELAY_OFF_CMD='...' RELAY_ON_CMD='...' ./ac_cycle.sh
#   (or keep RELAY_OFF_CMD / RELAY_ON_CMD in os_flip.env)
#   PERSIST_IP=1 ./ac_cycle.sh   # also write verified refreshed IPs/MACs back
# Exit: 0 = PASS (DUT back, BMC back) | 1 = FAIL
set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/os_flip_common.sh"
LOG_TAG=ac_cycle
ENV_FILE=${OS_FLIP_ENV_FILE:-$SCRIPT_DIR/os_flip.env}

# ac_cycle-specific knobs (wait budgets / drift thresholds live in the common)
AC_SETTLE=${AC_SETTLE:-6}      # seconds the relay stays cut
PRE_SHUTDOWN=${PRE_SHUTDOWN:-1}    # 1 (default): confirm power off before the cut
SHUTDOWN_TIMEOUT=${SHUTDOWN_TIMEOUT:-60}   # budget for the clean OS shutdown
PROBE_TIMEOUT=${PROBE_TIMEOUT:-15}  # per ssh probe attempt
ID_PROBE_BUDGET=${ID_PROBE_BUDGET:-120}   # total budget for OS identification
PERSIST_IP=${PERSIST_IP:-0}    # 1 = rewrite verified refreshed identity into ENV_FILE

load_env_file

# ---- prerequisites ----
[ -n "${RELAY_OFF_CMD:-}" ] && [ -n "${RELAY_ON_CMD:-}" ] || \
  fail "RELAY_OFF_CMD / RELAY_ON_CMD not set (env or os_flip.env)"
[ -n "${DUT_IP:-}" ] || fail "DUT_IP unknown -- run discovery.sh first"
[ -n "${BMC_IP:-}" ] || fail "BMC_IP unknown -- run discovery.sh first"
relay_arm

# ---- precheck (refuse to cut unless both endpoints look sane) ----
log "precheck: DUT $DUT_IP pingable / BMC $BMC_IP answers IPMI"
resolve_endpoints
[ "$DUT_RESOLVED" -eq 1 ] || \
  fail "DUT not reachable at $DUT_IP (known IP + drift search) -- wrong IP / already down / DUT_MAC unset?"
[ "$BMC_RESOLVED" -eq 1 ] || \
  fail "BMC $BMC_IP does not answer IPMI (known IP + drift search) -- post-restore recovery depends on it; aborting"
[ -n "${DUT_MAC:-}" ] || log "WARN: DUT_MAC still unset -- post-restore drift search for the DUT will be impossible"
[ -n "${BMC_MAC:-}" ] || log "WARN: BMC_MAC still unset -- post-restore drift search for the BMC will be impossible"

# ---- graceful OS shutdown (confirm OFF via BMC before the AC cut) ----
# Same patterns as os_flip.sh's clean mode (probe_one / ssh_fire /
# shut_down_os); the OSFLIPPROBE77/SUDONOK77 markers are shared.


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
    if power_is_off "$BMC_IP"; then
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

# ---- post-restore: BMC (two-stage; IPMI probe; real BMCs block ICMP) ----
wait_bmc_up
if [ "$BMC_UP" -eq 1 ]; then
  case "$BMC_PSTAT" in
    off) log "system is OFF after AC loss -- powering on via BMC"
         ipmi_try "$BMC_IP" chassis power on >/dev/null 2>&1 || \
           log "WARN: BMC power on failed -- power the system on manually" ;;
    on) log "system already ON (auto power-restore in effect)" ;;
    *) log "WARN: could not parse BMC power state (state: $BMC_PSTAT)" ;;
  esac
else
  log "WARN: BMC unavailable after restore -- cannot verify/force the power state"
fi

# ---- post-restore: DUT (two-stage: known IP, then MAC drift search) ----
wait_dut_up

# ---- optional persist of verified refreshed identity ----
persist_ips

# ---- summary ----
if [ "$DUT_UP" -eq 1 ] && [ "$BMC_UP" -eq 1 ]; then
  log "==== ac_cycle done: result=PASS dut=$DUT_IP bmc=$BMC_IP pstat=$BMC_PSTAT shut_os=$shut_os ===="
  exit 0
fi
log "==== ac_cycle done: result=FAIL dut_up=$DUT_UP bmc_up=$BMC_UP pstat=$BMC_PSTAT shut_os=$shut_os ===="
exit 1
