#!/usr/bin/env bash
# os_flip.sh -- dual-OS Boot Override cycle test (one-shot UEFI boot switching).
#
# Provenance: designed & validated by luke1987515; AI-assisted development
# (Hermes Agent by Nous Research; self-hosted Qwen3.8-27B). Verified on real
# hardware 2026-11-01 and 2026-11-02: 20/20 cycles PASS across two 10-cycle
# runs, persistent boot order unchanged. Site-profile rework per
# DESIGN-site-profiles.md v1 (approved 2026-11-07): navigation is profile
# driven (profiles/<SITE>.conf > sites/<SITE>.conf); --check / --discover
# are read-only / setup phases, the cycle phase is read-only on the profile.
#
# Target: a dual-OS DUT (e.g. Windows Server 2022 + Ubuntu 24.04 on one disk,
# persistent UEFI boot order as installed). Each cycle:
#   one-shot Boot Override to the OTHER OS via SOL pty (profile-driven key
#   path) -> wait for boot (SOL stream + ping) -> identify the booted OS
#   (ssh probe + hostname) -> collect that OS's system info -> log all.
#
# The one-shot override does not touch the persistent boot order; each cycle
# consumes its override. No restore step: the run ends on the last booted OS.
#
# Per-cycle log: nav key trace (t/key/+bytes/text), boot duration
# (reset -> ping UP), OS identification evidence (EFI stub / hostname),
# full system-info output, failure reason.
#
# Failure semantics (approved 2026-10-29, decisions 2a/5a):
#   nav verify fail  = no ENTER sent, safe exit (SOL closed + plain reset to
#                      normal boot), cycle FAIL, abort the whole run
#   layout drift     = first item (item_2) live-verify mismatch -> cycle
#                      aborts, re-run --discover (never a silent wrong-OS pick)
#   boot timeout / identification fail / wrong OS = cycle FAIL, abort
#   collection failure after a correct boot = cycle PARTIAL, continue
#
# Stop: pkill -f os_flip
#   (the active SOL driver's exit handler sends a plain power reset if the
#   machine is still in UEFI setup)
#
# Usage:
#   ./os_flip.sh --check      # readiness: env, connectivity, profile gate,
#                             # current OS. No power actions.
#                             # exit 0 = ready | 2 = config/profile problem
#                             #        | 3 = profile identity mismatch
#                             #        | 1 = DUT/BMC/OS not reachable
#   ./os_flip.sh --discover   # setup phase (~5 min): calibrate the site's
#                             # Save & Exit tab into profiles/<SITE>.conf,
#                             # machine returns to its original OS.
#   ./os_flip.sh [N]          # N cycles (default: CYCLES, 10)
set -u
set -o pipefail

# ---------------- config resolution ----------------
# priority: CLI environment > ./os_flip.env > interactive discovery (discovery.sh)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="$SCRIPT_DIR/os_flip.env"

# load_env_file: fill only EMPTY variables from the env file (CLI wins).
# Strict KEY=VALUE parsing -- the file is never sourced/executed.
load_env_file() {
  [ -f "$ENV_FILE" ] || return 1
  local line k v
  while IFS= read -r line; do
    case $line in ''|\#*) continue;; esac
    k=${line%%=*}; v=${line#*=}
    case $k in
      DUT_IP|DUT_MAC|DUT_NET|BMC_IP|BMC_USER|BMC_PASS|WIN_USER|WIN_PASS|UBU_USER|UBU_PASS|SITE_NAME|LINUX_NAME|KNOWN_OUI|RELAY_OFF_CMD|RELAY_ON_CMD|BMC_DEFAULT_USER|BMC_DEFAULT_PASS|RESTORE_BIOS_STATE)
        [ -n "${!k:-}" ] && continue
        export "$k=$v";;
    esac
  done < "$ENV_FILE"
  return 0
}
load_env_file

# ---------------- tunables (all env-overridable) ----------------
# site config -- no defaults; filled by discovery.sh / ./os_flip.env:
DUT_IP=${DUT_IP:-}
DUT_MAC=${DUT_MAC:-}
BMC_IP=${BMC_IP:-}
BMC_PASS=${BMC_PASS:-}
WIN_PASS=${WIN_PASS:-}
UBU_PASS=${UBU_PASS:-}
# account names (vendor/OS conventions; editable, Enter accepts the default):
BMC_USER=${BMC_USER:-admin}
WIN_USER=${WIN_USER:-Administrator}
UBU_USER=${UBU_USER:-dqa}
# site profile (DESIGN-site-profiles.md): profile resolution by SITE_NAME:
#   profiles/<SITE_NAME>.conf (runner local, latest --discover calibration)
#   > sites/<SITE_NAME>.conf (repo baseline)
#   > (none) -> the cycle refuses; run --discover first.
SITE_NAME=${SITE_NAME:-}
# Linux-side OS name token (squash-substring match in the Boot Override
# list): 'ubuntu', 'centos', ... Required for --discover; recommended for
# the cycle (discover will need it later).
LINUX_NAME=${LINUX_NAME:-}
# vendor-default BMC credentials (public) -- used ONLY for discovery's first
# credential trial, never as a fallback after a real failure:
BMC_DEFAULT_USER=${BMC_DEFAULT_USER:-admin}
BMC_DEFAULT_PASS=${BMC_DEFAULT_PASS:-admin}
# known vendor OUIs (public prefixes), comma-separated -- MAC sweep filter:
KNOWN_OUI=${KNOWN_OUI:-00:15:b2}
# relay control commands: set BOTH to enable discovery's power-off fingerprint.
# Each is a full shell command; discovery only ever runs these two, never
# guesses at relay channels.
RELAY_OFF_CMD=${RELAY_OFF_CMD:-}
RELAY_ON_CMD=${RELAY_ON_CMD:-}
# run tunables:
CYCLES=${CYCLES:-10}
SETUP_TIMEOUT=${SETUP_TIMEOUT:-120}
BOOT_TIMEOUT=${BOOT_TIMEOUT:-240}
PROBE_TIMEOUT=${PROBE_TIMEOUT:-30}
COLLECT_TIMEOUT=${COLLECT_TIMEOUT:-120}
PRE_PING_TRIES=${PRE_PING_TRIES:-3}
# clean = SSH shutdown + power off + bootdev-while-off + power on (COLD boot)
# reset = legacy: one-shot bootdev while running + chassis power reset (WARM)
SHUTDOWN_MODE=${SHUTDOWN_MODE:-clean}
SHUTDOWN_TIMEOUT=${SHUTDOWN_TIMEOUT:-60}
# precheck console-redirection gate (bios_redir.sh): if the BIOS console
# redirection was OFF when found, the gate repairs it (nested /Bios/SD PATCH
# + cold cycle + LIVE re-verify). After the run, RESTORE_BIOS_STATE:
#   0 (default) leave it ON (the usable baseline for SOL work)
#   1           restore the found (OFF) state -- costs one extra cold cycle
RESTORE_BIOS_STATE=${RESTORE_BIOS_STATE:-0}
# DUT identity: the IP drifts with DHCP; when DUT_MAC is set, DUT_IP is
# (re)resolved from the ARP/neigh cache on every check.
DUT_NET=${DUT_NET:-}
# DUT_NET default = the runner's own /24 (auto-detected below). Override to
# sweep a different segment (e.g. runner and DUT on different /24, one L2).
if [ -z "$DUT_NET" ]; then
  _runner_ip=$(ip -4 -o addr show 2>/dev/null | awk '$2 != "lo" {print $4; exit}')
  if [ -n "${_runner_ip:-}" ]; then
    DUT_NET="${_runner_ip%.*}.0/24"
  else
    DUT_NET="127.0.0.0/8"    # unreachable fallback: MAC sweeps simply no-op
  fi
