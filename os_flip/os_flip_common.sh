#!/usr/bin/env bash
# os_flip_common.sh -- shared library for the os_flip scripts
# (ac_cycle.sh, discovery.sh). Source it after `set -u`. No top-level side
# effects beyond variable defaults; every default is env-overridable.
#
# Requires: bash, ip, ping, ipmitool, python3.
#
# Contents:
#   log / fail                     -- tagged logging
#   load_env_file                  -- strict KEY=VALUE env loader (never sources)
#   ipmi_try / ipmi_default_ok     -- IPMI with site creds, vendor-default fallback
#   relay_safety_restore / relay_arm -- trap-guarded relay restore
#   bmc_power_probe / power_is_off -- BMC power state (either ipmitool format)
#   learn_mac                      -- MAC of an IP from the kernel neigh cache
#   arp_sweep / sweep_find_ip      -- L2 ARP sweep + MAC->IP lookup
#   resolve_endpoints              -- precheck: probe known IPs, self-heal via
#                                     one ARP sweep when an endpoint drifted
#   wait_bmc_up / wait_dut_up      -- two-stage waits (known IP, then drift
#                                     search) for the post-restore phase
#   persist_ips                    -- opt-in (PERSIST_IP=1) line-level rewrite
#                                     of verified refreshed identity into ENV_FILE
#
# Why the ARP sweep exists (2026-11-03 design): both the DUT and the BMC get
# their IP from DHCP on this site, so BOTH can come back at a new IP
# after an AC cycle. A ping sweep cannot find the BMC (AIC BMCs block ICMP and
# only enter the neigh cache after IPMI/UDP traffic), so the drift search is
# L2: raw ARP who-has per IP. The BMC answers ARP even though it never answers
# ping (RMCP+ itself needs it), so one sweep recovers both endpoints.
set -u

PY3=${PY3:-python3}
SCRIPT_COMMON_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE=${OS_FLIP_ENV_FILE:-$SCRIPT_COMMON_DIR/os_flip.env}
ARP_SWEEP_BIN=${ARP_SWEEP_BIN:-$SCRIPT_COMMON_DIR/arp_sweep.py}
SWEEP_HOSTS_BIN=${SWEEP_HOSTS_BIN:-$SCRIPT_COMMON_DIR/sweep_hosts.py}
BMC_SWEEP_BIN=${BMC_SWEEP_BIN:-$SCRIPT_COMMON_DIR/bmc_sweep.py}
BMC_SWEEP_PORT=${BMC_SWEEP_PORT:-443}     # BMC web-UI port used for the drift sweep
ARP_LISTEN=${ARP_LISTEN:-4}        # seconds the sweep listens for replies

# wait budgets (all overridable for smoke tests / sandboxes)
POLL=${POLL:-3}                    # wait-loop poll interval, seconds
DUT_WAIT=${DUT_WAIT:-240}          # total budget: DUT ping UP after restore
BMC_WAIT=${BMC_WAIT:-240}          # total budget: BMC answers IPMI after restore
DUT_DRIFT_START=${DUT_DRIFT_START:-120}   # known-IP wait before the drift search
BMC_DRIFT_START=${BMC_DRIFT_START:-90}    # (BMC back ~81s, DUT cold
                                          #  boot ~148s from power on)
DRIFT_POLL=${DRIFT_POLL:-30}       # drift-search sweep cadence, seconds

# mutable state the waits update (initialized here so set -u never bites)
BMC_UP=0; DUT_UP=0
BMC_PSTAT=unknown
BMC_IP_CHANGED=0; DUT_IP_CHANGED=0
BMC_MAC_LEARNED=0; DUT_MAC_LEARNED=0
DUT_RESOLVED=0; BMC_RESOLVED=0
BPP_RAW=""; BPP_STATE=unknown

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [${LOG_TAG:-os_flip}] $*"
  echo "$msg"
  if [ -n "${LOG_FILE:-}" ]; then echo "$msg" >> "$LOG_FILE"; fi
  return 0
}

