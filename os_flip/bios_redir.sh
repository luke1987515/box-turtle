#!/usr/bin/env bash
# bios_redir.sh -- AMI (Aptio) Tuca-class BMC: BIOS console redirection
# (TER001 / TER002 / IPMI400) via Redfish. Standalone tool + the precheck
# gate helper used by os_flip.sh (bios_redir_gate).
#
# Why it exists: with console redirection OFF, SOL streams ONLY the session
# banner (zero BIOS bytes), and every UEFI-setup phase of os_flip dies at the
# setup-wait (2026-11-07 field failure: the machine sat in setup, SOL was
# blind, the run aborted). The gate checks the attributes BEFORE any power
# action, repairs them (nested PATCH + cold cycle + LIVE re-verify) when OFF,
# and os_flip.sh optionally restores the found state after the run
# (RESTORE_BIOS_STATE=1).
#
# The recipe (verified 2026-11-06 on aic_1x and 2026-11-08 on TUCANA; BMC
# firmware 1.01 and 1.06, registry Tuca0.0.90.0, SOL functionally verified):
#   * the PATCH body MUST be NESTED, the same shape as the GET response:
#       {"Attributes":{"TER001":true,"TER002":true,"IPMI400":"IPMI400Enabled"}}
#     a flat spec-standard body {"TER001":...} returns 400 PropertyUnknown
#     on this board class (flat masquerades as a "firmware bug" -- it was a
#     3-day misdiagnosis).
#   * If-Match = the /Bios/SD object's OWN @odata.etag (atomic GET -> PATCH in
#     the same shell; the /Bios etag is a different value -> 412; no header ->
#     428).
#   * after 204 the new values go LIVE only after a COLD cycle (off -> 15s ->
#     on); GET /Bios Attributes carry the full set ONLY while the host is ON
#     (absent while it is booting) -- the wait_live poller treats "attributes
#     not yet visible" as "still booting" and keeps polling.
#
# Usage:
#   bios_redir.sh state             report-only: prints ATTRS + VERDICT lines
#                                   (ON | OFF | ABSENT | REDFISH_DOWN), exit 0
#   bios_redir.sh fix               enable all three (nested PATCH, retry on
#                                   503/no-etag, cold cycle, LIVE re-verify).
#                                   exit 0 ok | 1 failed
#   bios_redir.sh restore FILE      write the values saved in a 'state' output
#                                   (the ATTRS: line) back, cold cycle,
#                                   re-verify. exit 0 ok | 1 failed
#
# Creds: BMC_IP / BMC_USER / BMC_PASS from the environment, else from the
# os_flip.env next to this script (strict KEY=VALUE parse, never sourced).
# Testable env: BIOS_REDIR_SETTLE (cold-cycle wait, 15), BIOS_REDIR_POLL
# (verify poll gap, 15), BIOS_REDIR_BUDGET (verify budget, 270), PY3.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PY3=${PY3:-python3}
ENV_FILE=${BIOS_REDIR_ENV:-$SCRIPT_DIR/os_flip.env}

load_env() {
  [ -f "$ENV_FILE" ] || return 0
  local line k v
  while IFS= read -r line; do
    case $line in ''|\#*) continue;; esac
    k=${line%%=*}; v=${line#*=}
    case $k in
      BMC_IP|BMC_USER|BMC_PASS)
        [ -n "${!k:-}" ] && continue
        export "$k=$v";;
    esac
  done < "$ENV_FILE"
  return 0
}
load_env
BMC_IP=${BMC_IP:-}
BMC_USER=${BMC_USER:-admin}
BMC_PASS=${BMC_PASS:-}
SETTLE=${BIOS_REDIR_SETTLE:-15}
POLL=${BIOS_REDIR_POLL:-15}
BUDGET=${BIOS_REDIR_BUDGET:-270}

rf() { # rf <redfish-path> -> JSON on stdout; rc = curl's rc
  curl -sk --max-time 20 -u "$BMC_USER:$BMC_PASS" "https://$BMC_IP/redfish/v1$1"
}