fi
export DUT_NET DUT_MAC
WORK_DIR=${WORK_DIR:-$HOME/os_flip}
PY3=${PY3:-python3}
LOCK_FILE="$WORK_DIR/.os_flip.lock"

usage() {
  cat <<'EOF'
os_flip.sh -- dual-OS Boot Override cycle test (site-profile driven)

Usage:
  ./os_flip.sh --check       readiness check: env, connectivity, profile
                             gate, current OS. No power actions.
  ./os_flip.sh --discover    setup phase (~5 min): calibrate the site's
                             Save & Exit tab into profiles/<SITE>.conf.
  ./os_flip.sh [N]           N cycles (default: CYCLES, 10)

Env: see os_flip.env.example (SITE_NAME / LINUX_NAME select the profile).
EOF
}

# ---------------- subcommand dispatch (parsed BEFORE any config gate) ----
CMD="cycle"
case ${1:-} in
  --check)    CMD="check"; shift;;
  --discover) CMD="discover"; shift;;
  -h|--help)  usage; exit 0;;
esac
if [ "$CMD" = "cycle" ] && [ $# -ge 1 ]; then CYCLES=$1; fi
if [ "$CMD" = "cycle" ]; then
  case $CYCLES in (*[!0-9]*|'') echo "CYCLES must be a number (got '$CYCLES')" >&2; exit 2;; esac
fi

TS=$(date +%Y%m%d_%H%M%S)
LOG_DIR="$WORK_DIR/os_flip_$TS"
LOG_FILE="$LOG_DIR/os_flip_$TS.log"
ABORT_FILE="$LOG_DIR/.abort"
mkdir -p "$LOG_DIR"

FAIL_COUNT=0
CYCLE=0
CURRENT_OS=""
SUMMARY_ROWS=""
CYCLE_RESULT=""
CYCLE_OS=""
CYCLE_FAIL_REASON=""
CYCLE_DUR=""
BOOT_SECS=""
CUR_RAW=""
CUR_CLEAN=""
CUR_TRACE=""
PROBE_RC=1
PROBE_HOST=""
IDENT_OS=""
IDENT_HOST=""
IDENT_EVIDENCE=""
PROFILE_FILE=""

log() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$line" | tee -a "$LOG_FILE"
}

trap 'log "!! INTERRUPTED (mode=$CMD, cycle $CYCLE) -- abort flag written; check DUT/BMC power state manually (pkill -f os_flip to finish)"; touch "$ABORT_FILE"; exit 130' INT TERM

ping_ok() { ping -c 1 -W 1 "$DUT_IP" >/dev/null 2>&1; }

