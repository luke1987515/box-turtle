#!/usr/bin/env bash
# discovery.sh -- first-run environment discovery for os_flip.sh
#
# Fills the missing site config (DUT identity, BMC, credentials) into
# ./os_flip.env (chmod 600, never committed). Resolution priority:
#   CLI environment > existing ./os_flip.env > this discovery
#
# Identity discovery modes:
#   1. Power-off fingerprint (when RELAY_OFF_CMD + RELAY_ON_CMD are set):
#      scan-1 (relay ON) -> relay OFF -> scan-2; the MAC diff = the machines
#      on this relay's power domain. Boards ship with a small block of
#      consecutive MACs (default: 3 per board, BLOCK_GAP=2). Within a block:
#      the BMC is the member whose IP answers IPMI with the public vendor-
#      default credentials; the DUT is the remaining member(s).
#   2. Manual (no relay, or the fingerprint finds nothing): ask for the DUT's
#      current IP, read its MAC from the ARP/neigh cache, then auto-search
#      the BMC among alive same-OUI MACs in the same block whose IP answers
#      IPMI with the vendor-default credentials.
#
# Edge cases:
#   E1  several boards disappeared  -> list them, user picks one
#   E2  nothing disappeared         -> fall back to manual mode
#   E3  BMC has independent power   -> the lone vanished MAC is matched to a
#       still-alive same-OUI neighbor in the same block; the neighbor that
#       passes the default-credential IPMI probe is the BMC, otherwise the
#       vanished MAC was the BMC and the neighbor is the DUT
#   E4  relay channel safety        -> only the two user-provided commands
#       are ever executed; nothing is guessed
#   E5  mixed L2 segments           -> DUT_NET (default: runner's /24) stays
#       overridable
#
# Usage:
#   ./discovery.sh --auto      # called by os_flip.sh: fill the gaps, write env
#   ./discovery.sh --dry-run   # read-only: sweep + board grouping, no power
#                              # cuts, no writes
#   ./discovery.sh --reauth    # forget saved config, run discovery from scratch
#   ./discovery.sh --log FILE  # also append output to FILE
#
# Requires: bash, ip, ping, ipmitool, python3 (on the runner).
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${OS_FLIP_ENV_FILE:-$SCRIPT_DIR/os_flip.env}"
LOG_FILE=""
AUTO=0; DRY=0; REAUTH=0
INTERACTIVE=0
[ -t 0 ] && INTERACTIVE=1
[ -n "${OS_FLIP_DISCOVERY:-}" ] && INTERACTIVE=1
while [ $# -gt 0 ]; do
  case $1 in
    --auto) AUTO=1; shift;;
    --dry-run) DRY=1; shift;;
    --reauth) REAUTH=1; shift;;
    --log) LOG_FILE=${2:-}; shift 2;;
    *) shift;;
  esac
done

log() {
  local line="[$(date '+%Y-%m-%d %H:%M:%S')] [discovery] $*"
  if [ -n "$LOG_FILE" ]; then echo "$line" | tee -a "$LOG_FILE"; else echo "$line"; fi
}

# account name conventions (editable during the prompts, Enter accepts):
BMC_USER=${BMC_USER:-admin}
WIN_USER=${WIN_USER:-Administrator}
UBU_USER=${UBU_USER:-dqa}
# public vendor-default BMC credentials -- used ONLY for the first trial:
BMC_DEFAULT_USER=${BMC_DEFAULT_USER:-admin}
BMC_DEFAULT_PASS=${BMC_DEFAULT_PASS:-admin}
# public vendor OUI prefixes (comma-separated) for the MAC sweep filter:
KNOWN_OUI=${KNOWN_OUI:-00:15:b2}
# one board = a block of consecutive MACs; 3 per board -> same-block gap <= 2:
BLOCK_GAP=${BLOCK_GAP:-2}
# site fields (normally empty on first run):
DUT_IP=${DUT_IP:-}
DUT_MAC=${DUT_MAC:-}
BMC_IP=${BMC_IP:-}
BMC_PASS=${BMC_PASS:-}
WIN_PASS=${WIN_PASS:-}
UBU_PASS=${UBU_PASS:-}
DUT_NET=${DUT_NET:-}
RELAY_OFF_CMD=${RELAY_OFF_CMD:-}
RELAY_ON_CMD=${RELAY_ON_CMD:-}