state() {
  local out parsed v
  if [ -z "$BMC_IP" ]; then
    echo "VERDICT: REDFISH_DOWN"; return 0
  fi
  if ! out=$(rf "/Systems/Self/Bios" 2>/dev/null); then
    echo "VERDICT: REDFISH_DOWN"; return 0
  fi
  parsed=$(printf '%s' "$out" | "$PY3" -c '
import json, sys
try:
    a = json.load(sys.stdin).get("Attributes", {})
except Exception:
    sys.exit(3)
keys = ("TER001", "TER002", "IPMI400")
if any(k not in a for k in keys):
    print("ABSENT")
    sys.exit(0)
vals = [a[k] for k in keys]
on = vals[0] is True and vals[1] is True and vals[2] == "IPMI400Enabled"
print("ON" if on else "OFF")
print("TER001=%s TER002=%s IPMI400=%s" % (vals[0], vals[1], vals[2]))
' 2>/dev/null)
  local prc=$?
  if [ $prc -ne 0 ] || [ -z "$parsed" ]; then
    echo "VERDICT: REDFISH_DOWN"; return 0
  fi
  v=$(head -1 <<<"$parsed")
  if [ "$v" = "ABSENT" ]; then
    echo "VERDICT: ABSENT"
    return 0
  fi
  echo "ATTRS: $(sed -n '2p' <<<"$parsed")"
  echo "VERDICT: $v"
  return 0
}

patch_attrs() { # patch_attrs '<json-attributes-object>' -> 0 on 204
  local attrs_json=$1 attempt etag code
  for attempt in 1 2 3 4 5; do
    etag=$(rf "/Systems/Self/Bios/SD" 2>/dev/null | "$PY3" -c '
import json, sys
try:
    print(json.load(sys.stdin).get("@odata.etag", ""))
except Exception:
    pass
' 2>/dev/null)
    if [ -z "$etag" ]; then
      echo "patch: try $attempt: no /Bios/SD etag (host in inventory?) -- waiting ${POLL}s"
      sleep "$POLL"
      continue
    fi
    code=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' \
        -u "$BMC_USER:$BMC_PASS" -X PATCH \
        -H 'Content-Type: application/json' -H "If-Match: $etag" \
        -d "{\"Attributes\":$attrs_json}" \
        "https://$BMC_IP/redfish/v1/Systems/Self/Bios/SD")
    echo "patch: try $attempt (etag=$etag) -> HTTP $code"
    if [ "$code" = "204" ]; then
      return 0
    fi
    sleep "$POLL"
  done
  echo "patch: FAILED after 5 tries (last code: ${code:-none})"
  return 1
}

cold_cycle() {
  echo "cold cycle: chassis power off"
  timeout 20 ipmitool -I lanplus -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" chassis power off
  sleep "$SETTLE"
  echo "cold cycle: chassis power on"
  timeout 20 ipmitool -I lanplus -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" chassis power on
}

wait_live() { # wait_live '<expected-json-attributes>' -> 0 when LIVE matches
  local exp=$1
  while [ "$(date +%s)" -lt "$(($(date +%s) + BUDGET))" ]; do
    local out
    out=$(rf "/Systems/Self/Bios" 2>/dev/null | "$PY3" -c '
import json, sys
exp = json.loads(sys.argv[1])
try:
    a = json.load(sys.stdin).get("Attributes", {})
except Exception:
    sys.exit(0)
if all(k in a and a[k] == v for k, v in exp.items()):
    print("YES")
' "$exp" 2>/dev/null)
    if [ "$out" = "YES" ]; then
      echo "LIVE verified: $(printf '%s' "$exp" | "$PY3" -c 'import json,sys; print(" ".join("%s=%s" % (k, v) for k, v in sorted(json.load(sys.stdin).items())))')"
      return 0
    fi
    sleep "$POLL"
  done
  echo "LIVE verify: ${BUDGET}s budget exhausted (host still booting, or the PATCH did not stick)"
  return 1
}

fix() {
  local ALL='{"TER001": true, "TER002": true, "IPMI400": "IPMI400Enabled"}'
  if [ -z "$BMC_IP" ]; then
    echo "fix: BMC_IP is empty"; return 1
  fi
  if ! patch_attrs "$ALL"; then
    return 1
  fi
  cold_cycle
  if wait_live "$ALL"; then
    echo "FIX_DONE ok=1"
    return 0
  fi
  echo "FIX_DONE ok=0"
  return 1
}

restore() {
  local f=${1:-}
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "restore: state file not found: ${f:-<none>}"; return 1
  fi
  local line exp
  line=$(grep -m1 '^ATTRS: ' "$f" | sed 's/^ATTRS: //')
  if [ -z "$line" ]; then
    echo "restore: no 'ATTRS:' line in $f (is it a 'state' output?)"; return 1
  fi
  exp=$(printf '%s' "$line" | "$PY3" -c '
import json, sys
d = {}
for t in sys.argv[1].split():
    k, v = t.split("=", 1)
    d[k] = (v == "True") if v in ("True", "False") else v
print(json.dumps(d))
' "$line" 2>/dev/null)
  if [ -z "$exp" ]; then
    echo "restore: cannot parse the saved ATTRS line: $line"; return 1
  fi
  if [ -z "$BMC_IP" ]; then
    echo "restore: BMC_IP is empty"; return 1
  fi
  if ! patch_attrs "$exp"; then
    return 1
  fi
  cold_cycle
  if wait_live "$exp"; then
    echo "RESTORE_DONE ok=1 (values: $line)"
    return 0
  fi
  echo "RESTORE_DONE ok=0"
  return 1
}

case ${1:-state} in
  state)   state;;
  fix)     fix;;
  restore) restore "${2:-}";;
  *)
    echo "usage: $0 state | fix | restore <statefile>" >&2
    exit 2
    ;;
esac