bmc_ipmi() { timeout 20 ipmitool -I lanplus -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" "$@"; }

# resolve_dut: re-resolve DUT_IP from a live sweep + the kernel neigh cache,
# keyed on DUT_MAC (the stable identity). /24 only.
# rc 0 = resolved (or DUT_MAC empty -> legacy behavior) | 1 = MAC not found
# (hard precheck failure by design: never test a stale IP).
resolve_dut() {
  [ -z "$DUT_MAC" ] && return 0
  local base x found mac
  mac=$(echo "$DUT_MAC" | tr 'A-Z' 'a-z')
  case $DUT_NET in
    */24) ;;
    *) log "FATAL: DUT_NET must be a.b.c.d/24 (got '$DUT_NET')"; return 1;;
  esac
  base=${DUT_NET%%/*}
  local pids=()
  for x in $(seq 1 254); do
    ping -c1 -W1 "${base%.*}.$x" >/dev/null 2>&1 &
    pids+=($!)
  done
  wait
  sleep 1
  found=$(ip neigh show 2>/dev/null | awk -v m="$mac" 'index(tolower($0), m) && $1 ~ /^[0-9]/ {print $1; exit}')
  if [ -z "$found" ]; then
    # second round: neigh entries may still be filling in
    sleep 2
    found=$(ip neigh show 2>/dev/null | awk -v m="$mac" 'index(tolower($0), m) && $1 ~ /^[0-9]/ {print $1; exit}')
  fi
  if [ -z "$found" ]; then
    log "FATAL: DUT_MAC $DUT_MAC not found on $DUT_NET -- DUT down, renamed, or off-segment"
    return 1
  fi
  if [ "$found" != "$DUT_IP" ]; then
    log "DUT_IP resolved by MAC: $DUT_IP -> $found (DHCP drift)"
  fi
  DUT_IP=$found
  return 0
}

power_is_off() {
  bmc_ipmi chassis status 2>/dev/null | grep -Eq "System Power[[:space:]]*:[[:space:]]*off"
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

# shut_down_os OS: clean shutdown via SSH, then wait for System Power: off.
# Fallback: forced chassis power off if the clean path does not reach off
# within SHUTDOWN_TIMEOUT (hung OS, dead SSH, ...).
# rc 0 = power is off (clean or forced) | 1 = even the forced off timed out
shut_down_os() {
  local os=$1 t0 deadline
  t0=$(date +%s); deadline=$((t0 + SHUTDOWN_TIMEOUT))
  log "clean shutdown: sending shutdown to $os (budget ${SHUTDOWN_TIMEOUT}s)"
  if [ "$os" = "windows" ]; then
    ssh_fire "$WIN_USER" "$WIN_PASS" "shutdown /s /t 0 /f"
  else
    # Ubuntu: shutdown needs root. Try passwordless sudo first; otherwise
    # feed the password through sudo -S (backtick in the password is safe:
    # the command travels as one ssh argv element, quoted for the remote shell).
    if "$PY3" "$SCRIPT_DIR/ssh_cmd.py" "$UBU_USER" "$UBU_PASS" "$DUT_IP" \
        "sudo -n true && echo SUDONOK77" "SUDONOK77" 10 2>/dev/null | grep -q "SUDONOK77"; then
      log "clean shutdown: ubuntu dqa has passwordless sudo"
      ssh_fire "$UBU_USER" "$UBU_PASS" "sudo shutdown -h now"
    else
      log "clean shutdown: ubuntu dqa needs sudo password"
      ssh_fire "$UBU_USER" "$UBU_PASS" "echo '$UBU_PASS' | sudo -S shutdown -h now"
    fi
  fi
  local forced=0
  while :; do
    if power_is_off; then
      if [ $forced -eq 1 ]; then log "clean shutdown: forced off confirmed"; fi
      log "clean shutdown: System Power off after $(( $(date +%s) - t0 ))s"
      return 0
    fi
    if [ "$(date +%s)" -ge $deadline ] && [ $forced -eq 0 ]; then
      log "WARN: clean shutdown did not reach off within ${SHUTDOWN_TIMEOUT}s (SSH dead or OS hung) -- forcing chassis power off"
      bmc_ipmi chassis power off >/dev/null 2>&1
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

# identify_os TARGET -> sets IDENT_OS/IDENT_HOST/IDENT_EVIDENCE
# (IDENT_OS empty = identification failed)
# After a fresh boot the OS SSH daemon may come up well after the first
# ping (field observation: Ubuntu ping UP, port 22 dead at +15..31s,
# up by +5min). So probe in retry rounds until the budget is exhausted.
identify_os() {
  local target=$1 win_host="" ubu_host="" attempt=0 t0 deadline wr ur saved_pt
  t0=$(date +%s)
  deadline=$((t0 + ${ID_PROBE_BUDGET:-240}))
  IDENT_OS=""; IDENT_HOST=""
  if [ -n "$CUR_CLEAN" ] && [ -f "$CUR_CLEAN" ] && grep -qa "EFI stub" "$CUR_CLEAN" 2>/dev/null; then
    IDENT_EVIDENCE="SOL stream shows 'EFI stub' (Ubuntu kernel)"
  else
    IDENT_EVIDENCE="no 'EFI stub' in SOL stream (Windows boots silent on serial)"
  fi
  saved_pt=$PROBE_TIMEOUT
  PROBE_TIMEOUT=15
  while :; do
    attempt=$((attempt+1))
    probe_one "$WIN_USER" "$WIN_PASS" windows
    wr=$PROBE_RC; win_host=$PROBE_HOST
    if [ $wr -eq 0 ]; then
      ur=1
    else
      probe_one "$UBU_USER" "$UBU_PASS" ubuntu
      ur=$PROBE_RC; ubu_host=$PROBE_HOST
    fi
    log "identify attempt $attempt: windows rc=$wr host='$win_host' | ubuntu rc=$ur host='${ubu_host:-}'"
    if [ $wr -eq 0 ] && [ $ur -ne 0 ]; then
      IDENT_OS="windows"; IDENT_HOST=$win_host
      PROBE_TIMEOUT=$saved_pt
      return 0
    elif [ $ur -eq 0 ] && [ $wr -ne 0 ]; then
      IDENT_OS="ubuntu"; IDENT_HOST=$ubu_host
      PROBE_TIMEOUT=$saved_pt
      return 0
    elif [ $wr -eq 0 ] && [ $ur -eq 0 ]; then
      log "identify: BOTH probes succeeded -- ambiguous, treating as identification failure"
      PROBE_TIMEOUT=$saved_pt
      return 1
    fi
    if [ "$(date +%s)" -ge $deadline ]; then
      log "identify: budget ${ID_PROBE_BUDGET:-240}s exhausted -- no OS answer"
      PROBE_TIMEOUT=$saved_pt
      return 1
    fi
    log "identify: neither OS answered yet (attempt $attempt) -- retrying"
    sleep 3
  done
}

# collect_info OS CYCLE -> appends full output to the main log; rc 0 = marker seen
collect_info() {
  local os=$1 i=$2 out rc
  log "---- system info collect: $os (cycle $i) ----"
  if [ "$os" = "windows" ]; then
    out=$("$PY3" "$SCRIPT_DIR/ssh_cmd.py" "$WIN_USER" "$WIN_PASS" "$DUT_IP" \
      'hostname & ver & systeminfo & wmic diskdrive get model,size,serialnumber & wmic logicaldisk get caption,size,freespace & ipconfig /all & echo WINCOLLECTDONE77' \
      "WINCOLLECTDONE77" "$COLLECT_TIMEOUT")
    rc=$?
  else
    out=$("$PY3" "$SCRIPT_DIR/ssh_cmd.py" "$UBU_USER" "$UBU_PASS" "$DUT_IP" \
      'cat /etc/os-release; echo UB_OSREL_RC=$?; uname -a; echo UB_UNAME_RC=$?; lscpu; echo UB_LSCPU_RC=$?; free -h; echo UB_FREE_RC=$?; lsblk -f; echo UB_LSBLK_RC=$?; lspci; echo UB_LSPCI_RC=$?; ip -br addr; echo UB_IP_RC=$?; df -h; echo UB_DF_RC=$?; uptime; echo UB_UPTIME_RC=$?; echo UBCOLLECTDONE77' \
      "UBCOLLECTDONE77" "$COLLECT_TIMEOUT")
    rc=$?
  fi
  {
    echo "  [collect $os] ssh marker rc=$rc"
    printf '%s\n' "$out" | sed 's/^/  | /'
    if [ "$os" = "ubuntu" ]; then
      printf '%s\n' "$out" | grep -o 'UB_[A-Z]*_RC=[0-9]*' | sed 's/^/  | per-cmd: /'
    fi
  } >> "$LOG_FILE"
  return $rc
}

# ---------------- site-profile helpers (DESIGN-site-profiles.md) --------

# acquire_lock: exclusive lock for the cycle and --discover (setup) phases.
# The lock lives on $WORK_DIR (not the script dir) and dies with the
# process (flock on an fd). --check is read-only and never takes it.
acquire_lock() {
  if ! command -v flock >/dev/null 2>&1; then
    log "WARN: flock not available -- run lock skipped (be careful)"
    return 0
  fi
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log "FATAL: another os_flip run holds the lock ($LOCK_FILE) -- wait for it to finish"
    exit 1
  fi
  printf 'pid=%s host=%s since=%s cmd=%s\n' "$$" "$(hostname)" "$(date '+%F %T')" "$CMD" >&9
}

lock_is_held() {
  command -v flock >/dev/null 2>&1 || return 1
  ! flock -n "$LOCK_FILE" -c true 2>/dev/null
}

# resolve_profile: set PROFILE_FILE ("" = none). rc 0 found | 2 not found.
# Order: profiles/<SITE>.conf (runner local) > sites/<SITE>.conf (repo).
resolve_profile() {
  PROFILE_FILE=""
  [ -n "$SITE_NAME" ] || return 2
  local p
  p=$("$PY3" "$SCRIPT_DIR/sol_boot.py" resolve "$SITE_NAME" "$SCRIPT_DIR" 2>>"$LOG_FILE")
  if [ -n "$p" ]; then
    PROFILE_FILE=$p
    return 0
  fi
  return 2
}

# profile_gate: the identity gate. rc 0 ok | 2 missing/unparseable |
# 3 identity mismatch (site moved or the env is wrong -> re-run --discover).
profile_gate() {
  [ -n "$PROFILE_FILE" ] && [ -f "$PROFILE_FILE" ] || return 2
  "$PY3" "$SCRIPT_DIR/sol_boot.py" gate "$PROFILE_FILE" "${BMC_IP:-}" "${DUT_MAC:-}" "$SITE_NAME" >>"$LOG_FILE" 2>&1
  return $?
}

# wait_dut_ping: S8-style wait (discover safe exit -> normal boot). Budget
# BOOT_TIMEOUT; re-resolves DUT_IP by MAC once a minute (DHCP drift).
wait_dut_ping() {
  local t0 last_sweep=0
  t0=$(date +%s)
  while :; do
    if ping_ok; then
      log "wait_dut_ping: DUT ping UP ($DUT_IP)"
      return 0
    fi
    if [ -n "$DUT_MAC" ] && [ $(( $(date +%s) - t0 )) -ge 60 ] \
       && [ $(( $(date +%s) - last_sweep )) -ge 60 ]; then
      last_sweep=$(date +%s)
      resolve_dut || log "wait_dut_ping: DUT_MAC not found on the segment yet -- keep polling"
    fi
    if [ $(( $(date +%s) - t0 )) -ge "$BOOT_TIMEOUT" ]; then
      return 1
    fi
    sleep 3
  done
}

# ---------------- --check (read-only; design 5.1) ------------------------
# No power actions, no lock taken. exit 0 = ready to run a cycle.
check_mode() {
  # 1) env: the cycle's full config (its contract: exit 0 = cycle can run)
  local missing=""
  [ -n "$SITE_NAME" ] || missing="$missing SITE_NAME"
  [ -n "$DUT_MAC" ]   || missing="$missing DUT_MAC"
  [ -n "$BMC_IP" ]    || missing="$missing BMC_IP"
  [ -n "$BMC_PASS" ]  || missing="$missing BMC_PASS"
  [ -n "$WIN_PASS" ]  || missing="$missing WIN_PASS"
  [ -n "$UBU_PASS" ]  || missing="$missing UBU_PASS"
  if [ -n "$missing" ]; then
    log "--check: config missing:$missing (fill $ENV_FILE; see os_flip.env.example)"
    exit 2
  fi
  log "==== os_flip --check: site=$SITE_NAME ===="
  lock_is_held && log "--check: NOTE: another os_flip run holds the lock ($LOCK_FILE)"
  # 2) connectivity: DUT identity + ping, BMC
  if ! resolve_dut; then
    log "--check: FAIL: DUT (MAC $DUT_MAC) not found on $DUT_NET"
    exit 1
  fi
  local up=0 i
  for i in $(seq 1 "$PRE_PING_TRIES"); do
    if ping_ok; then up=1; break; fi
    log "--check: DUT ping try $i/$PRE_PING_TRIES down"
    sleep 2
  done
  if [ $up -ne 1 ]; then
    log "--check: FAIL: DUT $DUT_IP not pingable"
    exit 1
  fi
  log "--check: DUT ping UP ($DUT_IP)"
  if ! bmc_ipmi chassis status > "$LOG_DIR/check_bmc.txt" 2>&1; then
    sleep 3
    if ! bmc_ipmi chassis status > "$LOG_DIR/check_bmc.txt" 2>&1; then
      log "--check: FAIL: BMC $BMC_IP unreachable (ipmitool chassis status)"
      exit 1
    fi
  fi
  log "--check: BMC $BMC_IP reachable"
  # 3) profile resolution + identity gate
  if ! resolve_profile; then
    log "--check: FAIL: no profile for SITE_NAME '$SITE_NAME' (looked in profiles/ and sites/) -- first run on this DUT: ./os_flip.sh --discover"
    exit 2
  fi
  log "--check: profile: $PROFILE_FILE"
  local g=0
  profile_gate || g=$?
  if [ $g -eq 3 ]; then
    log "--check: FAIL: profile identity mismatch with the env (site moved or the env is wrong) -- re-run: ./os_flip.sh --discover"
    exit 3
  elif [ $g -ne 0 ]; then
    log "--check: FAIL: profile unreadable/unparseable: $PROFILE_FILE (see log above)"
    exit 2
  fi
  # 4) bidirectional SSH probe -> current OS
  probe_one "$WIN_USER" "$WIN_PASS" windows
  if [ $PROBE_RC -eq 0 ]; then
    CURRENT_OS="windows"
  else
    probe_one "$UBU_USER" "$UBU_PASS" ubuntu
    if [ $PROBE_RC -eq 0 ]; then
      CURRENT_OS="ubuntu"
    else
      CURRENT_OS="unknown (probe failed, last host='$PROBE_HOST')"
    fi
  fi
  log "--check: DUT currently on $CURRENT_OS (hostname=$PROBE_HOST)"
  # 5) readiness summary
  log "==================== READINESS SUMMARY ===================="
  log "site:        $SITE_NAME"
  log "profile:     $PROFILE_FILE"
  log "DUT:         $DUT_IP (MAC $DUT_MAC)"
  log "BMC:         $BMC_IP"
  log "current OS:  $CURRENT_OS"
  if [ "$CURRENT_OS" = "windows" ] || [ "$CURRENT_OS" = "ubuntu" ]; then
    log "READY: a cycle can run -> ./os_flip.sh <N>"
    exit 0
  else
    log "NOT READY: OS probe failed -- check the DUT SSH accounts (WIN_*/UBU_*)"
    exit 1
  fi
}