fail() { log "FATAL: $*"; exit 1; }

# load_env_file: fill only EMPTY variables from the env file (CLI wins).
# Strict KEY=VALUE parsing -- the file is never sourced/executed. (Site
# passwords may start with a backtick: sourcing or double-quoting the values
# into shell assignments would trigger command substitution.)
load_env_file() {
  [ -f "$ENV_FILE" ] || return 1
  local line k v
  while IFS= read -r line; do
    case $line in ''|\#*) continue;; esac
    k=${line%%=*}; v=${line#*=}
    case $k in
      DUT_IP|DUT_MAC|DUT_NET|BMC_IP|BMC_MAC|BMC_USER|BMC_PASS|WIN_USER|WIN_PASS|UBU_USER|UBU_PASS|KNOWN_OUI|RELAY_OFF_CMD|RELAY_ON_CMD|BMC_DEFAULT_USER|BMC_DEFAULT_PASS)
        [ -n "${!k:-}" ] && continue
        export "$k=$v";;
    esac
  done < "$ENV_FILE"
  return 0
}

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

# ipmi_default_ok IP: rc 0 = answers IPMI with the public vendor defaults
ipmi_default_ok() {
  timeout 10 ipmitool -I lanplus -H "$1" -U "${BMC_DEFAULT_USER:-admin}" -P "${BMC_DEFAULT_PASS:-admin}" \
    chassis power status >/dev/null 2>&1
}

RELAY_STATE=on     # "cut" while the relay is known to be off (trap-guarded)
relay_safety_restore() {
  [ "${RELAY_STATE:-on}" = "cut" ] || return 0
  [ -n "${RELAY_ON_CMD:-}" ] || return 0
  log "SAFETY: relay still cut at exit -- restoring: bash -c \"$RELAY_ON_CMD\""
  bash -c "$RELAY_ON_CMD" >/dev/null 2>&1 || log "SAFETY: restore command failed -- restore the relay MANUALLY"
  RELAY_STATE=on
}
relay_arm() { trap relay_safety_restore EXIT; }

# bmc_power_probe IP: probe the BMC power state. Sets BPP_RAW (first raw
# output) and BPP_STATE (on|off|unknown). rc 0 = the BMC answered, rc 1 = no
# answer. Real ipmitool prints "Chassis Power is on/off" (no colon -- that
# format is chassis *status*, not power status); the second format is parsed
# from chassis status.
bmc_power_probe() {
  local h=$1 cs
  BPP_RAW=$(ipmi_try "$h" chassis power status 2>/dev/null) || BPP_RAW=""
  case "$BPP_RAW" in
    *"is on"*)  BPP_STATE=on;  return 0;;
    *"is off"*) BPP_STATE=off; return 0;;
  esac
  [ -n "$BPP_RAW" ] && { BPP_STATE=unknown; return 0; }
  cs=$(ipmi_try "$h" chassis status 2>/dev/null) || true
  case "$cs" in
    *"System Power"*": off"*) BPP_STATE=off; return 0;;
    *"System Power"*": on"*)  BPP_STATE=on;  return 0;;
  esac
  BPP_STATE=unknown
  return 1
}

# power_is_off IP: BMC confirms the system power is off
power_is_off() { bmc_power_probe "$1" && [ "$BPP_STATE" = off ]; }

# learn_mac IP: MAC from the kernel neigh cache (empty when absent). A neigh
# entry exists after any traffic to the IP (a ping, or an IPMI session --
# RMCP+ is UDP 623 and needs ARP even for ICMP-deaf BMCs).
learn_mac() {
  ip neigh show "$1" 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="lladdr"){print tolower($(i+1)); break}}' | head -1
}

