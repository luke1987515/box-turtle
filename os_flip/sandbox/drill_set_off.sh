#!/usr/bin/env bash
# drill_set_off.sh -- TUCANA gate drill, phase 1: REPRODUCE the 2026-11-07
# field state. Set BIOS console redirection OFF via the verified nested
# /Bios/SD PATCH recipe (flat body 400s on this board class), then a cold
# cycle (clean shutdown preferred) so the pending values go LIVE, and wait
# for the machine back on windows. Leaves: machine ON, redirection OFF.
#
# Run from the os_flip dir on 103:  bash drill_set_off.sh
# Exit: 0 = LIVE OFF confirmed + DUT back | 1 = any step failed
set -u
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR" || exit 1
PY3=${PY3:-python3}
ENV_FILE=$SCRIPT_DIR/os_flip.env
[ -f "$ENV_FILE" ] || { echo "drill: no $ENV_FILE"; exit 1; }

# strict parse (NEVER sourced: backticks in the passwords)
declare -A ENVV
while IFS= read -r line; do
  case $line in ''|\#*) continue;; esac
  k=${line%%=*}; v=${line#*=}
  case $k in BMC_IP|BMC_USER|BMC_PASS|WIN_USER|WIN_PASS|DUT_IP) ENVV[$k]=$v;; esac
done < "$ENV_FILE"
: "${ENVV[BMC_IP]:?BMC_IP missing}" "${ENVV[BMC_USER]:?BMC_USER missing}" \
  "${ENVV[BMC_PASS]:?BMC_PASS missing}" "${ENVV[DUT_IP]:?DUT_IP missing}"
BMC_IP=${ENVV[BMC_IP]}; BMC_USER=${ENVV[BMC_USER]}; BMC_PASS=${ENVV[BMC_PASS]}
WIN_USER=${ENVV[WIN_USER]:-}; WIN_PASS=${ENVV[WIN_PASS]:-}; DUT_IP=${ENVV[DUT_IP]}

ipmi() { timeout 20 ipmitool -I lanplus -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" "$@"; }
power_off() { ipmi chassis status 2>/dev/null | grep -Eq "System Power[[:space:]]*:[[:space:]]*off"; }

echo "==== drill phase 1: set BIOS console redirection OFF (reproduce 11-07) ===="
echo "---- pre-state (expect VERDICT: ON) ----"
bash bios_redir.sh state

# 1) nested PATCH OFF
etag=$(curl -sk -u "$BMC_USER:$BMC_PASS" \
  "https://$BMC_IP/redfish/v1/Systems/Self/Bios/SD" \
  | "$PY3" -c 'import json,sys
try: print(json.load(sys.stdin).get("@odata.etag",""))
except Exception: pass')
[ -n "$etag" ] || { echo "drill: FAIL -- no /Bios/SD etag"; exit 1; }
code=$(curl -sk -o /dev/null -w '%{http_code}' -u "$BMC_USER:$BMC_PASS" -X PATCH \
  -H 'Content-Type: application/json' -H "If-Match: $etag" \
  -d '{"Attributes":{"TER001":false,"TER002":false,"IPMI400":"IPMI400Disabled"}}' \
  "https://$BMC_IP/redfish/v1/Systems/Self/Bios/SD")
echo "drill: PATCH OFF (etag=$etag) -> HTTP $code"
[ "$code" = "204" ] || { echo "drill: FAIL -- PATCH did not 204"; exit 1; }

# 2) reach System Power: off (clean shutdown first; the machine is on windows)
if power_off; then
  echo "drill: already off"
else
  if [ -n "$WIN_USER" ] && [ -n "$WIN_PASS" ]; then
    echo "drill: clean shutdown via ssh (windows: $WIN_USER)"
    "$PY3" ssh_cmd.py "$WIN_USER" "$WIN_PASS" "$DUT_IP" "shutdown /s /t 0 /f" "-" 20 >/dev/null 2>&1
  else
    echo "drill: no WIN creds in env -- will force"
  fi
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 240 ] && ! power_off; do sleep 5; done
  if ! power_off; then
    echo "drill: WARN clean shutdown did not reach off in 240s -- forced chassis power off"
    ipmi chassis power off
    t0=$(date +%s)
    while [ $(( $(date +%s) - t0 )) -lt 30 ] && ! power_off; do sleep 5; done
  fi
fi
power_off || { echo "drill: FAIL -- DUT never reached power off"; exit 1; }
echo "drill: System Power off"

# 3) power on -- the cold cycle applies the pending OFF values
sleep 15
ipmi chassis power on
echo "drill: power on sent; waiting for LIVE OFF (budget 300s)"
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
  if bash bios_redir.sh state 2>/dev/null | grep -q "VERDICT: OFF"; then ok=1; break; fi
  sleep 15
done
[ $ok -eq 1 ] || { echo "drill: FAIL -- LIVE state never reached OFF"; bash bios_redir.sh state; exit 1; }
echo "drill: LIVE OFF confirmed: $(bash bios_redir.sh state 2>/dev/null | grep '^ATTRS')"

# 4) wait for the DUT back (windows boot takes a few minutes)
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt 420 ] && ! ping -c1 -W2 "$DUT_IP" >/dev/null 2>&1; do sleep 10; done
if ping -c1 -W2 "$DUT_IP" >/dev/null 2>&1; then
  echo "drill: DUT ping UP (waited $(( $(date +%s) - t0 ))s)"
else
  echo "drill: WARN DUT not pingable after 420s"
fi
echo "==== drill phase 1 done: machine ON (windows), console redirection OFF ===="
exit 0