# ---------------- --discover (setup phase; design 5.2) -------------------
# ~5 minutes: precheck (S0) -> clean shutdown (S1) -> SOL discover (S2-S7,
# sol_boot.py) -> wait for boot + OS == S0 (S8). Machine returns to its
# original OS; the profile is written to profiles/<SITE>.conf.
discover_mode() {
  # env completeness (design 5.2 prerequisites)
  local missing=""
  [ -n "$SITE_NAME" ]  || missing="$missing SITE_NAME"
  [ -n "$LINUX_NAME" ] || missing="$missing LINUX_NAME"
  [ -n "$DUT_MAC" ]    || missing="$missing DUT_MAC"
  [ -n "$BMC_IP" ]     || missing="$missing BMC_IP"
  [ -n "$BMC_USER" ]   || missing="$missing BMC_USER"
  [ -n "$BMC_PASS" ]   || missing="$missing BMC_PASS"
  [ -n "$WIN_USER" ]   || missing="$missing WIN_USER"
  [ -n "$WIN_PASS" ]   || missing="$missing WIN_PASS"
  [ -n "$UBU_USER" ]   || missing="$missing UBU_USER"
  [ -n "$UBU_PASS" ]   || missing="$missing UBU_PASS"
  if [ -n "$missing" ]; then
    log "--discover: config missing:$missing (fill $ENV_FILE; see os_flip.env.example)"
    exit 2
  fi
  # Entry mode (schema v1.1): per-site in the profile, not an env var.
  # cold_on = clean shutdown -> bootdev latched while off -> COLD power on.
  # warm_reset = bootdev while running -> WARM power reset (required on
  # platforms that ignore the one-shot on cold boot, e.g. aic_1x/Tuca_0.09.0,
  # verified 2026-11-06; 2026-11-07 cold-on attempts timed out 3x).
  local pe="cold_on"
  # resolve_profile BEFORE reading power_entry: without it PROFILE_FILE is
  # "" and every site silently falls back to cold_on (verified bug
  # 2026-11-07: sites/aic_1x.conf said warm_reset, discover used cold_on).
  if resolve_profile; then
    pe=$(grep -E '^power_entry=' "$PROFILE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    [ -n "$pe" ] || pe="cold_on"
  else
    log "discover: no existing profile -- defaulting power_entry=cold_on (if this platform ignores the cold-boot one-shot, create sites/$SITE_NAME.conf with power_entry=warm_reset first)"
  fi
  case "$pe" in
    cold_on|warm_reset) ;;
    *) log "FATAL: discover: profile power_entry invalid: '$pe'"; exit 2 ;;
  esac
  log "discover: power_entry=$pe (source: ${PROFILE_FILE:-default})"
  acquire_lock
  log "==== os_flip --discover: site=$SITE_NAME linux_name=$LINUX_NAME ===="
  # S0: precheck (identity, ping, BMC, current OS)
  if ! precheck; then
    log "FATAL: discover S0 precheck failed -- NO power actions were taken"
    exit 1
  fi
  local os0=$CURRENT_OS
  log "discover S0: current OS recorded as $os0 (safe-restore baseline)"
  # S1: entry pre-stage per power_entry
  if [ "$pe" = "warm_reset" ]; then
    log "discover S1 skipped: warm_reset entry (machine stays on; sol_boot sets bootdev while running + WARM reset)"
  else
    # cold_on: clean shutdown + bootdev latch while off
    if ! shut_down_os "$os0"; then
      log "FATAL: discover S1 clean shutdown failed -- check machine state"
      exit 1
    fi
    if ! bmc_ipmi chassis bootdev bios option=efiboot >/dev/null 2>&1; then
      log "FATAL: discover S1: could not latch bootdev while power off"
      exit 1
    fi
    log "discover S1 done: DUT off, bootdev latched -- SOL discover (S2-S7)"
  fi
  local proff raw cln trc
  proff="$SCRIPT_DIR/profiles/$SITE_NAME.conf"
  mkdir -p "$SCRIPT_DIR/profiles"
  raw="$LOG_DIR/discover.sol.raw"; cln="$LOG_DIR/discover.sol.txt"; trc="$LOG_DIR/discover.navtrace.txt"
  "$PY3" "$SCRIPT_DIR/sol_boot.py" discover "$BMC_IP" "$BMC_USER" "$BMC_PASS" \
    "$raw" "$cln" "$trc" "$SETUP_TIMEOUT" "$BOOT_TIMEOUT" "$DUT_IP" "$ABORT_FILE" \
    "$proff" "$SITE_NAME" "$LINUX_NAME" "$DUT_MAC" "$pe" \
    2>&1 | tee "$LOG_DIR/discover.sol.log" | tee -a "$LOG_FILE" >/dev/null
  local src=${PIPESTATUS[0]}
  if [ -f "$trc" ] && [ -s "$trc" ]; then
    log "---- discover nav trace ----"
    sed 's/^/  /' "$trc" | tee -a "$LOG_FILE" >/dev/null
  fi
  case $src in
    0|2)
      # machine is back to a normal boot (Discard, or plain-reset fallback);
      # S8: wait for ping + verify the OS is the S0 baseline
      log "discover S8: waiting for the DUT ping (budget ${BOOT_TIMEOUT}s) ..."
      if wait_dut_ping; then
        identify_os "$os0"
        if [ -n "$IDENT_OS" ] && [ "$IDENT_OS" = "$os0" ]; then
          log "==== os_flip --discover DONE: setup complete, machine returned to $os0 ===="
          if [ $src -eq 0 ] && [ -f "$proff" ]; then
            log "profile written: $proff -- verify with: ./os_flip.sh --check"
          else
            log "NOTE: sol_boot exit $src -- see discover.sol.log for what happened"
          fi
          exit 0
        fi
        log "FATAL: discover S8: machine booted as ${IDENT_OS:-unknown}, expected $os0 -- check the machine"
        exit 1
      fi
      log "FATAL: discover S8: DUT ping not UP within ${BOOT_TIMEOUT}s -- check the machine"
      exit 1
      ;;
    7)
      log "!! DISCOVER FAILED AND THE MACHINE MAY BE SITTING IN UEFI SETUP -- PHYSICAL INTERVENTION REQUIRED"
      exit 1
      ;;
    *)
      log "FATAL: discover sol_boot.py exit $src (no profile written; see discover.sol.log)"
      exit 1
      ;;
  esac
}