# arp_sweep OUTFILE [CIDR]: L2 ARP sweep; writes "ip mac" lines to OUTFILE.
# CIDR defaults to $DUT_NET, then to the runner's own /24. rc 0 = the sweep
# ran (zero or more responders); rc 1 = the sweep itself failed (the WARN
# says why -- on non-root boxes the sweep needs sudo, see below).
# The sweep opens an AF_PACKET raw socket: as root it runs directly; as a
# non-root user it is retried via sudo (passwordless if `sudo -n` works,
# otherwise the password in $SUDO_PASS). With neither, it refuses loudly --
# a blind sweep is worse than none (silent PermissionError would empty the
# candidate list and waste the whole drift budget).
arp_sweep() {
  local out=$1 cidr=${2:-${DUT_NET:-}} rip errf n ran=0
  [ -n "$cidr" ] || {
    rip=$(ip -4 -o addr show 2>/dev/null | awk '$2 != "lo" {split($4,a,"/"); print a[1]; exit}')
    [ -n "$rip" ] || { log "arp_sweep: cannot derive a scan range (set DUT_NET)"; return 1; }
    cidr="${rip%.*}.0/24"
  }
  errf=$(mktemp)
  if [ "$(id -u)" = "0" ]; then
    "$PY3" "$ARP_SWEEP_BIN" "$cidr" "$ARP_LISTEN" > "$out" 2> "$errf" && ran=1
  elif command -v sudo >/dev/null 2>&1; then
    if sudo -n true 2>/dev/null; then
      sudo -n "$PY3" "$ARP_SWEEP_BIN" "$cidr" "$ARP_LISTEN" > "$out" 2> "$errf" && ran=1
    elif [ -n "${SUDO_PASS:-}" ]; then
      printf '%s\n' "$SUDO_PASS" | sudo -S "$PY3" "$ARP_SWEEP_BIN" "$cidr" "$ARP_LISTEN" > "$out" 2> "$errf" && ran=1
    fi
  fi
  if [ "$ran" != "1" ]; then
    log "WARN: arp_sweep cannot run (range $cidr): needs root/CAP_NET_RAW, or sudo (set SUDO_PASS): $(head -c 200 "$errf")"
    rm -f "$errf"
    return 1
  fi
  rm -f "$errf"
  n=$(wc -l < "$out" 2>/dev/null || echo 0)
  log "arp sweep ($cidr): $n responder(s)"
  return 0
}

# sweep_hosts OUTFILE [CIDR]: ICMP-ping sweep + kernel neigh MACs (no raw
# socket needed -- the kernel's own ICMP path, which also works on Wi-Fi
# runners where AF_PACKET injection is silently dropped). Writes "ip mac"
# lines, the same format arp_sweep produces (sweep_find_ip consumes it).
# rc 0 = sweep ran | rc 1 = failed.
sweep_hosts() {
  local out=$1 cidr=${2:-${DUT_NET:-}}
  [ -n "$cidr" ] || { log "sweep_hosts: no range (set DUT_NET)"; return 1; }
  if ! "$PY3" "$SWEEP_HOSTS_BIN" "$cidr" > "$out" 2>/dev/null; then
    log "WARN: sweep_hosts failed (range $cidr)"
    return 1
  fi
  log "ping sweep ($cidr): $(wc -l < "$out") live host(s)"
  return 0
}

# bmc_sweep OUTFILE [CIDR]: TCP-connect sweep of the BMC web-UI port (plain
# sockets -- no raw needed). One candidate IP per line; VERIFY a hit with
# bmc_power_probe before trusting it (other boxes may serve the port).
# rc 0 = sweep ran | rc 1 = failed.
bmc_sweep() {
  local out=$1 cidr=${2:-${DUT_NET:-}}
  [ -n "$cidr" ] || { log "bmc_sweep: no range (set DUT_NET)"; return 1; }
  if ! "$PY3" "$BMC_SWEEP_BIN" "$cidr" "$BMC_SWEEP_PORT" > "$out" 2>/dev/null; then
    log "WARN: bmc_sweep failed (range $cidr, port $BMC_SWEEP_PORT)"
    return 1
  fi
  log "bmc port sweep ($cidr :$BMC_SWEEP_PORT): $(wc -l < "$out") candidate(s)"
  return 0
}

