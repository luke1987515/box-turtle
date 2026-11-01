#!/usr/bin/env python3
"""sol_boot.py -- Boot Override one-shot OS switch via SOL pty (Aptio/AMI).

Provenance: designed & validated by luke1987515; AI-assisted development
(Hermes Agent by Nous Research; self-hosted Qwen3.8-27B). Verified on real
hardware 2026-11-01: 10/10 cycles PASS, persistent boot order unchanged.

Verified path (2026-10, reference dual-OS DUT):
  sol deactivate -> wait SOL_DEACT_WAIT (10s; the BMC SOL engine needs this
  gap before re-attach) -> chassis bootdev bios option=efiboot -> open SOL
  pty session -> wait SOL_PRE_RESET_WAIT (8s) -> chassis power reset (WARM;
  a cold boot ignores the one-shot on this platform) -> wait "Aptio Setup"
  -> RIGHT x7 (arrival: "Save Options" block on the Save & Exit tab) ->
  DOWN x9 (Windows Boot Manager entry) or DOWN x10 (Ubuntu entry) -> ENTER.

ENTER on a Boot Override entry answers with a ~24-byte screen clear
(\\x1b[2J \\x1b[1;1H, twice) = the BIOS handing off to boot. That clear is
NOT "no response": after it this script sends NOTHING and never issues an
abort/power reset (an abort reset after the handoff kills the target boot
-- a real failure mode verified 2026-10-28).

Boot confirmation = SOL stream + ping polling. SOL may be silent during
boot on this platform (even fully silent); ping is the ground truth.

Usage:
  sol_boot.py BMC_IP BMC_USER BMC_PASS TARGET RAW_FILE CLEAN_FILE TRACE_FILE
             SETUP_TIMEOUT BOOT_TIMEOUT DUT_IP ABORT_FLAG POWER_ACTION
             (POWER_ACTION: 'reset' = legacy warm reset | 'on' = machine is
             already off with bootdev latched, COLD power on)

Env (defaults are the verified values; shrunk only for sandbox testing):
  SOL_DEACT_WAIT=10  SOL_PRE_RESET_WAIT=8  SOL_PRE_POWERON_WAIT=3
  SOL_KEY_SETTLE=3.0  SOL_DOWN_SETTLE=4.0
  DUT_MAC/DUT_NET: when DUT_MAC set, the boot wait re-resolves the DUT IP
  by MAC if the DUT is silent for 30s (DHCP drift guard)

Exit codes:
  0 ok | 1 setup timeout | 2 nav fail (safe exit: SOL closed, plain power
  reset sent, normal boot waited) | 3 boot not confirmed | 4 bootdev set
  failed | 5 power reset failed
"""
import os
import pty
import tty
import time
import select
import signal
import subprocess
import sys
import re
import threading

UP = b"\x1b[A"
DOWN = b"\x1b[B"
RIGHT = b"\x1b[C"
ENTER = b"\x0d"
ESC = b"\x1b"

# Save & Exit tab: 11 selectable items, top to bottom (verified 2026-10-28,
# description panel checked item by item). ITEMS[i] = description-panel
# substring for the item highlighted after DOWN press i+1 (None = Boot
# Override entry rows, which have no description).
ITEMS = [
    "without saving any changes",                                        # item 2
    "Reset the system after saving the changes",                         # item 3
    "Reset system setup without saving any changes",                     # item 4
    "Save Changes done so far to any of the setup option",               # item 5
    "Discard Changes done so far",                                       # item 6
    "Restore/Load Default values for all the setup options",             # item 7
    "Save the changes done so far as User Defaults",                     # item 8
    "Restore the User Defaults to all the setup options",                # item 9
    None,                                                                 # item 10: Windows Boot Manager (P1: ...)
    None,                                                                 # item 11: Ubuntu (P1: ...)
]
TARGET_DOWNS = {"windows": 9, "ubuntu": 10}