# ---------------- required config (first run: discovery.sh fills it) -----
config_missing() {
  local m=""
  [ -n "${SITE_NAME:-}" ] || m="$m SITE_NAME"
  { [ -n "${DUT_IP:-}" ] || [ -n "${DUT_MAC:-}" ]; } || m="$m DUT-identity(DUT_IP|DUT_MAC)"
  [ -n "${BMC_IP:-}" ]  || m="$m BMC_IP"
  [ -n "${BMC_PASS:-}" ] || m="$m BMC_PASS"
  [ -n "${WIN_PASS:-}" ] || m="$m WIN_PASS"
  [ -n "${UBU_PASS:-}" ] || m="$m UBU_PASS"
  printf '%s' "$m"
}

# BIOS console-redirection gate (AMI Tuca boards, precheck stage). SOL UEFI
# navigation needs TER001 + TER002 + IPMI400 all on; OFF means banner-only
# SOL and a guaranteed setup-wait death (2026-11-07 field failure). The gate
# runs BEFORE any power action: OFF -> auto-repair via bios_redir.sh (nested
# PATCH + cold cycle + LIVE re-verify). ABSENT (non-AMI/Tuca boards) and
# REDFISH_DOWN are WARN-only: the gate must never block a site whose BMC does
# not expose these attributes. Sets BIOS_WAS_OFF=1 when a repair happened
# (main() uses it for the optional post-run restore).
bios_redir_gate() {
  local statef="$LOG_DIR/bios_redir_pre.txt" verdict
  BIOS_WAS_OFF=0
  if [ ! -f "$SCRIPT_DIR/bios_redir.sh" ] || [ -z "$BMC_IP" ]; then
    log "precheck: console-redirection gate skipped (no bios_redir.sh / no BMC_IP)"
    return 0
  fi
  DUT_IP="$DUT_IP" bash "$SCRIPT_DIR/bios_redir.sh" state > "$statef" 2>&1
  verdict=$(awk -F': ' '/^VERDICT: / {print $2}' "$statef" | head -1)
  case $verdict in
    ON)
      log "precheck: BIOS console redirection ON ($(grep -m1 '^ATTRS: ' "$statef" | sed 's/^ATTRS: //'))"
      ;;
    ABSENT)
      log "precheck: WARN: console-redirection attributes not exposed by this BMC (non-AMI/Tuca board?) -- gate skipped"
      ;;
    REDFISH_DOWN|"")
      log "precheck: WARN: Redfish unavailable on $BMC_IP (IPMI is up) -- gate skipped"
      ;;
    OFF)
      log "precheck: BIOS console redirection OFF ($(grep -m1 '^ATTRS: ' "$statef" | sed 's/^ATTRS: //')) -- SOL UEFI nav would be blind (2026-11-07 failure mode)"
      log "precheck: auto-repair: nested /Bios/SD PATCH + cold cycle + LIVE re-verify"
      if ! DUT_IP="$DUT_IP" bash "$SCRIPT_DIR/bios_redir.sh" fix 2>&1 | tee -a "$LOG_FILE"; then
        log "PRECHECK FAIL: console-redirection repair failed -- aborting (no further power actions)"
        FAIL_COUNT=$((FAIL_COUNT+1))
        return 1
      fi
      BIOS_WAS_OFF=1
      log "precheck: console redirection repaired and LIVE-verified ON (pre-run OFF state saved in bios_redir_pre.txt)"
      ;;
  esac
  return 0
}