# sweep_find_ip OUTFILE MAC: print the IPs bound to MAC in a sweep output
# (exact field match -- no prefix confusion), one per line, sorted.
sweep_find_ip() {
  local out=$1 mac=$2
  [ -f "$out" ] || return 0
  mac=$(echo "$mac" | tr 'A-Z' 'a-z')
  awk -v m="$mac" 'tolower($2) == m {print $1}' "$out" | sort -u
}

# resolve_endpoints: probe DUT (ping) and BMC (IPMI) at their known IPs. If
# the DUT is unreachable and its MAC is known, a ping+neigh sweep searches
# for its drifted IP; if the BMC stops answering IPMI, a port sweep of the
# BMC web-UI port searches for it (a good IPMI answer verifies the hit). A
# live candidate is adopted (DUT_IP / BMC_IP updated, CHANGED flags set).
# MACs are learned from the neigh cache when a probe succeeds and the MAC is
# not yet known (LEARNED flags set).
# Sets DUT_RESOLVED / BMC_RESOLVED (0/1).
resolve_endpoints() {
  local sweepfile ips cand
  DUT_RESOLVED=0; BMC_RESOLVED=0
  ping -c1 -W2 "$DUT_IP" >/dev/null 2>&1 && DUT_RESOLVED=1
  ipmi_try "$BMC_IP" chassis power status >/dev/null 2>&1 && BMC_RESOLVED=1
  if [ $DUT_RESOLVED -eq 1 ] && [ -z "${DUT_MAC:-}" ]; then
    DUT_MAC=$(learn_mac "$DUT_IP")
    [ -n "$DUT_MAC" ] && DUT_MAC_LEARNED=1 && log "DUT_MAC learned from ARP: $DUT_MAC"
  fi
  if [ $BMC_RESOLVED -eq 1 ] && [ -z "${BMC_MAC:-}" ]; then
    BMC_MAC=$(learn_mac "$BMC_IP")
    [ -n "$BMC_MAC" ] && BMC_MAC_LEARNED=1 && log "BMC_MAC learned from ARP: $BMC_MAC"
  fi
  [ $DUT_RESOLVED -eq 1 ] && [ $BMC_RESOLVED -eq 1 ] && return 0
  if [ $DUT_RESOLVED -eq 0 ] && [ -z "${DUT_MAC:-}" ]; then
    log "WARN: DUT $DUT_IP unreachable and DUT_MAC unset -- no drift search possible for the DUT"
  fi
  if [ $DUT_RESOLVED -eq 0 ] && [ -n "${DUT_MAC:-}" ]; then
    log "precheck: DUT unreachable at known IP -- ping+neigh sweep for its MAC (${DUT_MAC})"
    sweepfile=$(mktemp)
    if sweep_hosts "$sweepfile"; then
      ips=$(sweep_find_ip "$sweepfile" "$DUT_MAC")
      for cand in $ips; do
        if ping -c1 -W2 "$cand" >/dev/null 2>&1; then
          DUT_RESOLVED=1
          if [ "$cand" != "$DUT_IP" ]; then
            log "precheck: DUT found at new IP (DHCP drift): $DUT_IP -> $cand"
            DUT_IP_CHANGED=1; DUT_IP=$cand
          fi
          break
        fi
      done
    fi
    rm -f "$sweepfile"
  fi
  if [ $BMC_RESOLVED -eq 0 ]; then
    log "precheck: BMC not answering IPMI -- port sweep (:$BMC_SWEEP_PORT) + IPMI verify"
    bmcfile=$(mktemp)
    if bmc_sweep "$bmcfile"; then
      while read -r cand; do
        [ -n "$cand" ] || continue
        if ipmi_try "$cand" chassis power status >/dev/null 2>&1; then
          BMC_RESOLVED=1
          if [ "$cand" != "$BMC_IP" ]; then
            log "precheck: BMC found at new IP (DHCP drift): $BMC_IP -> $cand"
            BMC_IP_CHANGED=1; BMC_IP=$cand
          fi
          break
        fi
      done < "$bmcfile"
    fi
    rm -f "$bmcfile"
  fi
}

