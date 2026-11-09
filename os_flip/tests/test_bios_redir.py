#!/usr/bin/env python3
"""Local (no hardware) verification for bios_redir.sh -- the Redfish
console-redirection gate tool (state / fix / restore) that os_flip.sh's
precheck calls (bios_redir_gate).

The BMC is emulated with PATH-shimmed fake `curl` and `ipmitool` executables
driven by a JSON state file:

    {"host": "on"|"off",
     "attrs":   {...},   # LIVE values (GET /Bios) -- visible only when host=on
     "pending": {...}}   # values after a 204 PATCH (GET /Bios/SD)

`chassis power off` -> host=off; `chassis power on` -> host=on AND
attrs=pending (the AMI cold-cycle apply semantics). The fake curl rejects a
FLAT PATCH body (no "Attributes" wrapper) exactly like the real board class.

Run:   python3 tests/test_bios_redir.py     (from the os_flip/ dir)
Exit:  0 = all pass | 1 = failures
Needs: bash + python3 (no network, no hardware).
"""
import json
import os
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

FAILS = []


def check(name, fn):
    try:
        fn()
        print("ok    %s" % name)
    except AssertionError as e:
        FAILS.append(name)
        print("FAIL  %s: %s" % (name, e))
    except Exception as e:
        FAILS.append(name)
        print("ERROR %s: %r" % (name, e))


ON = {"TER001": True, "TER002": True, "IPMI400": "IPMI400Enabled"}
OFF = {"TER001": False, "TER002": False, "IPMI400": "IPMI400Disabled"}
PARTIAL = {"TER001": True, "TER002": False, "IPMI400": "IPMI400Disabled"}

FAKE_CURL = r'''#!/usr/bin/env bash
STATE="$FAKE_STATE"; LOG="$FAKE_LOG"
url=""; patch=0; body=""; prev=""
for a in "$@"; do
  if [ "$prev" = "-d" ]; then body="$a"; fi
  if [ "$prev" = "-X" ] && [ "$a" = "PATCH" ]; then patch=1; fi
  case "$a" in http*) url="$a";; esac
  prev="$a"
done
if [ "${FAKE_MODE:-}" = "down" ]; then
  echo "curl: (7) Failed to connect to $url" >&2
  exit 6
fi
st=$(cat "$STATE")
if [ "$patch" = 1 ]; then
  printf 'PATCH url=%s body=%s\n' "$url" "$body" >> "$LOG"
  printf '%s' "$st" | python3 -c '
import json, sys
st = json.load(sys.stdin)
body = json.loads(sys.argv[1])
if "Attributes" not in body:
    sys.stderr.write("flat body: the board class rejects this shape\n")
    sys.exit(42)
st["pending"].update(body["Attributes"])
print(json.dumps(st))
' "$body" > "$STATE.new" || { echo 400; exit 0; }
  mv "$STATE.new" "$STATE"
  echo 204
  exit 0
fi
case "$url" in
  */Bios/SD)
    printf '%s' "$st" | python3 -c '
import json, sys
st = json.load(sys.stdin)
print(json.dumps({"@odata.etag": "\"1794123456\"",
                  "Attributes": st.get("pending", {})}))
';;
  */Bios)
    printf '%s' "$st" | python3 -c '
import json, sys
st = json.load(sys.stdin)
print(json.dumps({"Attributes": st["attrs"] if st.get("host") == "on" else {}}))
';;
  *)
    echo '{}';;
esac
'''

FAKE_IPMITOOL = r'''#!/usr/bin/env bash
printf 'ipmitool %s\n' "$*" >> "$FAKE_LOG"
case "$*" in
  *"chassis power off"*)
    python3 -c '
import json, os
p = os.environ["FAKE_STATE"]
st = json.load(open(p)); st["host"] = "off"
json.dump(st, open(p, "w"))
'
    echo "Chassis Power Control: Down/Off";;
  *"chassis power on"*)
    python3 -c '
import json, os
p = os.environ["FAKE_STATE"]
st = json.load(open(p))
st["attrs"] = dict(st.get("pending") or st.get("attrs") or {})
st["host"] = "on"
json.dump(st, open(p, "w"))
'
    echo "Chassis Power Control: Up/On";;
  *"chassis status"*)
    python3 -c '
import json, os
st = json.load(open(os.environ["FAKE_STATE"]))
print("System Power : %s" % ("on" if st.get("host") == "on" else "off"))
';;
  *)
    echo "ok";;
esac
'''