precheck() {
  log "---- PRECHECK ----"
  # Identity first: with DUT_MAC set, sweep the segment and resolve the
  # CURRENT ip before pinging anything -- pinging the stale DUT_IP first
  # would falsely abort a machine that moved to a new IP (DHCP drift).
  if [ -n "$DUT_MAC" ] && ! resolve_dut; then
    log "PRECHECK FAIL: DUT identity check failed (DUT_MAC=$DUT_MAC)"
    FAIL_COUNT=$((FAIL_COUNT+1))
    return 1
  fi
  local up=0 i
  for i in $(seq 1 "$PRE_PING_TRIES"); do
    if ping_ok; then up=1; break; fi
    log "precheck: DUT ping try $i/$PRE_PING_TRIES down"
    sleep 2
  done
  if [ $up -ne 1 ]; then
    log "PRECHECK FAIL: DUT $DUT_IP not pingable"
    FAIL_COUNT=$((FAIL_COUNT+1))
    return 1
  fi
  log "precheck: DUT ping UP"
  local brc=1
  if bmc_ipmi chassis status > "$LOG_DIR/precheck_bmc.txt" 2>&1; then
    brc=0
  else
    log "precheck: BMC status try 1 failed -- retrying in 3s (RMCP+ jitter)"
    sleep 3
    bmc_ipmi chassis status > "$LOG_DIR/precheck_bmc.txt" 2>&1 && brc=0
  fi
  if [ $brc -ne 0 ]; then
    log "PRECHECK FAIL: BMC $BMC_IP unreachable (ipmitool chassis status rc=$brc)"
    FAIL_COUNT=$((FAIL_COUNT+1))
    return 1
  fi
  log "precheck: BMC reachable (status in precheck_bmc.txt)"
  if ! bios_redir_gate; then
    return 1
  fi
  if [ "${BIOS_WAS_OFF:-0}" = 1 ]; then
    # the repair's cold cycle rebooted the machine: wait for the OS to come
    # back BEFORE the SSH probe (a Windows boot can take several minutes).
    local rwaited=0
    while [ $rwaited -lt 360 ] && ! ping_ok; do
      sleep 15; rwaited=$((rwaited+15))
    done
    log "precheck: machine back after the repair cold cycle (ping UP, waited ${rwaited}s)"
  fi
  probe_one "$WIN_USER" "$WIN_PASS" windows
  if [ $PROBE_RC -eq 0 ]; then
    CURRENT_OS="windows"
  else
    probe_one "$UBU_USER" "$UBU_PASS" ubuntu
    if [ $PROBE_RC -eq 0 ]; then
      CURRENT_OS="ubuntu"
    else
      log "PRECHECK FAIL: neither OS SSH probe succeeded (last host='$PROBE_HOST')"
      FAIL_COUNT=$((FAIL_COUNT+1))
      return 1
    fi
  fi
  log "precheck: DUT currently on $CURRENT_OS (hostname=$PROBE_HOST)"
  return 0
}

record_row() {
  local i=$1 target=$2
  SUMMARY_ROWS="$SUMMARY_ROWS
  cycle $i: target=$target os=${CYCLE_OS:-?} result=${CYCLE_RESULT:-?} total=${CYCLE_DUR:-?}s boot=${BOOT_SECS:-?}s${CYCLE_FAIL_REASON:+ fail_reason=$CYCLE_FAIL_REASON}"
}