# wait_bmc_up: wait for the BMC (IPMI) after the relay restore. Stage 1 probes
# the known $BMC_IP; past BMC_DRIFT_START, stage 2 repeats (every DRIFT_POLL):
# bmc port sweep -> IPMI-probe each candidate -> adopt. No MAC needed (the
# port + a good IPMI answer IS the fingerprint). Sets
# BMC_UP (0/1), BMC_PSTAT (on/off/unknown); updates BMC_IP when found at a new
# IP (BMC_IP_CHANGED=1). rc 0 = up.
wait_bmc_up() {
  local t0 now cand ips sweepfile
  BMC_UP=0; BMC_PSTAT=unknown
  t0=$(date +%s)
  log "waiting for BMC $BMC_IP to answer IPMI (known IP, ${BMC_DRIFT_START}s) ..."
  while :; do
    now=$(date +%s)
    [ $((now - t0)) -ge "$BMC_WAIT" ] && break
    [ $((now - t0)) -ge "$BMC_DRIFT_START" ] && break
    if bmc_power_probe "$BMC_IP"; then
      BMC_UP=1; BMC_PSTAT=$BPP_STATE
      log "BMC $BMC_IP is back (power state: $BMC_PSTAT)"
      return 0
    fi
    sleep "$POLL"
  done
  log "BMC $BMC_IP not back after ${BMC_DRIFT_START}s -- drift search (bmc port sweep :${BMC_SWEEP_PORT} + IPMI verify)"
  sweepfile=$(mktemp)
  while :; do
    now=$(date +%s)
    [ $((now - t0)) -ge "$BMC_WAIT" ] && break
    bmc_sweep "$sweepfile"
    while read -r cand; do
      [ -n "$cand" ] || continue
      if bmc_power_probe "$cand"; then
        BMC_UP=1; BMC_PSTAT=$BPP_STATE
        if [ "$cand" != "$BMC_IP" ]; then
          log "BMC found at new IP (DHCP drift): $BMC_IP -> $cand (power state: $BMC_PSTAT)"
          BMC_IP_CHANGED=1; BMC_IP=$cand
        else
          log "BMC $cand is back at its known IP (power state: $BMC_PSTAT)"
        fi
        rm -f "$sweepfile"
        return 0
      fi
    done
    log "drift search: no live BMC yet (candidates: $(tr '\n' ' ' < "$sweepfile"))"
    sleep "$DRIFT_POLL"
  done
  rm -f "$sweepfile"
  log "WARN: BMC not found (known IP $BMC_IP, port sweep :$BMC_SWEEP_PORT) within ${BMC_WAIT}s"
  return 1
}