# load_env_file: fill only EMPTY variables from the env file (CLI wins).
# Strict KEY=VALUE parsing -- the file is never sourced/executed.
load_env_file() {
  [ -f "$ENV_FILE" ] || return 1
  local line k v
  while IFS= read -r line; do
    case $line in ''|\#*) continue;; esac
    k=${line%%=*}; v=${line#*=}
    case $k in
      DUT_IP|DUT_MAC|DUT_NET|BMC_IP|BMC_USER|BMC_PASS|WIN_USER|WIN_PASS|UBU_USER|UBU_PASS|KNOWN_OUI|RELAY_OFF_CMD|RELAY_ON_CMD|BMC_DEFAULT_USER|BMC_DEFAULT_PASS)
        [ -n "${!k:-}" ] && continue
        export "$k=$v";;
    esac
  done < "$ENV_FILE"
  return 0
}
if [ $REAUTH -eq 1 ]; then
  log "--reauth: removing $ENV_FILE"
  rm -f "$ENV_FILE"
  DUT_IP=""; DUT_MAC=""; BMC_IP=""; BMC_PASS=""; WIN_PASS=""; UBU_PASS=""; DUT_NET=""
else
  load_env_file
fi

# ---------------- helpers ----------------

# mac_sweep OUTFILE: parallel ping sweep of $DUT_NET, then read the kernel
# neigh cache; keep only MACs matching a KNOWN_OUI. Lines: "<ip> <mac>".
mac_sweep() {
  local base out pids=() x pat n
  base=${DUT_NET%%/*}
  out=$1
  : > "$out"
  log "sweeping $DUT_NET ..."
  for x in $(seq 1 254); do
    ping -c1 -W1 "${base%.*}.$x" >/dev/null 2>&1 & pids+=($!);
  done
  wait
  sleep 1
  pat=$(echo "$KNOWN_OUI" | tr ',' '|')
  ip neigh show 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="lladdr"){print $1, tolower($(i+1)); break}}' \
    | awk -v p="$pat" '
        NF >= 2 && $2 ~ /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/ {
          n = split($2, o, ":")
          if (n == 6 && (o[1]":"o[2]":"o[3] ~ "^(" p ")$")) print $1, $2
        }' \
    | sort -u > "$out"
  n=$(wc -l < "$out")
  log "sweep: $n known-OUI host(s)"
}

# mac_tail MAC -> numeric value of the last 3 octets (same OUI assumed)
mac_tail() {
  python3 -c 'import sys
m = sys.argv[1].lower().split(":")
print(int(m[3], 16) * 65536 + int(m[4], 16) * 256 + int(m[5], 16))' "$1" 2>/dev/null || echo ""
}

# ipmi_default_ok IP: rc 0 = answers IPMI with the public vendor defaults
ipmi_default_ok() {
  timeout 10 ipmitool -I lanplus -H "$1" -U "$BMC_DEFAULT_USER" -P "$BMC_DEFAULT_PASS" \
    chassis power status >/dev/null 2>&1
}

# port22 IP: rc 0 = TCP 22 open (bash /dev/tcp probe)
port22() {
  (exec 3<>"/dev/tcp/$1/22") 2>/dev/null && { exec 3>&-; return 0; } || return 1
}

# group MACs into same-board blocks (same OUI, consecutive tail, gap <= gap).
# input: newline MACs on stdin; output: one "mac,mac[,mac]" block per line.
# (data is handed to python via the environment -- a heredoc would steal
#  the pipe from python's stdin)
group_blocks() {
  local gap=$1 data
  data=$(cat)
  GB_GAP="$gap" GB_DATA="$data" python3 -c '
import os
gap = int(os.environ["GB_GAP"])
recs = []
for m in os.environ.get("GB_DATA", "").split():
    m = m.lower()
    parts = m.split(":")
    if len(parts) != 6:
        continue
    oui = ":".join(parts[:3])
    tail = int(parts[3], 16) * 65536 + int(parts[4], 16) * 256 + int(parts[5], 16)
    recs.append((oui, tail, m))
recs.sort()
groups, cur = [], []
for r in recs:
    if cur and r[0] == cur[-1][0] and r[1] - cur[-1][1] <= gap:
        cur.append(r)
    else:
        if cur:
            groups.append(cur)
        cur = [r]
if cur:
    groups.append(cur)
for g in groups:
    print(",".join(x[2] for x in g))
'
}

# classify_board GROUP_IPMACS: one board block; sets B_IP (BMC ip), B_MAC,
# D_IP (DUT ip), D_MAC. rc 0 = both identified, 1 = needs user input.
# input lines: "<ip> <mac>" (from the relay-ON sweep)
classify_board() {
  local lines=$1
  B_IP=""; B_MAC=""; D_IP=""; D_MAC=""
  local ip mac
  local dut_cand_ips=() dut_cand_macs=()
  while read -r ip mac; do
    [ -n "$ip" ] && [ -n "$mac" ] || continue
    if ipmi_default_ok "$ip"; then
      B_IP=$ip; B_MAC=$mac
      log "board: BMC identified by default-cred IPMI: $B_IP ($B_MAC)"
    else
      dut_cand_ips+=("$ip"); dut_cand_macs+=("$mac")
    fi
  done <<< "$lines"
  local n=${#dut_cand_ips[@]}
  if [ $n -eq 0 ]; then
    log "board: no DUT candidate in block (only BMC vanished?)"
    return 1
  fi
  if [ $n -eq 1 ]; then
    D_IP=${dut_cand_ips[0]}; D_MAC=${dut_cand_macs[0]}
    return 0
  fi
  # several non-BMC members: prefer the one with an open SSH port
  local i pick=""
  for i in "${!dut_cand_ips[@]}"; do
    if port22 "${dut_cand_ips[$i]}"; then pick=$i; break; fi
  done
  if [ -n "$pick" ]; then
    D_IP=${dut_cand_ips[$pick]}; D_MAC=${dut_cand_macs[$pick]}
    log "board: DUT picked by open SSH port: $D_IP ($D_MAC)"
    return 0
  fi
  log "board: $n DUT candidates, none with open port 22 -- user must pick"
  return 1
}

# e3_single_board LONE_IPMAC ALIVE_FILE: one MAC vanished (BMC has independent
# power, or only the DUT was cut). Matches it against still-alive same-OUI
# neighbors in the same block. Sets B_IP/B_MAC/D_IP/D_MAC. rc 0 on success.
e3_single_board() {
  local ipmac=$1 alive=$2
  local lip lmac t ltail
  lip=${ipmac%% *}; lmac=${ipmac##* }
  ltail=$(mac_tail "$lmac")
  local lo ui oui
  oui="${lmac:0:8}"
  # alive neighbors in the same block
  local neigh
  neigh=$(awk -v o="$oui" -v g="$BLOCK_GAP" -v t="$ltail" '
      function h2d(h,  i, v) { v = 0; for (i = 1; i <= length(h); i++) v = v * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1; return v } 
      {
        m = tolower($2); split(m, p, ":")
        if (p[1]":"p[2]":"p[3] != o) next
        tail = h2d(p[4])*65536 + h2d(p[5])*256 + h2d(p[6])
        if (tail - t <= g && t - tail <= g) print $1, m
      }' "$alive")
  B_IP=""; B_MAC=""; D_IP=""; D_MAC=""
  if [ -n "$neigh" ]; then
    local nip nmac okn=0
    while read -r nip nmac; do
      [ -n "$nip" ] || continue
      if ipmi_default_ok "$nip"; then
        B_IP=$nip; B_MAC=$nmac; D_IP=$lip; D_MAC=$lmac
        log "E3: vanished $lmac = DUT; alive neighbor $B_IP ($B_MAC) passed default-cred IPMI = BMC"
        return 0
      fi
      okn=$((okn+1))
    done <<< "$neigh"
    if [ $okn -gt 0 ]; then
      # vanished MAC must be the BMC; the alive neighbor is the DUT
      read -r D_IP D_MAC <<< "$neigh"
      B_IP=$lip; B_MAC=$lmac
      log "E3: vanished $lmac = BMC; alive neighbor $D_IP ($D_MAC) = DUT (default creds rejected on all alive neighbors)"
      return 0
    fi
  fi
  log "E3: no same-block alive neighbor for $lmac -- cannot complete the board"
  return 1
}

relay_fingerprint() {
  [ -n "${RELAY_OFF_CMD:-}" ] && [ -n "${RELAY_ON_CMD:-}" ] || return 2
  local gone
  # t1/t2 are deliberately GLOBAL: the RETURN trap fires in the caller's
  # scope, where function locals have already vanished (set -u would bite)
  t1=$(mktemp); t2=$(mktemp)
  trap 'rm -f "$t1" "$t2" "$t1.mac" "$t2.mac"' RETURN
  mac_sweep "$t1"
  log "cutting relay: bash -c \"$RELAY_OFF_CMD\" (a few seconds)"
  bash -c "$RELAY_OFF_CMD"
  sleep 6
  mac_sweep "$t2"
  awk '{print tolower($2)}' "$t1" | sort -u > "$t1.mac"
  awk '{print tolower($2)}' "$t2" | sort -u > "$t2.mac"
  gone=$(comm -23 "$t1.mac" "$t2.mac")
  if [ -z "$gone" ]; then
    log "fingerprint: no known-OUI MAC disappeared (relay maps to nothing here?) -- E2"
    return 4
  fi
  log "fingerprint: disappeared MACs:"
  printf '%s\n' "$gone" | sed 's/^/  - /'
  local groups
  groups=$(printf '%s\n' "$gone" | group_blocks "$BLOCK_GAP")
  local ngroups
  ngroups=$(printf '%s\n' "$groups" | grep -c .)
  local choose=""
  if [ "$ngroups" -gt 1 ]; then
    log "E1: $ngroups boards on this relay -- pick one:"
    local i
    i=0
    local -a glist=()
    while IFS= read -r g; do
      i=$((i+1))
      glist+=("$g")
      log "  [$i] $(echo "$g" | tr ',' ' ')"
    done <<< "$groups"
    local sel
    if [ $INTERACTIVE -eq 1 ]; then read -rp "board number: " sel
    else log "FATAL: multiple boards and stdin is not a tty"; return 1; fi
    sel=${sel//[^0-9]/}
    if [ -z "$sel" ] || [ "$sel" -lt 1 ] || [ "$sel" -gt "$ngroups" ]; then
      log "FATAL: bad board selection '$sel'"
      return 1
    fi
    choose=${glist[$((sel-1))]}
  else
    choose=$groups
  fi
  # ip:mac lines for the chosen board's MACs (from the relay-ON sweep)
  local members lines="" m
  for m in $(echo "$choose" | tr ',' ' '); do
    lines="${lines}$(awk -v mm="$m" '$2 == mm {print; exit}' "$t1")
"
  done
  if ! classify_board "$lines"; then
    # E3: board reduced to a single vanished MAC
    if [ "$(echo "$choose" | tr ',' ' ' | wc -w)" -eq 1 ]; then
      if e3_single_board "$(printf '%s' "$lines")" "$t2"; then :; else return 1; fi
    else
      log "FATAL: could not split BMC/DUT in the chosen board -- E1 rerun with user input expected"
      return 1
    fi
  fi
  [ -n "$D_IP" ] && [ -n "$D_MAC" ] || { log "FATAL: DUT not identified"; return 1; }
  if [ -z "$B_IP" ] && [ "$(echo "$choose" | tr ',' ' ' | wc -w)" -eq 1 ]; then
    # E3: the DUT was found but its BMC never left the neigh cache
    # (independent power) -- complete the board against the alive sweep
    e3_single_board "$(printf '%s' "$lines")" "$t2" || { log "FATAL: BMC side of the board not identified"; return 1; }
  fi
  [ -n "$B_IP" ] || { log "FATAL: BMC not identified in board"; return 1; }
  log "fingerprint result: DUT $D_IP ($D_MAC) | BMC $B_IP ($B_MAC)"
  log "restoring relay: bash -c \"$RELAY_ON_CMD\""
  bash -c "$RELAY_ON_CMD"
  # wait for the DUT to come back (cold boot), then refresh its IP
  log "waiting for DUT $D_IP ping UP (180s budget) ..."
  local t0 now
  t0=$(date +%s)
  while :; do
    now=$(date +%s)
    if [ $((now - t0)) -ge 180 ]; then
      log "WARN: DUT ping not UP within 180s (it may still be booting)"
      break
    fi
    if ping -c1 -W1 "$D_IP" >/dev/null 2>&1; then log "DUT ping UP"; break; fi
    sleep 3
  done
  local nmac nip
  nmac=$(echo "$D_MAC" | tr 'A-Z' 'a-z')
  nip=$(ip neigh show 2>/dev/null | awk -v m="$nmac" 'index(tolower($0), m) && $1 ~ /^[0-9]/ {print $1; exit}')
  if [ -n "$nip" ]; then
    [ "$nip" != "$D_IP" ] && log "DUT IP refreshed after boot: $D_IP -> $nip"
    D_IP=$nip
  fi
  DUT_MAC=$D_MAC; DUT_IP=$D_IP; BMC_IP=$B_IP
  return 0
}

manual_discovery() {
  # DUT identity
  if [ -z "${DUT_IP:-}" ] && [ -z "${DUT_MAC:-}" ]; then
    if [ $INTERACTIVE -eq 1 ]; then
      read -rp "DUT current IP? " DUT_IP
    else
      log "FATAL: no DUT identity and not interactive"; return 1
    fi
  fi
  local i mac=""
  if [ -z "${DUT_MAC:-}" ]; then
    for i in 1 2 3; do
      ping -c 2 -W 2 "$DUT_IP" >/dev/null 2>&1
      mac=$(ip neigh show "$DUT_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="lladdr"){print tolower($(i+1)); break}}' | head -1)
      [ -n "$mac" ] && break
      log "no neigh entry for $DUT_IP yet (retry $i/3)"
      sleep 2
    done
    if [ -z "$mac" ]; then
      log "FATAL: cannot resolve MAC for $DUT_IP (wrong IP / off-segment?)"
      return 1
    fi
    DUT_MAC=$mac
    log "DUT_MAC from ARP: $DUT_MAC (identity stored as MAC -- DHCP drift is transparent)"
  fi
  # BMC auto-search: alive same-OUI MACs in the same block, default-cred IPMI
  if [ -z "${BMC_IP:-}" ]; then
    local t
    t=$(mktemp)
    mac_sweep "$t"
    local doui dtail
    doui="${DUT_MAC:0:8}"
    dtail=$(mac_tail "$DUT_MAC")
    local cand
    for cand in $(awk -v d="${DUT_IP:-}" -v o="$doui" -v g="$BLOCK_GAP" -v dt="$dtail" '
        function h2d(h,  i, v) { v = 0; for (i = 1; i <= length(h); i++) v = v * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1; return v } 
        {
          m = tolower($2); split(m, p, ":")
          if (p[1]":"p[2]":"p[3] != o) next
          tail = h2d(p[4])*65536 + h2d(p[5])*256 + h2d(p[6])
          if (($1 != d) && (tail - dt <= g) && (dt - tail <= g)) print $1
        }' "$t" | sort -u); do
      if ipmi_default_ok "$cand"; then
        BMC_IP=$cand
        log "BMC auto-found (same-OUI block, vendor-default creds OK): $BMC_IP"
        if [ $INTERACTIVE -eq 1 ]; then
          local yn
          read -rp "accept $BMC_IP as BMC? [Y/n] " yn
          case $yn in [Nn]*) BMC_IP="";; esac
        fi
        break
      fi
    done
    rm -f "$t"
  fi
  if [ -z "${BMC_IP:-}" ]; then
    if [ $INTERACTIVE -eq 1 ]; then
      read -rp "BMC IP (auto-search found nothing)? " BMC_IP
    else
      log "FATAL: BMC not found and not interactive"; return 1
    fi
    if ! ipmi_default_ok "$BMC_IP"; then
      log "NOTE: $BMC_IP does not answer with vendor-default credentials -- you will be asked for the BMC password"
    fi
  fi
  return 0
}

ask_credentials() {
  [ $DRY -eq 1 ] && return 0
  if [ -z "${BMC_PASS:-}" ]; then
    if ipmi_default_ok "$BMC_IP"; then
      log "BMC credentials: vendor defaults accepted (public defaults, stored as such)"
      BMC_USER=$BMC_DEFAULT_USER; BMC_PASS=$BMC_DEFAULT_PASS
    else
      [ $INTERACTIVE -eq 1 ] || { log "FATAL: BMC defaults rejected and not interactive"; return 1; }
      local u
      read -rp "BMC user [$BMC_USER]: " u; [ -n "$u" ] && BMC_USER=$u
      read -rs -p "BMC password: " BMC_PASS; echo
    fi
  fi
  if [ -z "${WIN_PASS:-}" ]; then
    [ $INTERACTIVE -eq 1 ] || { log "FATAL: WIN_PASS missing and not interactive"; return 1; }
    local u
    read -rp "Windows user [$WIN_USER]: " u; [ -n "$u" ] && WIN_USER=$u
    read -rs -p "Windows password: " WIN_PASS; echo
  fi
  if [ -z "${UBU_PASS:-}" ]; then
    [ $INTERACTIVE -eq 1 ] || { log "FATAL: UBU_PASS missing and not interactive"; return 1; }
    local u
    read -rp "Ubuntu user [$UBU_USER]: " u; [ -n "$u" ] && UBU_USER=$u
    read -rs -p "Ubuntu password: " UBU_PASS; echo
  fi
  return 0
}

write_env() {
  if [ $DRY -eq 1 ]; then
    log "dry-run: not writing $ENV_FILE"
    return 0
  fi
  (
    umask 077
    {
      echo "# os_flip site config -- written by discovery.sh $(date '+%Y-%m-%d %H:%M:%S')"
      echo "# chmod 600; local-only (gitignored). CLI env vars override this file."
      for k in DUT_IP DUT_MAC DUT_NET BMC_IP BMC_USER BMC_PASS WIN_USER WIN_PASS \
               UBU_USER UBU_PASS KNOWN_OUI RELAY_OFF_CMD RELAY_ON_CMD; do
        [ -n "${!k:-}" ] && echo "$k=${!k}"
      done
    } > "$ENV_FILE"
  )
  chmod 600 "$ENV_FILE"
  log "config written to $ENV_FILE (chmod 600): DUT_IP=$DUT_IP DUT_MAC=$DUT_MAC BMC_IP=$BMC_IP (passwords not echoed)"
}

main() {
  # C0: scan range
  if [ -z "${DUT_NET:-}" ]; then
    local rip
    rip=$(ip -4 -o addr show 2>/dev/null | awk '$2 != "lo" {split($4,a,"/"); print a[1]; exit}')
    if [ -n "$rip" ]; then
      DUT_NET="${rip%.*}.0/24"
      log "scan range (auto from runner IP $rip): $DUT_NET"
    else
      log "FATAL: cannot detect the runner IP for the scan range (set DUT_NET)"
      exit 1
    fi
  else
    log "scan range: $DUT_NET"
  fi

  if [ $DRY -eq 1 ]; then
    log "DRY RUN: read-only sweep + board grouping (no power cut, no writes)"
    local t
    t=$(mktemp)
    mac_sweep "$t"
    log "live known-OUI hosts:"
    sed 's/^/  /' "$t"
    log "grouped into candidate boards (same OUI, MAC gap <= $BLOCK_GAP):"
    awk '{print $2}' "$t" | group_blocks "$BLOCK_GAP" | sed 's/^/  /'
    rm -f "$t"
    exit 0
  fi

  local need_identity=0
  [ -z "${DUT_IP:-}" ] && [ -z "${DUT_MAC:-}" ] && need_identity=1

  if [ $need_identity -eq 1 ] && [ -n "${RELAY_OFF_CMD:-}" ] && [ -n "${RELAY_ON_CMD:-}" ]; then
    log "relay fingerprint available (RELAY_OFF_CMD / RELAY_ON_CMD set)"
    relay_fingerprint
    case $? in
      0) log "fingerprint: board identified" ;;
      2) log "WARN: relay commands incomplete -- manual mode" ;;
      4) log "WARN: E2 fingerprint found nothing -- manual mode" ;;
      *) log "WARN: fingerprint error -- manual mode" ;;
    esac
  fi

  if [ -z "${DUT_IP:-}" ] && [ -z "${DUT_MAC:-}" ]; then
    log "manual discovery: DUT identity"
    manual_discovery || { log "FATAL: DUT identity discovery failed"; exit 1; }
  elif [ -z "${DUT_IP:-}" ]; then
    # MAC known (e.g. from fingerprint) but no IP: refresh from neigh
    local nmac nip
    nmac=$(echo "$DUT_MAC" | tr 'A-Z' 'a-z')
    nip=$(ip neigh show 2>/dev/null | awk -v m="$nmac" 'index(tolower($0), m) && $1 ~ /^[0-9]/ {print $1; exit}')
    if [ -n "$nip" ]; then
      DUT_IP=$nip
      log "DUT_IP resolved from MAC: $DUT_IP"
    fi
  fi

  if [ -z "${BMC_IP:-}" ]; then
    log "manual discovery: BMC"
    manual_discovery || { log "FATAL: BMC discovery failed"; exit 1; }
  fi

  ask_credentials || { log "FATAL: credentials incomplete -- nothing written"; exit 1; }
  write_env
  log "discovery complete"
}

main