# run_cycle I TARGET -> 0 on PASS/PARTIAL, 1 on FAIL (caller aborts)
run_cycle() {
  local i=$1 target=$2
  CYCLE=$i
  local cnum raw cln trc sollog t0 t1 src res=0 ptarget
  cnum=$(printf '%02d' "$i")
  raw="$LOG_DIR/cycle${cnum}.sol.raw"
  cln="$LOG_DIR/cycle${cnum}.sol.txt"
  trc="$LOG_DIR/cycle${cnum}.navtrace.txt"
  sollog="$LOG_DIR/cycle${cnum}.sol.log"
  CUR_RAW=$raw; CUR_CLEAN=$cln; CUR_TRACE=$trc
  CYCLE_RESULT=""; CYCLE_OS=""; CYCLE_FAIL_REASON=""; CYCLE_DUR=""; BOOT_SECS=""
  t0=$(date +%s)
  log "==== CYCLE $i/$CYCLES  target=$target (prev OS: $CURRENT_OS) ===="

  # 1) power stage: the profile's power_entry is authoritative (schema v1.1);
  #    SHUTDOWN_MODE only breaks ties when the profile says cold_on:
  #    clean = SSH shutdown -> wait power off -> bootdev while off -> power on
  #    reset = legacy: bootdev while running + warm power reset (inside sol_boot)
  local pe="cold_on"
  if [ -n "$PROFILE_FILE" ] && [ -f "$PROFILE_FILE" ]; then
    pe=$(grep -E '^power_entry=' "$PROFILE_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    case "$pe" in
      cold_on|warm_reset) ;;
      *) log "FATAL: profile power_entry invalid: '$pe'"; exit 2 ;;
    esac
  fi
  local power_action="reset"
  if [ "$pe" = "warm_reset" ]; then
    log "cycle $i: profile power_entry=warm_reset -- legacy warm-reset entry (this platform ignores the one-shot on cold boot)"
  elif [ "$SHUTDOWN_MODE" = "clean" ]; then
    if ! shut_down_os "$CURRENT_OS"; then
      CYCLE_RESULT="FAIL"; CYCLE_OS="unknown"
      CYCLE_FAIL_REASON="clean shutdown failed: DUT never reached power off (forced off also timed out)"
      log "CYCLE $i FAIL: $CYCLE_FAIL_REASON"
      FAIL_COUNT=$((FAIL_COUNT+1))
      CYCLE_DUR=$(( $(date +%s) - t0 ))
      record_row "$i" "$target"
      return 1
    fi
    if bmc_ipmi chassis bootdev bios option=efiboot > /dev/null 2>&1; then
      log "clean shutdown: bootdev bios option=efiboot latched while power off"
    else
      CYCLE_RESULT="FAIL"; CYCLE_OS="unknown"
      CYCLE_FAIL_REASON="could not set chassis bootdev while power off (BMC error)"
      log "CYCLE $i FAIL: $CYCLE_FAIL_REASON"
      FAIL_COUNT=$((FAIL_COUNT+1))
      CYCLE_DUR=$(( $(date +%s) - t0 ))
      record_row "$i" "$target"
      return 1
    fi
    power_action="on"
  fi

  # the profile target key: 'ubuntu' (probe name) -> 'linux' (profile key)
  ptarget=$target
  [ "$target" = "ubuntu" ] && ptarget="linux"
  "$PY3" "$SCRIPT_DIR/sol_boot.py" cycle "$BMC_IP" "$BMC_USER" "$BMC_PASS" "$ptarget" \
    "$raw" "$cln" "$trc" "$SETUP_TIMEOUT" "$BOOT_TIMEOUT" "$DUT_IP" "$ABORT_FILE" \
    "$power_action" "$PROFILE_FILE" \
    2>&1 | tee "$sollog" | tee -a "$LOG_FILE" >/dev/null
  src=${PIPESTATUS[0]}

  if [ -f "$trc" ] && [ -s "$trc" ]; then
    log "---- nav trace (cycle $i, file cycle${cnum}.navtrace.txt) ----"
    sed 's/^/  /' "$trc" | tee -a "$LOG_FILE" >/dev/null
  fi
  if [ $src -ne 0 ]; then
    case $src in
      1) CYCLE_FAIL_REASON="no UEFI setup within ${SETUP_TIMEOUT}s (SOL evidence: cycle${cnum}.sol.txt)";;
      2) CYCLE_FAIL_REASON="nav verify failed -- no ENTER sent; safe exit done (plain reset to normal boot)";;
      3) CYCLE_FAIL_REASON="boot not confirmed: ping not UP within ${BOOT_TIMEOUT}s (SOL evidence: cycle${cnum}.sol.txt)";;
      4) CYCLE_FAIL_REASON="could not set chassis bootdev (BMC error)";;
      5) CYCLE_FAIL_REASON="chassis power reset failed (BMC error)";;
      6) CYCLE_FAIL_REASON="LAYOUT DRIFT: first item (item_2) mismatch -- profile stale (firmware update / UEFI reset?); safe exit done. Re-run: ./os_flip.sh --discover, then ./os_flip.sh 1";;
      *) CYCLE_FAIL_REASON="sol_boot.py unexpected exit $src (see cycle${cnum}.sol.log)";;
    esac
    CYCLE_RESULT="FAIL"; CYCLE_OS="unknown"
    FAIL_COUNT=$((FAIL_COUNT+1))
    CYCLE_DUR=$(( $(date +%s) - t0 ))
    log "CYCLE $i FAIL: $CYCLE_FAIL_REASON"
    record_row "$i" "$target"
    return 1
  fi

  # 2) identify the booted OS
  identify_os "$target"
  if [ -z "$IDENT_OS" ]; then
    CYCLE_RESULT="FAIL"; CYCLE_OS="unknown"
    CYCLE_FAIL_REASON="boot completed but OS identification failed ($IDENT_EVIDENCE)"
    log "CYCLE $i FAIL: $CYCLE_FAIL_REASON"
    FAIL_COUNT=$((FAIL_COUNT+1))
    CYCLE_DUR=$(( $(date +%s) - t0 ))
    record_row "$i" "$target"
    return 1
  fi
  if [ "$IDENT_OS" != "$target" ]; then
    CYCLE_RESULT="FAIL"; CYCLE_OS=$IDENT_OS
    CYCLE_FAIL_REASON="expected $target but booted OS identified as $IDENT_OS (host=$IDENT_HOST) -- persistent order may have been disturbed; machine left on $IDENT_OS"
    log "CYCLE $i FAIL: $CYCLE_FAIL_REASON"
    FAIL_COUNT=$((FAIL_COUNT+1))
    CYCLE_DUR=$(( $(date +%s) - t0 ))
    record_row "$i" "$target"
    return 1
  fi
  log "CYCLE $i identified: $IDENT_OS (host=$IDENT_HOST; $IDENT_EVIDENCE)"

  # 3) collect system info (failure here = PARTIAL, not abort)
  CYCLE_RESULT="PASS"
  if collect_info "$IDENT_OS" "$i"; then
    log "CYCLE $i collect: OK"
  else
    CYCLE_RESULT="PARTIAL"
    CYCLE_FAIL_REASON="switch+identify OK, system-info collect failed/timed out (output above is partial)"
    log "CYCLE $i PARTIAL: $CYCLE_FAIL_REASON"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi

  BOOT_SECS=$(grep -o 'reset_plus=[0-9.]*' "$CUR_TRACE" 2>/dev/null | head -1 | cut -d= -f2)
  t1=$(date +%s)
  CYCLE_DUR=$(( t1 - t0 ))
  CYCLE_OS=$IDENT_OS
  log "==== CYCLE $i done: result=$CYCLE_RESULT os=$IDENT_OS total=${CYCLE_DUR}s boot=${BOOT_SECS:-?}s ===="
  record_row "$i" "$target"
  CURRENT_OS=$IDENT_OS
  return 0
}