FAKE_SSH_CMD = r'''#!/usr/bin/env python3
import json, os, sys
mode = os.environ.get("FAKE_SSH_MODE", "fail")
cmd = sys.argv[4] if len(sys.argv) > 4 else ""
if mode == "fail":
    sys.exit(3)  # spawn-error path (rf_ssh_fire rc 1)
if "SUDONOK77" in cmd:
    sys.exit(0)  # no marker -> passwordless-sudo probe fails
if "shutdown" in cmd:
    p = os.environ["FAKE_STATE"]
    st = json.load(open(p))
    st["host"] = "off"  # the OS honors the shutdown command
    json.dump(st, open(p, "w"))
    print("sent")
sys.exit(0)
'''


class FakeBMC:
    def __init__(self, attrs, host="on", mode="", ssh=None):
        self.tmp = tempfile.TemporaryDirectory()
        self.statef = os.path.join(self.tmp.name, "state.json")
        self.logf = os.path.join(self.tmp.name, "calls.log")
        with open(self.statef, "w") as fh:
            json.dump({"host": host, "attrs": attrs, "pending": {}}, fh)
        open(self.logf, "w").close()
        fake = os.path.join(self.tmp.name, "bin")
        os.makedirs(fake)
        for name, body in (("curl", FAKE_CURL), ("ipmitool", FAKE_IPMITOOL)):
            p = os.path.join(fake, name)
            with open(p, "w", newline="\n") as fh:
                fh.write(body)
            os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
        self.sshf = None
        if ssh:
            self.sshf = os.path.join(fake, "ssh_cmd.py")
            with open(self.sshf, "w", newline="\n") as fh:
                fh.write(FAKE_SSH_CMD)
            os.chmod(self.sshf, os.stat(self.sshf).st_mode
                     | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
        self.env = dict(os.environ)
        self.env.update({
            "PATH": fake + os.pathsep + os.environ["PATH"],
            "FAKE_STATE": self.statef,
            "FAKE_LOG": self.logf,
            "FAKE_MODE": mode,
            "BMC_IP": "127.0.0.1",
            "BMC_USER": "admin",
            "BMC_PASS": "testpass",
            "BIOS_REDIR_SETTLE": "0",
            "BIOS_REDIR_POLL": "1",
            "BIOS_REDIR_BUDGET": "30",
            "BIOS_REDIR_ENV": "/nonexistent-env",
        })
        if ssh:
            # graceful-off path becomes exercisable: DUT + creds present,
            # ssh_cmd.py replaced by the fake, minimal grace windows
            self.env.update({
                "BIOS_REDIR_SSH_CMD": self.sshf,
                "FAKE_SSH_MODE": ssh,
                "DUT_IP": "127.0.0.1",
                "WIN_USER": "win", "WIN_PASS": "wp",
                "UBU_USER": "ubu", "UBU_PASS": "up",
                "BIOS_REDIR_OS_GRACE": "1",
                "BIOS_REDIR_POWER_POLL": "1",
                "BIOS_REDIR_SHUTDOWN_BUDGET": "10",
            })

    def run(self, *args, timeout=90):
        r = subprocess.run(["bash", os.path.join(ROOT, "bios_redir.sh")] + list(args),
                           capture_output=True, text=True, timeout=timeout, env=self.env)
        return r.returncode, r.stdout, r.stderr

    def state(self):
        return json.load(open(self.statef))

    def calls(self):
        return open(self.logf).read()

    def cleanup(self):
        self.tmp.cleanup()


# ---------------- 1. state: the four verdicts ----------------

def t_state_on():
    b = FakeBMC(dict(ON))
    try:
        rc, out, err = b.run("state")
        assert rc == 0, (rc, out, err)
        assert "VERDICT: ON" in out, out
        assert "TER001=True TER002=True IPMI400=IPMI400Enabled" in out, out
    finally:
        b.cleanup()


def t_state_off():
    b = FakeBMC(dict(OFF))
    try:
        rc, out, err = b.run("state")
        assert rc == 0 and "VERDICT: OFF" in out, (rc, out, err)
        assert "TER001=False" in out, out
    finally:
        b.cleanup()


def t_state_partial_is_off():
    # the 2026-11-07 field state (TER001 alone on) is OFF for our purposes:
    # SOL was banner-only in exactly that state.
    b = FakeBMC(dict(PARTIAL))
    try:
        rc, out, err = b.run("state")
        assert rc == 0 and "VERDICT: OFF" in out, (rc, out, err)
    finally:
        b.cleanup()


def t_state_absent():
    b = FakeBMC({})
    try:
        rc, out, err = b.run("state")
        assert rc == 0 and "VERDICT: ABSENT" in out, (rc, out, err)
        assert "ATTRS:" not in out, out
    finally:
        b.cleanup()


def t_state_down():
    b = FakeBMC(dict(ON), mode="down")
    try:
        rc, out, err = b.run("state")
        assert rc == 0 and "VERDICT: REDFISH_DOWN" in out, (rc, out, err)
    finally:
        b.cleanup()


# ---------------- 2. fix: OFF -> ON (the 2026-11-08 recipe) ----------------

def t_fix_off_to_on():
    b = FakeBMC(dict(OFF))
    try:
        rc, out, err = b.run("fix")
        assert rc == 0, (rc, out, err)
        assert "FIX_DONE ok=1" in out, out
        # LIVE state is all-on and the machine is back on
        assert b.state()["attrs"] == ON, b.state()
        assert b.state()["host"] == "on", b.state()
        # the PATCH was NESTED, hit the SD object, and the cold cycle ran
        log = b.calls()
        patch_lines = [l for l in log.splitlines() if l.startswith("PATCH ")]
        assert len(patch_lines) == 1, log
        assert "/Bios/SD" in patch_lines[0], patch_lines[0]
        assert '"Attributes"' in patch_lines[0], patch_lines[0]
        ipm = [l for l in log.splitlines() if "ipmitool" in l]
        assert any("power off" in l for l in ipm) and any("power on" in l for l in ipm), log
        assert "power off" in log.splitlines()[log.splitlines().index(next(l for l in ipm if "power off" in l))]
        # off before on, in order
        offs = [i for i, l in enumerate(log.splitlines()) if "power off" in l]
        ons = [i for i, l in enumerate(log.splitlines()) if "power on" in l]
        assert offs and ons and offs[0] < ons[0], log
    finally:
        b.cleanup()


def t_fix_already_on_is_noop_patch():
    b = FakeBMC(dict(ON))
    try:
        rc, out, err = b.run("fix")
        assert rc == 0 and "FIX_DONE ok=1" in out, (rc, out, err)
        assert b.state()["attrs"] == ON, b.state()
    finally:
        b.cleanup()


def t_fix_rejects_flat_body():
    # the fake curl exits 42 on a flat body (like the board's 400). If
    # bios_redir.sh ever regressed to a flat body, the PATCH would not 204
    # and fix would fail the LIVE verify.
    b = FakeBMC(dict(OFF))
    try:
        # emulate a regression: patch the script copy? No -- instead assert
        # the emitted body shape directly from a normal fix (defense in depth
        # for t_fix_off_to_on): re-run and grep the recorded body.
        rc, out, err = b.run("fix")
        assert rc == 0, (rc, out, err)
        body = [l for l in b.calls().splitlines() if l.startswith("PATCH ")][0]
        assert body.split("body=", 1)[1].startswith('{"Attributes":'), body
    finally:
        b.cleanup()


# ---------------- 3. graceful off (cold cycle without hard cut) ------------

def t_fix_graceful_off():
    # the running-OS case: fake ssh honors the windows shutdown command, so
    # the cold cycle must reach off WITHOUT a chassis power off call.
    b = FakeBMC(dict(OFF), ssh="ok")
    try:
        rc, out, err = b.run("fix")
        assert rc == 0, (rc, out, err)
        assert "graceful off: windows attempt" in out, out
        assert "forced chassis power off" not in out, out
        log = b.calls()
        offs = [i for i, l in enumerate(log.splitlines()) if "power off" in l]
        assert offs == [], "a hard power off happened: %s" % log
        ons = [i for i, l in enumerate(log.splitlines()) if "power on" in l]
        assert ons, log
        assert b.state()["attrs"] == ON and b.state()["host"] == "on", b.state()
    finally:
        b.cleanup()


def t_fix_graceful_fallback_forced():
    # ssh spawn-fails (mode fail): every clean attempt dies -> the forced
    # chassis power off path must still complete the cycle and the fix.
    b = FakeBMC(dict(OFF), ssh="fail")
    try:
        rc, out, err = b.run("fix")
        assert rc == 0, (rc, out, err)
        assert "forced chassis power off" in out, out
        log = b.calls()
        offs = [i for i, l in enumerate(log.splitlines()) if "power off" in l]
        ons = [i for i, l in enumerate(log.splitlines()) if "power on" in l]
        assert offs and ons and offs[0] < ons[0], log
        assert b.state()["attrs"] == ON and b.state()["host"] == "on", b.state()
    finally:
        b.cleanup()


# ---------------- 4. restore: the found-state roundtrip --------------------

def t_restore_roundtrip():
    b = FakeBMC(dict(PARTIAL))
    try:
        # save the found state (what os_flip.sh's gate stores in the run dir)
        rc, out, err = b.run("state")
        assert rc == 0 and "VERDICT: OFF" in out, (rc, out, err)
        statefile = os.path.join(b.tmp.name, "pre.txt")
        with open(statefile, "w") as fh:
            fh.write(out)
        # repair (gate behavior)
        rc, out, err = b.run("fix")
        assert rc == 0 and b.state()["attrs"] == ON, (rc, out, b.state())
        # post-run restore (RESTORE_BIOS_STATE=1 behavior)
        rc, out, err = b.run("restore", statefile)
        assert rc == 0, (rc, out, err)
        assert "RESTORE_DONE ok=1" in out, out
        assert b.state()["attrs"] == PARTIAL, b.state()
        assert b.state()["host"] == "on", b.state()
    finally:
        b.cleanup()


def t_restore_bad_file():
    b = FakeBMC(dict(ON))
    try:
        bad = os.path.join(b.tmp.name, "bad.txt")
        with open(bad, "w") as fh:
            fh.write("nothing useful here\n")
        rc, out, err = b.run("restore", bad)
        assert rc == 1 and "ATTRS:" in out, (rc, out, err)
        rc, out, err = b.run("restore", os.path.join(b.tmp.name, "nope"))
        assert rc == 1, (rc, out, err)
    finally:
        b.cleanup()


# ---------------- 5. os_flip.sh wiring (tokens + syntax) -------------------

def t_osflip_wiring():
    for f in ("os_flip.sh", "bios_redir.sh"):
        r = subprocess.run(["bash", "-n", os.path.join(ROOT, f)],
                           capture_output=True, text=True)
        assert r.returncode == 0, (f, r.stderr)
    with open(os.path.join(ROOT, "os_flip.sh")) as fh:
        s = fh.read()
    for token in ("bios_redir_gate", "RESTORE_BIOS_STATE", "BIOS_WAS_OFF",
                  "bios_redir.sh", "console-redirection left ON"):
        assert token in s, "missing %r in os_flip.sh" % token
    # the gate passes the live (post-DHCP-drift) DUT_IP to the child tool
    assert 'DUT_IP="$DUT_IP" bash "$SCRIPT_DIR/bios_redir.sh"' in s, \
        "gate must forward the live DUT_IP to bios_redir.sh"
    with open(os.path.join(ROOT, "bios_redir.sh")) as fh:
        bs = fh.read()
    for token in ("rf_reach_off", "bmc_power_off_state", "rf_ssh_fire",
                  "BIOS_REDIR_CLEAN", "DUT_IP", "SUDONOK77"):
        assert token in bs, "missing %r in bios_redir.sh" % token
    # the gate is called inside precheck, and restore is gated on BIOS_WAS_OFF
    assert s.count("bios_redir_gate") >= 2, "gate defined but never called"
    assert "BIOS_REDIR" not in s.replace("RESTORE_BIOS_STATE", ""), \
        "os_flip.sh must not leak test-knob names"
    # env.example documents the knob
    with open(os.path.join(ROOT, "os_flip.env.example")) as fh:
        assert "RESTORE_BIOS_STATE" in fh.read()


def main():
    print("== os_flip bios_redir local verification ==")
    check("state verdict: ON", t_state_on)
    check("state verdict: OFF", t_state_off)
    check("state verdict: partial (TER001-only) = OFF", t_state_partial_is_off)
    check("state verdict: ABSENT (non-Tuca board)", t_state_absent)
    check("state verdict: REDFISH_DOWN", t_state_down)
    check("fix: OFF -> ON (nested PATCH + cold cycle + LIVE)", t_fix_off_to_on)
    check("fix: already-ON no-op still 204 + verify", t_fix_already_on_is_noop_patch)
    check("fix: emitted body is NESTED (no flat regression)", t_fix_rejects_flat_body)
    check("restore: found-state roundtrip (OFF -> ON -> back)", t_restore_roundtrip)
    check("restore: bad/missing state file -> rc 1", t_restore_bad_file)
    check("fix: graceful off (no hard cut when ssh shutdown works)", t_fix_graceful_off)
    check("fix: graceful fallback (ssh dead -> forced off, still ok)", t_fix_graceful_fallback_forced)
    check("os_flip.sh wiring (tokens + bash -n + env.example)", t_osflip_wiring)
    print()
    if FAILS:
        print("FAILED: %d/%d -> %s" % (len(FAILS), 13, ", ".join(FAILS)))
        return 1
    print("ALL PASS (13/13)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