CSI = re.compile(rb"\x1b\[[0-9;?]*[ -/]*[@-~]")
OSC = re.compile(rb"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)")
CTL = re.compile(rb"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def clean(b):
    s = CSI.sub(b"", b)
    s = OSC.sub(b"", s)
    s = CTL.sub(b"", s)
    return s


# ITEM_NAMES[i] = (row substring, negative substring) of the menu row that
# must be SGR-bold (the cursor row) after DOWN press i+1. The bold row is
# the cursor-position ground truth (verified against real Aptio frames,
# 2026-10-29: bold appears only on the highlighted item name); the
# description panel text is a secondary check.
ITEM_NAMES = [
    ("Discard Changes and Exit", None),                 # item 2
    ("Save Changes and Reset", None),                   # item 3
    ("Discard Changes and Reset", None),                # item 4
    ("Save Changes", "Save Changes and"),               # item 5 (not item 1/3)
    ("Discard Changes", "Discard Changes and"),         # item 6 (not item 2/4)
    ("Restore Defaults", None),                         # item 7
    ("Save as User Defaults", None),                    # item 8
    ("Restore User Defaults", None),                    # item 9
    ("Windows Boot Manager (P1:", None),                # item 10
    ("Ubuntu (P1:", None),                              # item 11
]


class Screen(object):
    """Mini terminal emulator over the SOL stream.

    Aptio partial redraws interleave old and new text in the raw byte
    stream (a wrapped description sentence spans grid lines and old line
    remnants survive in the same visual line), so navigation verify is
    done against this rendered screen, not the raw stream. Verified
    against real captures (2026-10 smoke run):
    SGR bold (\\x1b[1m) marks exactly the highlighted item row.
    """
    ROWS = 40
    COLS = 132

    def __init__(self):
        self.g = [[" "] * self.COLS for _ in range(self.ROWS)]
        self.b = [[False] * self.COLS for _ in range(self.ROWS)]
        self.r = 0
        self.c = 0
        self._bold = False
        self._csi = re.compile(rb"\x1b\[([0-9;?]*)([@-~])")

    def feed(self, data):
        i, n = 0, len(data)
        while i < n:
            ch = data[i]
            if ch == 0x1b:
                m = self._csi.match(data, i)
                if m:
                    params = m.group(1).decode("latin-1")
                    final = m.group(2)
                    nums = [int(x) for x in params.split(";") if x.isdigit()]
                    if final == b"m":
                        if not nums or 0 in nums:
                            self._bold = False
                        elif 1 in nums:
                            self._bold = True
                        i = m.end()
                        continue
                    if final in b"Hf":
                        self.r = max(0, min(
                            (nums[0] - 1) if nums and nums[0] else 0,
                            self.ROWS - 1))
                        self.c = max(0, min(
                            (nums[1] - 1) if len(nums) > 1 and nums[1] else 0,
                            self.COLS - 1))
                    elif final == b"A":
                        self.r = max(0, self.r - (nums[0] if nums else 1))
                    elif final == b"B":
                        self.r = min(self.ROWS - 1, self.r + (nums[0] if nums else 1))
                    elif final == b"C":
                        self.c = min(self.COLS - 1, self.c + (nums[0] if nums else 1))
                    elif final == b"D":
                        self.c = max(0, self.c - (nums[0] if nums else 1))
                    elif final == b"J":
                        if not nums or nums[0] in (0, 2):
                            for rr in range(self.r, self.ROWS):
                                for cc in range(0 if rr > self.r else self.c,
                                               self.COLS):
                                    self.g[rr][cc] = " "
                                    self.b[rr][cc] = False
                        if not nums or nums[0] == 1:
                            for rr in range(0, self.r + 1):
                                for cc in range(0 if rr < self.r else self.c,
                                               self.COLS):
                                    self.g[rr][cc] = " "
                                    self.b[rr][cc] = False
                    elif final == b"K":
                        if not nums or nums[0] == 0:
                            rng = range(self.c, self.COLS)
                        elif nums[0] == 1:
                            rng = range(0, self.c + 1)
                        elif nums[0] == 2:
                            rng = range(self.COLS)
                        else:
                            rng = range()
                        for cc in rng:
                            self.g[self.r][cc] = " "
                            self.b[self.r][cc] = False
                    i = m.end()
                    continue
                if data[i:i + 2] == b"\x1b]":
                    j = data.find(b"\x07", i)
                    j2 = data.find(b"\x1b\\", i)
                    js = [x for x in (j, j2) if x != -1]
                    i = (min(js) + 1) if js else i + 2
                    continue
                i += 1
                continue
            if ch == 0x0d:
                self.c = 0
                i += 1
                continue
            if ch == 0x0a:
                self.r = min(self.ROWS - 1, self.r + 1)
                i += 1
                continue
            if ch == 0x08:
                self.c = max(0, self.c - 1)
                i += 1
                continue
            if 0x20 <= ch < 0x7f:
                if 0 <= self.r < self.ROWS and 0 <= self.c < self.COLS:
                    self.g[self.r][self.c] = chr(ch)
                    self.b[self.r][self.c] = self._bold
            self.c += 1
            if self.c >= self.COLS:
                self.c = 0
                self.r = min(self.ROWS - 1, self.r + 1)
            i += 1

    def lines(self):
        return ["".join(row) for row in self.g]

    def text(self):
        return "\n".join(l.rstrip() for l in self.lines())

    def panel_text(self):
        """Right-hand description panel (grid columns 55..88, 1-based) of
        every row, joined. The BIOS writes the highlighted item's
        description here, wrapped (verified position: CUP 6;55 in real
        reference captures). Joining the panel column alone makes a wrapped
        sentence contiguous again -- the full screen text is useless for
        that because menu-column text interleaves between the fragments.
        """
        parts = []
        for line in self.lines():
            seg = line[54:88].replace("|", " ").strip()
            if seg:
                parts.append(seg)
        return " ".join(parts)

    def highlight_row(self):
        """Row (0-based) holding the longest SGR-bold run (>=8 chars).
        Row 0 (the title band) is bold on every frame and is excluded.
        Returns None when no bold row qualifies."""
        best, best_len = None, 7
        for rr in range(1, self.ROWS):
            run = cur = 0
            for cell in self.b[rr]:
                cur = cur + 1 if cell else 0
                if cur > run:
                    run = cur
            if run > best_len:
                best, best_len = rr, run
        return best


def log(msg):
    print("[%s] %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


def ping_up(host):
    try:
        p = subprocess.run(["ping", "-c", "1", "-W", "1", host],
                           capture_output=True, timeout=5)
        return p.returncode == 0
    except Exception:
        return False


def refresh_dut_ip(mac, net, tries=2):
    """Re-resolve the DUT IP from a live sweep + the kernel neigh cache,
    keyed on the MAC (DHCP drift guard; the DUT re-acquires its lease after
    every boot and the lease can move (observed on the reference DUT).
    Returns the new IP string or None. /24 only."""
    import ipaddress
    mac = (mac or "").lower()
    if not mac:
        return None
    try:
        addrs = [str(a) for a in ipaddress.ip_network(net).hosts()]
    except Exception:
        return None
    for attempt in range(tries):
        alive = {}

        def poke(a):
            try:
                r = subprocess.run(["ping", "-c", "1", "-W", "1", a],
                                   capture_output=True, timeout=4)
                if b"0% packet loss" in r.stdout:
                    alive[a] = True
            except Exception:
                pass

        ts = [threading.Thread(target=poke, args=(a,)) for a in addrs]
        [t.start() for t in ts]
        [t.join(6) for t in ts]
        if not alive:
            continue
        time.sleep(1.5)  # let kernel neigh entries fill in
        try:
            r = subprocess.run(["ip", "neigh", "show"],
                               capture_output=True, text=True, timeout=10)
            for line in r.stdout.splitlines():
                if mac in line.lower():
                    f = line.split()
                    if f and f[0] in alive:
                        return f[0]
        except Exception:
            pass
        time.sleep(2)
    return None


def wait_ping_up(host, timeout, interval=3.0, need=2, dut_mac=None, dut_net=None):
    """Poll ping until `need` consecutive UP; return wall time or None.
    If the DUT is silent for 30s and dut_mac is set, re-resolve the IP
    (mid-run DHCP drift)."""
    t_end = time.time() + timeout
    streak = 0
    last_refresh = 0.0
    t0 = time.time()
    while time.time() < t_end:
        if ping_up(host):
            streak += 1
            if streak >= need:
                return time.time()
        else:
            streak = 0
            if (dut_mac and time.time() - last_refresh >= 30
                    and time.time() - t0 >= 30):
                last_refresh = time.time()
                new = refresh_dut_ip(dut_mac, dut_net)
                if new and new != host:
                    log("DUT_IP drift detected: %s -> %s (MAC %s)"
                        % (host, new, dut_mac))
                    host = new
        time.sleep(interval)
    return None


def boot_capture(sol, dut_ip, t_reset, boot_to, abort_flag, trace, up_tail=15.0,
                 dut_mac=None, dut_net=None):
    """Stream SOL while polling ping; stop after ping UP + up_tail or timeout.
    Re-resolves dut_ip by MAC if the DUT is silent for 30s (DHCP drift).
    Returns (ok, t_up)."""
    t_end = time.time() + boot_to
    up_at = None
    streak = 0
    last_refresh = 0.0
    while True:
        if abort_flag is not None and os.path.exists(abort_flag):
            log("abort flag present -- stopping boot capture")
            break
        if time.time() >= t_end:
            break
        sol.read(2.0)
        if up_at is None:
            if ping_up(dut_ip):
                streak += 1
                if streak >= 2:
                    up_at = time.time()
                    log("ping UP at reset+%.0fs" % (up_at - t_reset))
            else:
                streak = 0
                if (dut_mac and time.time() - last_refresh >= 30
                        and time.time() - t_reset >= 30):
                    last_refresh = time.time()
                    new = refresh_dut_ip(dut_mac, dut_net)
                    if new and new != dut_ip:
                        log("DUT_IP drift detected: %s -> %s (MAC %s)"
                            % (dut_ip, new, dut_mac))
                        trace.append("IP_DRIFT %s -> %s" % (dut_ip, new))
                        dut_ip = new
        elif time.time() - up_at >= up_tail:
            break
    if b"EFI stub" in sol.stream:
        trace.append("EVIDENCE efi_stub=yes")
    else:
        trace.append("EVIDENCE efi_stub=no")
    if up_at is None:
        return False, None
    return True, up_at


class Sol:
    """SOL pty session (single session; open before the reset, keep it
    through the boot so the stream is one continuous capture)."""

    def __init__(self, bmc_ip, user, pw):
        self.bmc_ip = bmc_ip
        self.user = user
        self.pw = pw
        self.master = None
        self.proc = None
        self.stream = b""
        self.t0 = None
        self.screen = Screen()

    def ipmi(self, *args, timeout=30):
        cmd = ["ipmitool", "-I", "lanplus", "-H", self.bmc_ip,
               "-U", self.user, "-P", self.pw] + list(args)
        try:
            p = subprocess.run(cmd, capture_output=True, timeout=timeout)
            out = (p.stdout + p.stderr).decode("utf-8", "replace")
        except Exception as e:
            log("ipmi %s: EXCEPTION %s" % (" ".join(args), e))
            return 1, str(e)
        one = " ".join(out.split())
        log("ipmi %s rc=%d %s" % (" ".join(args), p.returncode, one[:150]))
        return p.returncode, out

    def deactivate(self):
        self.ipmi("sol", "deactivate")

    def open(self):
        m, s = pty.openpty()
        tty.setraw(s)
        cmd = ["ipmitool", "-I", "lanplus", "-H", self.bmc_ip,
               "-U", self.user, "-P", self.pw, "sol", "activate"]
        self.proc = subprocess.Popen(cmd, stdin=s, stdout=s, stderr=s)
        os.close(s)
        self.master = m
        self.t0 = time.time()

    def close(self):
        if self.proc is not None:
            try:
                self.proc.kill()
            except Exception:
                pass
            try:
                self.proc.wait(timeout=5)
            except Exception:
                pass
            self.proc = None
        if self.master is not None:
            try:
                os.close(self.master)
            except Exception:
                pass
            self.master = None
        self.ipmi("sol", "deactivate")

    def t(self):
        return 0.0 if self.t0 is None else time.time() - self.t0

    def read(self, dur):
        """Read the pty for dur seconds; append to stream; return new bytes."""
        buf = b""
        end = time.time() + dur
        while time.time() < end:
            if self.master is None:
                break
            r, _, _ = select.select([self.master], [], [], 0.25)
            if r:
                try:
                    d = os.read(self.master, 65536)
                except OSError:
                    break
                if not d:
                    break
                buf += d
            elif self.proc is not None and self.proc.poll() is not None:
                break
        self.stream += buf
        if buf:
            self.screen.feed(buf)
        return buf

    def wait_for(self, substr, timeout, abort_flag=None):
        """Keep reading until substr appears in the cumulative stream."""
        dl = substr.lower()
        t_end = time.time() + timeout
        while True:
            if dl in self.stream.lower():
                return True
            if abort_flag is not None and os.path.exists(abort_flag):
                log("abort flag present -- leaving wait early")
                return False
            if time.time() >= t_end:
                return False
            self.read(0.5)


def _check_text(screen, sub):
    """Substring against the RENDERED screen, whitespace-tolerant."""
    pat = r"\s+".join(re.escape(w) for w in sub.split())
    return re.search(pat, screen.text()) is not None


def _check_panel(screen, sub):
    """Substring against the description-panel column (wrapped sentences
    become contiguous when the panel rows are joined)."""
    pat = r"\s+".join(re.escape(w) for w in sub.split())
    return re.search(pat, screen.panel_text()) is not None


def _bold_run_text(screen, rr):
    """Text of the longest SGR-bold run on grid row rr (stripped)."""
    best, cur, start = "", 0, 0
    for cc, cell in enumerate(screen.b[rr]):
        if cell:
            if cur == 0:
                start = cc
            cur += 1
            if cur > len(best):
                best = "".join(screen.g[rr][start:cc + 1])
        else:
            cur = 0
    return best.strip()


def _check_highlight(screen, name, neg):
    """The SGR-bold run itself (the cursor item) must contain `name` and not
    `neg`. Deliberately NOT the whole grid line: the description panel on
    the same row can carry the previous item's text and would mask a
    drifted cursor (sandbox Case B, 2026-10-29)."""
    rr = screen.highlight_row()
    if rr is None:
        return False
    run = _bold_run_text(screen, rr)
    if name not in run:
        return False
    return neg is None or neg not in run


def send_key(sol, trace, key, name, settle, checks, abort_flag):
    """Send one key, read the settle window, log the diff, verify.

    checks = list of (label, kind, payload); ALL must pass.
      kind 'text' : payload = substring matched on the rendered screen
                    (whitespace-tolerant, handles wrapped desc sentences).
      kind 'hl'   : payload = (name, neg); the highlighted (SGR-bold) row
                    must contain name (and not neg).
    The rendered screen is the ground truth: BIOS partial redraws
    interleave old and new text in the raw stream, so stream-substring
    verify is unreliable (real-machine failure observed 2026-10-29).
    Returns True when the key was accepted AND all checks passed.
    """
    try:
        os.write(sol.master, key)
    except OSError as e:
        trace.append("t=%.1f key=%s WRITE FAILED %s" % (sol.t(), name, e))
        return False
    d = sol.read(settle)
    n = len(d)
    text = " ".join(clean(d).decode("utf-8", "replace").split())
    ok = n > 0
    vd = ""
    if checks:
        for label, kind, payload in checks:
            if kind == "text":
                passed = _check_text(sol.screen, payload)
            elif kind == "panel":
                passed = _check_panel(sol.screen, payload)
            elif kind == "hl":
                passed = _check_highlight(sol.screen, payload[0], payload[1])
            else:
                passed = False
            if passed:
                vd += " verify[%s]=OK" % label
            else:
                ok = False
                vd += " verify[%s]=MISSING" % label
    trace.append('t=%.1f key=%s +bytes=%d%s text="%s"'
                 % (sol.t(), name, n, vd, text[:160]))
    log("key=%s +bytes=%d%s" % (name, n, vd))
    return ok


def do_enter(sol, trace):
    """ENTER on the target entry = one-shot handoff to boot.
    Returns 'handoff' | 'dialog' (ESC'd) | 'unknown' | 'write_fail'."""
    try:
        os.write(sol.master, ENTER)
    except OSError as e:
        trace.append("t=%.1f key=ENTER WRITE FAILED %s" % (sol.t(), e))
        return "write_fail"
    sol.read(4.0)
    tail = sol.stream[-120:]
    text = " ".join(clean(tail).decode("utf-8", "replace").split())
    if b"\x1b[2J" in tail:
        trace.append('t=%.1f key=ENTER +bytes(handoff clear) text="%s"'
                     % (sol.t(), text[:80]))
        log("ENTER: handoff screen clear seen -- target boot starting; "
            "sending NOTHING further (no abort reset)")
        return "handoff"
    low = tail.lower()
    if any(k in low for k in (b"save", b"discard", b"restore")):
        trace.append('t=%.1f key=ENTER DIALOG opened text="%s"'
                     % (sol.t(), text[:120]))
        log("ENTER: side-effect dialog opened (landed on a non-entry item) "
            "-- ESC to cancel")
        try:
            os.write(sol.master, ESC)
        except OSError:
            pass
        sol.read(3.0)
        return "dialog"
    trace.append('t=%.1f key=ENTER NO CLEAR NO DIALOG text="%s"'
                 % (sol.t(), text[:120]))
    log("ENTER: unexpected response (no screen clear, no dialog)")
    return "unknown"


def nav_fail(sol, trace, why, boot_to, dut_ip):
    """Nav verify failed: do NOT send ENTER. Safe exit = close SOL + plain
    power reset (persistent order unchanged) + wait for normal boot."""
    log("NAV FAIL: %s" % why)
    trace.append("NAV_FAIL %s" % why)
    sol.close()
    rc, _ = sol.ipmi("chassis", "power", "reset")
    if rc != 0:
        log("NAV FAIL: safe-exit power reset FAILED -- check machine manually")
        return 2
    up_at = wait_ping_up(dut_ip, boot_to,
                         dut_mac=os.environ.get("DUT_MAC", ""),
                         dut_net=os.environ.get("DUT_NET", ""))
    if up_at:
        log("NAV FAIL: safe exit done, DUT ping UP "
            "(normal boot, persistent order unchanged)")
        trace.append("SAFE_EXIT done (DUT ping UP)")
    else:
        log("NAV FAIL: DUT ping NOT UP after reset within %.0fs "
            "-- check machine manually" % boot_to)
        trace.append("SAFE_EXIT ping NOT UP (check machine manually)")
    return 2


def main():
    if len(sys.argv) != 13:
        print(__doc__)
        sys.exit(2)
    (bmc_ip, bmc_user, bmc_pass, target, raw_f, clean_f, trace_f,
     setup_to, boot_to, dut_ip, abort_flag, power_action) = sys.argv[1:13]
    setup_to = float(setup_to)
    boot_to = float(boot_to)
    deact_wait = float(os.environ.get("SOL_DEACT_WAIT", "10"))
    pre_reset_wait = float(os.environ.get("SOL_PRE_RESET_WAIT", "8"))
    pre_poweron_wait = float(os.environ.get("SOL_PRE_POWERON_WAIT", "3"))
    settle_r = float(os.environ.get("SOL_KEY_SETTLE", "3.0"))
    settle_d = float(os.environ.get("SOL_DOWN_SETTLE", "4.0"))
    up_tail = float(os.environ.get("SOL_UP_TAIL", "15"))
    dut_mac = os.environ.get("DUT_MAC", "")
    dut_net = os.environ.get("DUT_NET", "")
    if target not in TARGET_DOWNS:
        log("FATAL: bad target %r (want one of %s)" % (target, sorted(TARGET_DOWNS)))
        sys.exit(2)
    if power_action not in ("on", "reset"):
        log("FATAL: bad power_action %r (want 'on' or 'reset')" % power_action)
        sys.exit(2)

    state = {"phase": "idle", "safe_done": False}

    def _on_term(signum, frame):
        log("signal %d -- exiting through safe path" % signum)
        raise SystemExit(143)

    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)

    sol = Sol(bmc_ip, bmc_user, bmc_pass)
    trace = []
    code = 0
    try:
        log("phase: deactivate SOL, wait %.0fs" % deact_wait)
        sol.deactivate()
        time.sleep(deact_wait)
        setup_seen = False
        if power_action == "on":
            # CLEAN mode: os_flip.sh already reached System Power: off and
            # latched 'bootdev bios option=efiboot' while off. Open SOL,
            # then COLD power on (no bootdev here -- it was latched off).
            #
            # RETRY: this platform's BIOS can silently DROP the one-shot
            # latch (2026-10-30 prod: latch set rc=0, cold power on, yet
            # the machine booted straight into the OS with no setup).
            # On a setup timeout: close SOL, force power off, re-latch
            # bootdev, cold power on again. SOL_SETUP_RETRIES = extra
            # attempts after the first (default 2 -> max 3 total).
            max_attempts = int(os.environ.get("SOL_SETUP_RETRIES", "2")) + 1
            for attempt in range(1, max_attempts + 1):
                if attempt > 1:
                    log("WARN: 'Aptio Setup' not seen within %.0fs on attempt "
                        "%d/%d -- BIOS likely dropped the one-shot latch; "
                        "retrying (power off -> re-latch bootdev -> power on)"
                        % (setup_to, attempt - 1, max_attempts))
                    sol.close()
                    time.sleep(deact_wait)
                    # Force power off: after a dropped one-shot the machine
                    # is usually booted into the persistent-first OS already
                    # (hard cut, same fallback class as the clean-shutdown
                    # forced-off path).
                    rc, _ = sol.ipmi("chassis", "power", "off")
                    if rc != 0:
                        time.sleep(3)
                        rc, _ = sol.ipmi("chassis", "power", "off")
                    if rc != 0:
                        log("FATAL: retry power off failed")
                        raise SystemExit(5)
                    off_ok = False
                    for _ in range(10):
                        rc, out = sol.ipmi("chassis", "status")
                        if rc == 0 and re.search(
                                r"System Power\s*:\s*off", out, re.I):
                            off_ok = True
                            break
                        time.sleep(2)
                    if not off_ok:
                        log("FATAL: machine not off before retry re-latch")
                        raise SystemExit(5)
                    rc, _ = sol.ipmi("chassis", "bootdev", "bios", "option=efiboot")
                    if rc != 0:
                        log("FATAL: retry bootdev set failed (rc=%d)" % rc)
                        raise SystemExit(4)
                    log("retry: bootdev re-latched while off")
                    sol.open()
                else:
                    sol.open()
                    state["phase"] = "pre_poweron"
                log("SOL session open, wait %.0fs then COLD power on "
                    "(attempt %d/%d, bootdev latched while off)"
                    % (pre_poweron_wait, attempt, max_attempts))
                time.sleep(pre_poweron_wait)
                t_reset = time.time()
                rc, _ = sol.ipmi("chassis", "power", "on")
                if rc != 0:
                    time.sleep(3)
                    rc, _ = sol.ipmi("chassis", "power", "on")
                if rc != 0:
                    log("FATAL: power on failed after retry")
                    raise SystemExit(5)
                state["phase"] = "post"
                log("cold power on sent (t=%.1fs, attempt %d)" % (sol.t(), attempt))
                if sol.wait_for(b"Aptio Setup", setup_to, abort_flag):
                    setup_seen = True
                    break
                if attempt == max_attempts:
                    log("FAIL: 'Aptio Setup' not seen within %.0fs "
                        "(%d attempts)" % (setup_to, max_attempts))
                    raise SystemExit(1)
        else:
            # RESET mode (legacy): one-shot bootdev while running + warm
            # power reset. (No setup retry here: legacy path, and a warm
            # reset after a dropped latch is just another reset.)
            state["phase"] = "bootdev"
            rc, _ = sol.ipmi("chassis", "bootdev", "bios", "option=efiboot")
            if rc != 0:
                log("FATAL: bootdev set failed (rc=%d)" % rc)
                raise SystemExit(4)
            sol.open()
            state["phase"] = "pre_reset"
            log("SOL session open, wait %.0fs then warm reset" % pre_reset_wait)
            time.sleep(pre_reset_wait)
            t_reset = time.time()
            rc, _ = sol.ipmi("chassis", "power", "reset")
            if rc != 0:
                time.sleep(3)
                rc, _ = sol.ipmi("chassis", "power", "reset")
            if rc != 0:
                log("FATAL: power reset failed after retry")
                raise SystemExit(5)
            state["phase"] = "post"
            log("warm reset sent (t=%.1fs)" % sol.t())
            setup_seen = sol.wait_for(b"Aptio Setup", setup_to, abort_flag)
            if not setup_seen:
                log("FAIL: 'Aptio Setup' not seen within %.0fs" % setup_to)
                raise SystemExit(1)
        log("UEFI setup reached at t=%.0fs" % sol.t())
        state["phase"] = "setup"
        for i in range(7):
            checks = ([("Save Options (tab arrival)", "text", "Save Options")]
                      if i == 6 else None)
            if not send_key(sol, trace, RIGHT, "RIGHT", settle_r, checks,
                            abort_flag):
                code = nav_fail(sol, trace,
                                "RIGHT press %d/7 verify failed" % (i + 1),
                                boot_to, dut_ip)
                state["safe_done"] = True
                raise SystemExit(code)
        ndown = TARGET_DOWNS[target]
        for i in range(ndown):
            checks = []
            desc = ITEMS[i]
            if desc is not None:
                checks.append(("desc item %d" % (i + 2), "panel", desc))
            name, neg = ITEM_NAMES[i]
            checks.append(("highlight item %d" % (i + 2), "hl", (name, neg)))
            if not send_key(sol, trace, DOWN, "DOWN", settle_d, checks,
                            abort_flag):
                code = nav_fail(
                    sol, trace,
                    "DOWN press %d/%d verify failed (expecting item %d)"
                    % (i + 1, ndown, i + 2), boot_to, dut_ip)
                state["safe_done"] = True
                raise SystemExit(code)
        r = do_enter(sol, trace)
        if r == "handoff":
            state["phase"] = "booting"
        else:
            code = nav_fail(sol, trace,
                            "ENTER response was %r, not the 24B handoff clear" % r,
                            boot_to, dut_ip)
            state["safe_done"] = True
            raise SystemExit(code)
        ok, up_at = boot_capture(sol, dut_ip, t_reset, boot_to, abort_flag,
                                 trace, up_tail,
                                 dut_mac=dut_mac, dut_net=dut_net)
        if not ok:
            log("FAIL: boot not confirmed (ping not UP within %.0fs) -- "
                "SOL evidence saved" % boot_to)
            raise SystemExit(3)
        trace.append("BOOT_UP reset_plus=%.0f" % (up_at - t_reset))
        log("boot confirmed: ping UP at reset+%.0fs" % (up_at - t_reset))
    finally:
        sol.close()
        try:
            with open(raw_f, "wb") as f:
                f.write(sol.stream)
            with open(clean_f, "wb") as f:
                f.write(clean(sol.stream))
            with open(trace_f, "w") as f:
                f.write("\n".join(trace) + ("\n" if trace else ""))
        except OSError as e:
            print("ERROR writing evidence files: %s" % e, file=sys.stderr)
        if state["phase"] in ("setup", "post") and not state["safe_done"]:
            # Machine is sitting in/entering UEFI setup: bring it back to a
            # normal boot. Phase "booting" must NOT be reset (the one-shot
            # handoff is in progress).
            log("exit path: machine in setup/POST phase -- plain power reset "
                "to normal boot")
            try:
                subprocess.run(
                    ["ipmitool", "-I", "lanplus", "-H", bmc_ip, "-U", bmc_user,
                     "-P", bmc_pass, "chassis", "power", "reset"],
                    capture_output=True, timeout=30)
            except Exception as e:
                log("WARN: cleanup power reset failed: %s" % e)
    sys.exit(code)


if __name__ == "__main__":
    main()