# wait_dut_up: wait for the DUT (ping) after the relay restore. Stage 1 pings
# the known $DUT_IP; past DUT_DRIFT_START, stage 2 repeats (every DRIFT_POLL):
# ping+neigh sweep -> DUT_MAC match -> ping the matched IP -> adopt. The MAC
# comes from the kernel neigh cache after a live ping, so stale entries from
# before the cut cannot fake a hit. No raw socket needed (Wi-Fi-safe).
# Sets DUT_UP (0/1); updates
# DUT_IP when found at a new IP (DUT_IP_CHANGED=1). rc 0 = up.
wait_dut_up() {
  local t0 now cand ips sweepfile
  DUT_UP=0
  t0=$(date +%s)
  log "waiting for DUT $DUT_IP ping UP (known IP, ${DUT_DRIFT_START}s) ..."
  while :; do
    now=$(date +%s)
    [ $((now - t0)) -ge "$DUT_WAIT" ] && break
    [ $((now - t0)) -ge "$DUT_DRIFT_START" ] && break
    if ping -c1 -W1 "$DUT_IP" >/dev/null 2>&1; then
      DUT_UP=1
      log "DUT ping UP ($DUT_IP)"
      return 0
    fi
    sleep "$POLL"
  done
  if [ -z "${DUT_MAC:-}" ]; then
    log "WARN: DUT $DUT_IP not up after ${DUT_DRIFT_START}s and DUT_MAC unset -- no drift search possible; keeping the known-IP ping until the budget"
    while :; do
      now=$(date +%s)
      [ $((now - t0)) -ge "$DUT_WAIT" ] && break
      if ping -c1 -W1 "$DUT_IP" >/dev/null 2>&1; then
        DUT_UP=1
        log "DUT ping UP ($DUT_IP)"
        return 0
      fi
      sleep "$POLL"
    done
    log "WARN: DUT ping not UP within ${DUT_WAIT}s (it may still be booting)"
    return 1
  fi
  log "DUT $DUT_IP not up after ${DUT_DRIFT_START}s -- drift search (ping+neigh sweep, DUT_MAC ${DUT_MAC})"
  sweepfile=$(mktemp)
  while :; do
    now=$(date +%s)
    [ $((now - t0)) -ge "$DUT_WAIT" ] && break
    sweep_hosts "$sweepfile" || log "WARN: sweep round failed (see above) -- retrying"
    ips=$(sweep_find_ip "$sweepfile" "$DUT_MAC")
    for cand in $ips; do
      if ping -c1 -W1 "$cand" >/dev/null 2>&1; then
        DUT_UP=1
        if [ "$cand" != "$DUT_IP" ]; then
          log "DUT found at new IP (DHCP drift): $DUT_IP -> $cand"
          DUT_IP_CHANGED=1; DUT_IP=$cand
        else
          log "DUT ping UP at known IP ($DUT_IP)"
        fi
        rm -f "$sweepfile"
        return 0
      fi
    done
    log "drift search: DUT not pingable yet (candidates: $(echo $ips))"
    sleep "$DRIFT_POLL"
  done
  rm -f "$sweepfile"
  log "WARN: DUT not found (known IP $DUT_IP, MAC ${DUT_MAC}) within ${DUT_WAIT}s"
  return 1
}

# persist_ips: with PERSIST_IP=1, rewrite the identity lines this run VERIFIED
# (changed IPs only after the endpoint came up; learned MACs only after a
# successful probe) back into ENV_FILE -- line-level replace-or-append, every
# other line byte-preserved (passwords and relay commands are never touched).
persist_ips() {
  [ "${PERSIST_IP:-0}" = "1" ] || return 0
  [ -f "$ENV_FILE" ] || { log "WARN: PERSIST_IP=1 but $ENV_FILE does not exist -- nothing persisted"; return 0; }
  local key val tmp done=0
  for key in DUT_IP BMC_IP DUT_MAC BMC_MAC; do
    val=${!key:-}
    [ -n "$val" ] || continue
    case $key in
      DUT_IP)  [ "${DUT_IP_CHANGED:-0}" = 1 ] || continue; [ "${DUT_UP:-0}" = 1 ] || continue;;
      BMC_IP)  [ "${BMC_IP_CHANGED:-0}" = 1 ] || continue; [ "${BMC_UP:-0}" = 1 ] || continue;;
      DUT_MAC) [ "${DUT_MAC_LEARNED:-0}" = 1 ] || continue;;
      BMC_MAC) [ "${BMC_MAC_LEARNED:-0}" = 1 ] || continue;;
    esac
    tmp=$(mktemp)
    awk -v k="$key" -v v="$val" '
      { if (index($0, k "=") == 1) { printf "%s=%s\n", k, v; n=1; next } print }
      END { if (!n) printf "%s=%s\n", k, v }' "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
    chmod 600 "$ENV_FILE" 2>/dev/null || true
    log "persist: $ENV_FILE updated $key=$val"
    done=1
  done
  [ $done -eq 1 ] || log "persist: nothing to persist (no verified refresh this run)"
  return 0
}