summary() {
  local counts
  counts=$(printf '%s\n' "$SUMMARY_ROWS" | grep -o 'result=[A-Z]*' | sort | uniq -c | tr '\n' ' ')
  {
    echo "==================== SUMMARY ===================="
    echo "run ts:         $TS"
    echo "site:           $SITE_NAME (profile: ${PROFILE_FILE:-none})"
    echo "cycles wanted:  $CYCLES"
    echo "result counts:  ${counts:-none}"
    echo "FAIL_COUNT:     $FAIL_COUNT (failed steps, incl. collection)"
    echo ""
    echo "per-cycle:"
    if [ -n "$SUMMARY_ROWS" ]; then printf '%s\n' "$SUMMARY_ROWS" | sed 's/^/  /'; else echo "  (none)"; fi
    echo ""
    echo "final booted OS:  $CURRENT_OS"
    echo "persistent order: UNCHANGED (one-shot overrides are consumed; nothing was saved in setup)"
    echo "no restore step performed; machine left on the last booted OS"
  } | tee -a "$LOG_FILE"
}

main() {
  local f i target res failed=0 ran=0 g
  for f in sol_boot.py ssh_cmd.py; do
    if [ ! -f "$SCRIPT_DIR/$f" ]; then
      log "FATAL: helper $f not found next to os_flip.sh (dir: $SCRIPT_DIR)"
      exit 1
    fi
  done
  log "==== os_flip start: site=$SITE_NAME cycles=$CYCLES DUT=${DUT_IP:-<by MAC $DUT_MAC>} BMC=$BMC_IP ===="
  log "runner: $(hostname) tz=$(date '+%Z %z') | log dir: $LOG_DIR"
  log "config: SETUP_TIMEOUT=$SETUP_TIMEOUT BOOT_TIMEOUT=$BOOT_TIMEOUT PROBE_TIMEOUT=$PROBE_TIMEOUT ID_PROBE_BUDGET=${ID_PROBE_BUDGET:-240} COLLECT_TIMEOUT=$COLLECT_TIMEOUT PRE_PING_TRIES=$PRE_PING_TRIES SHUTDOWN_MODE=$SHUTDOWN_MODE SHUTDOWN_TIMEOUT=$SHUTDOWN_TIMEOUT RESTORE_BIOS_STATE=$RESTORE_BIOS_STATE DUT_MAC=${DUT_MAC:-<none>} DUT_NET=$DUT_NET LINUX_NAME=${LINUX_NAME:-<none>}"
  # profile gate BEFORE the precheck: config-level refusals (no power
  # actions). design 5.3: profile missing -> exit 2 + --discover hint;
  # bmc_ip/dut_mac mismatch -> exit 3 (site moved or wrong env).
  if ! resolve_profile; then
    log "FATAL: no profile for SITE_NAME '$SITE_NAME' (looked in profiles/ and sites/) -- first run on this DUT: ./os_flip.sh --discover"
    exit 2
  fi
  log "profile: $PROFILE_FILE"
  g=0
  profile_gate || g=$?
  case $g in
    3) log "FATAL: profile identity mismatch with the env (site moved or the env is wrong) -- re-run: ./os_flip.sh --discover"; exit 3;;
    2) log "FATAL: profile unreadable/unparseable: $PROFILE_FILE (see log above)"; exit 2;;
  esac
  acquire_lock
  if ! precheck; then
    summary
    log "ABORT at precheck -- machine not in expected state; NO power/boot actions were taken"
    exit 1
  fi
  for i in $(seq 1 "$CYCLES"); do
    [ -f "$ABORT_FILE" ] && break
    ran=$((ran+1))
    if [ "$CURRENT_OS" = "windows" ]; then target="ubuntu"; else target="windows"; fi
    res=0
    run_cycle "$i" "$target" || res=1
    if [ $res -ne 0 ]; then
      failed=1
      log "!! cycle $i FAILED -- aborting whole run (design: abort on any cycle FAIL)"
      break
    fi
    sleep 5
  done
  summary
  if [ "${BIOS_WAS_OFF:-0}" = "1" ]; then
    if [ "${RESTORE_BIOS_STATE:-0}" = "1" ]; then
      log "==== console-redirection restore (RESTORE_BIOS_STATE=1; found OFF pre-run) ===="
      if DUT_IP="$DUT_IP" bash "$SCRIPT_DIR/bios_redir.sh" restore "$LOG_DIR/bios_redir_pre.txt" 2>&1 | tee -a "$LOG_FILE"; then
        log "console-redirection restored to the pre-run state (extra cold cycle consumed)"
      else
        log "!! console-redirection restore FAILED -- machine left with redirection ON (repair it before the next run)"
      fi
    else
      log "console-redirection left ON (found OFF pre-run; set RESTORE_BIOS_STATE=1 to restore the found state after a run)"
    fi
  fi
  log "==== os_flip end: machine left on $CURRENT_OS; persistent order unchanged ===="
  if [ $failed -ne 0 ] || [ $ran -ne "$CYCLES" ]; then
    exit 1
  fi
}

# ---------------- dispatch -----------------------------------------------
case $CMD in
  check)
    check_mode
    ;;
  discover)
    discover_mode
    ;;
  *)
    # cycle mode: config gate (with first-run discovery), then main()
    if [ -n "$(config_missing)" ]; then
      if [ -f "$SCRIPT_DIR/discovery.sh" ] && { [ -t 0 ] || [ -n "${OS_FLIP_DISCOVERY:-}" ]; }; then
        log "config incomplete$(config_missing) -- running first-run discovery"
        if bash "$SCRIPT_DIR/discovery.sh" --auto --log "$LOG_FILE"; then
          load_env_file
          if [ -n "$(config_missing)" ]; then
            log "FATAL: config still incomplete after discovery:$(config_missing)"
            exit 1
          fi
          log "discovery done -- config loaded from $ENV_FILE"
        else
          log "FATAL: discovery failed -- no test actions were taken"
          exit 1
        fi
      else
        log "FATAL: config missing:$(config_missing) -- run ./discovery.sh or fill $ENV_FILE (see os_flip.env.example); then set SITE_NAME and run ./os_flip.sh --discover on a new DUT"
        exit 1
      fi
    fi
    main
    ;;
esac
