#!/usr/bin/env python3
"""sol_boot.py -- profile-driven Boot Override switch + site discovery
(SOL pty, Aptio/AMI).

Provenance: designed & validated by luke1987515; AI-assisted development
(Hermes Agent by Nous Research; self-hosted Qwen3.8-27B). Verified on real
hardware 2026-11-01 and 2026-11-02: 20/20 os_flip cycles PASS across two
10-cycle runs; persistent boot order unchanged. Site-profile rework per
DESIGN-site-profiles.md v1 (approved 2026-11-07): the hardcoded Save & Exit
item table is replaced by per-site profiles, and --discover auto-calibrates
a new DUT in ~5 minutes.

Verified path (2026-10, reference dual-OS DUT):
  sol deactivate -> wait SOL_DEACT_WAIT (10s; the BMC SOL engine needs this
  gap before re-attach) -> open SOL pty session -> chassis power on/reset
  (bootdev bios option=efiboot latched while off, or one-shot while running
  in legacy reset mode) -> wait "Aptio Setup" -> RIGHT until the "Save &
  Exit" tab label is seen (cap 12) -> DOWN x <profile target_..._down> ->
  ENTER.

ENTER on a Boot Override entry answers with a ~24-byte screen clear
(\\x1b[2J \\x1b[1;1H, twice) = the BIOS handing off to boot. That clear is
NOT "no response": after it this script sends NOTHING and never issues an
abort/power reset (an abort reset after the handoff kills the target boot
-- a real failure mode verified 2026-10-28).

Boot confirmation = SOL stream + ping polling. SOL may be silent during
boot on this platform (even fully silent); ping is the ground truth.

Modes (argv[1]):
  cycle BMC_IP BMC_USER BMC_PASS TARGET RAW_FILE CLEAN_FILE TRACE_FILE
        SETUP_TIMEOUT BOOT_TIMEOUT DUT_IP ABORT_FLAG POWER_ACTION PROFILE_FILE
        TARGET: 'windows' | 'linux' (the profile's target_..._down keys)
        POWER_ACTION: 'reset' = legacy warm reset | 'on' = machine already
        off with bootdev latched, COLD power on
        The profile is opened READ-ONLY (run phase is never written to).
        The first DOWN is live-verified against item_2 (name+desc):
        mismatch = LAYOUT DRIFT -> the cycle aborts (exit 6), safe exit,
        re-run --discover.
  discover BMC_IP BMC_USER BMC_PASS RAW_FILE CLEAN_FILE TRACE_FILE
        SETUP_TIMEOUT BOOT_TIMEOUT DUT_IP ABORT_FLAG PROFILE_OUT SITE_NAME
        LINUX_NAME DUT_MAC POWERENTRY
        POWERENTRY: 'cold_on' (machine off + bootdev latched, COLD power on)
        | 'warm_reset' (machine running, bootdev while running, WARM reset --
        required on platforms that ignore the one-shot on cold boot, e.g.
        the aic_1x DUT / Tuca_0.09.0, verified 2026-11-06).
        Setup phase (~5 min): enter UEFI setup per POWERENTRY, navigate to
        the Save & Exit tab (RIGHT until the tab label is seen, cap 12),
        enumerate
        every item (DOWN step by step; stop at wrap back to the first item
        or the 24-item safety cap), pair the targets (windows = the row
        starting with "Windows Boot Manager"; linux = the row containing
        LINUX_NAME, squash comparison), write PROFILE_OUT atomically (tmp +
        mv) and print the human-readable item table, then leave setup via
        Discard Changes and Exit (Yes/No dialog: LEFT -> ENTER, calibrated
        sequence).
  setup-exit BMC_IP BMC_USER BMC_PASS RAW_FILE CLEAN_FILE TRACE_FILE
        SETUP_TIMEOUT BOOT_TIMEOUT DUT_IP
        RECOVERY: the machine must be OFF (a one-shot bootdev latch may be
        active). Opens SOL, cold-powers on and watches the boot: if
        'Aptio Setup' appears, leaves it via Discard Changes and Exit
        (one verified DOWN + the calibrated discard sequence); if not,
        the machine booted normally (latch dropped) and nothing is done.
        Exit: 0 = discard done or no-setup no-op | 2 = plain-reset fallback
        done (normal boot), or precondition not met (machine already on) |
        5 = power on failed | 7 = STUCK in setup.
  gate PROFILE_FILE BMC_IP DUT_MAC [SITE_NAME]
        Read-only identity gate (no hardware touched). Exit 0 ok | 2
        profile missing/unparseable | 3 identity or site mismatch (site
        move or the env is wrong -> re-run --discover).
  resolve SITE_NAME BASE_DIR
        Profile resolution: BASE_DIR/profiles/<SITE>.conf >
        BASE_DIR/sites/<SITE>.conf. Prints the winning path; exit 0 found
        | 2 not found (stderr lists the available sites).

Env (defaults are the verified values; shrunk only for sandbox testing):
  SOL_DEACT_WAIT=10  SOL_PRE_RESET_WAIT=8  SOL_PRE_POWERON_WAIT=3
  SOL_KEY_SETTLE=3.0  SOL_DOWN_SETTLE=4.0  SOL_SETUP_RETRIES=2
  SOL_UP_TAIL=15
  DUT_MAC/DUT_NET: when DUT_MAC set, the boot wait re-resolves the DUT IP
  by MAC if the DUT is silent for 30s (DHCP drift guard)

Exit codes:
  0 ok | 1 setup timeout | 2 nav fail (safe exit: SOL closed, plain power
  reset sent, normal boot waited) | 3 boot not confirmed | 4 bootdev set
  failed | 5 power reset failed | 6 LAYOUT DRIFT (cycle first-item
  mismatch) or discover pairing fail (safe exit done; re-run --discover) |
  7 machine may be sitting in UEFI setup (physical intervention required)
"""
import os
import re
import time
import select
import signal
import subprocess
import sys
import threading

UP = b"\x1b[A"
DOWN = b"\x1b[B"
RIGHT = b"\x1b[C"
LEFT = b"\x1b[D"
ENTER = b"\x0d"
ESC = b"\x1b"

CSI = re.compile(rb"\x1b\[[0-9;?]*[ -/]*[@-~]")
OSC = re.compile(rb"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\\\)")
CTL = re.compile(rb"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def clean(b):
    s = CSI.sub(b"", b)
    s = OSC.sub(b"", s)
    s = CTL.sub(b"", s)
    return s


# ---------------- site profiles (schema v1, DESIGN-site-profiles.md) ----

def squash(s):
    """The profile comparison rule: strip ALL whitespace + lowercase."""
    return re.sub(r"\s+", "", (s or "")).lower()


RE_MAC = re.compile(r"^([0-9a-f]{2}:){5}[0-9a-f]{2}$")
RE_IP = re.compile(r"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$")
RE_ITEM = re.compile(r"^item_(\d+)$")
PROFILE_KEYS = {"site", "bmc_ip", "dut_mac", "firmware", "discovered_at",
                "item_count", "power_entry", "target_windows_down",
                "target_linux_down", "target_linux_name"}
POWER_ENTRIES = ("cold_on", "warm_reset")


def _valid_ip(s):
    m = RE_IP.match(s)
    return bool(m) and all(int(g) <= 255 for g in m.groups())


def load_profile(path):
    """Parse a site profile (schema v1). Returns (dict, None) or
    (None, reason). Strict: unknown keys, duplicate/missing item_N, bad
    name::desc format, out-of-range targets, bad IP/MAC all fail loudly --
    a silently misparsed profile would pick the wrong OS.
    dict: site, bmc_ip, dut_mac (lower), firmware, discovered_at,
    item_count, items = [(name, desc)] (index 0 = item_1 = the item
    highlighted at setup arrival, before any DOWN), target_windows_down,
    target_linux_down, target_linux_name, path.
    desc "-" = no description column (Boot Override rows) = desc check off.
    """
    try:
        with open(path, "r") as f:
            lines = f.readlines()
    except OSError as e:
        return None, "cannot read %s: %s" % (path, e)
    kv = {}
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            return None, "bad line (no '='): %r" % line
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip()
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
            return None, "bad key: %r" % k
        if k in kv:
            return None, "duplicate key: %s" % k
        if k not in PROFILE_KEYS and not RE_ITEM.match(k):
            return None, "unknown key: %r" % k
        kv[k] = v
    for req in ("site", "bmc_ip", "dut_mac", "item_count",
                "target_windows_down", "target_linux_down",
                "target_linux_name"):
        if kv.get(req, "") == "":
            return None, "missing required key: %s" % req
    try:
        item_count = int(kv["item_count"])
        tw = int(kv["target_windows_down"])
        tl = int(kv["target_linux_down"])
    except ValueError:
        return None, "item_count / target_*_down must be integers"
    if item_count < 2:
        return None, "item_count too small: %d" % item_count
    if not 1 <= tw <= item_count - 1:
        return None, "target_windows_down=%d out of range 1..%d" % (tw, item_count - 1)
    if not 1 <= tl <= item_count - 1:
        return None, "target_linux_down=%d out of range 1..%d" % (tl, item_count - 1)
    if not _valid_ip(kv["bmc_ip"]):
        return None, "bmc_ip not a valid IPv4 address: %r" % kv["bmc_ip"]
    mac = kv["dut_mac"].lower()
    if not RE_MAC.match(mac):
        return None, "dut_mac not a valid MAC address: %r" % kv["dut_mac"]
    # power_entry: how this site's UEFI is entered (schema v1.1).
    # cold_on = clean shutdown -> bootdev latched while off -> COLD power on
    # (TUCANA reference platform). warm_reset = bootdev while running ->
    # WARM power reset: on some platforms (the aic_1x DUT, Tuca_0.09.0) a
    # COLD boot IGNORES the one-shot latch (verified 2026-11-06).
    pe = kv.get("power_entry", "cold_on")
    if pe not in POWER_ENTRIES:
        return None, "power_entry must be one of %s (got %r)" % (list(POWER_ENTRIES), pe)
    items = {}
    for k, v in kv.items():
        m = RE_ITEM.match(k)
        if not m:
            continue
        n = int(m.group(1))
        if not 1 <= n <= item_count:
            return None, "%s index out of range (item_count=%d)" % (k, item_count)
        if "::" not in v:
            return None, "%s missing '::' separator (want name::desc)" % k
        name, desc = v.split("::", 1)
        name, desc = name.strip(), desc.strip()
        if not name:
            return None, "%s has an empty name" % k
        if not desc:
            desc = "-"
        items[n] = (name, desc)
    missing = [n for n in range(1, item_count + 1) if n not in items]
    if missing:
        return None, "missing item_%d" % missing[0]
    lst = [items[n] for n in range(1, item_count + 1)]
    sq_seen = {}
    for n, (nm, _) in enumerate(lst, 1):
        s = squash(nm)
        if s in sq_seen:
            return None, ("items %d and %d have the same squashed name %r "
                          "-- the highlight check could not tell them apart"
                          % (sq_seen[s], n, nm))
        sq_seen[s] = n
    return {
        "site": kv["site"], "bmc_ip": kv["bmc_ip"], "dut_mac": mac,
        "firmware": kv.get("firmware", "unknown"),
        "discovered_at": kv.get("discovered_at", "unknown"),
        "item_count": item_count, "items": lst,
        "power_entry": pe,
        "target_windows_down": tw, "target_linux_down": tl,
        "target_linux_name": kv["target_linux_name"], "path": path,
    }, None


def resolve_profile(site, base_dir):
    """Resolution order: base_dir/profiles/<site>.conf (runner local,
    latest calibration) > base_dir/sites/<site>.conf (repo baseline).
    Returns (path, "profiles"|"sites") or (None, None). Site names that
    are not plain filenames are rejected (no path traversal)."""
    if (not site or "/" in site or "\\" in site or ".." in site
            or site != os.path.basename(site)):
        return None, None
    for sub in ("profiles", "sites"):
        p = os.path.join(base_dir, sub, site + ".conf")
        if os.path.isfile(p):
            return p, sub
    return None, None


def do_gate(profile_file, bmc_ip, dut_mac, site_name=""):
    """The identity gate (design 5.1/5.3): profile exists + parses, and
    its bmc_ip/dut_mac/site match the env. Returns the exit code."""
    p, err = load_profile(profile_file)
    if err:
        print("GATE FAIL (2): %s: %s" % (profile_file, err))
        return 2
    bad = []
    if bmc_ip and p["bmc_ip"] != bmc_ip:
        bad.append("bmc_ip profile=%s env=%s" % (p["bmc_ip"], bmc_ip))
    if dut_mac and p["dut_mac"] != dut_mac.lower():
        bad.append("dut_mac profile=%s env=%s" % (p["dut_mac"], dut_mac))
    if site_name and p["site"] != site_name:
        bad.append("site profile=%s env=%s" % (p["site"], site_name))
    if bad:
        print("GATE FAIL (3): identity mismatch (site moved or the env is "
              "wrong): " + "; ".join(bad))
        return 3
    print("GATE OK: site=%s bmc_ip=%s dut_mac=%s (%d items, "
          "windows=DOWN%d linux=DOWN%d/%s)"
          % (p["site"], p["bmc_ip"], p["dut_mac"], p["item_count"],
             p["target_windows_down"], p["target_linux_down"],
             p["target_linux_name"]))
    return 0


def hl_checks(name, all_names):
    """Highlight check for a profile item name: (squashed name, negs).
    The SGR-bold run (the cursor row) must contain the name; negs are the
    squashed full names of every OTHER item that strictly contains this
    one (disambiguates 'Save Changes' from 'Save Changes and Exit/Reset'
    without any hardcoded table)."""
    sq = squash(name)
    negs = sorted({squash(o) for o in all_names
                   if o and squash(o) != sq and sq in squash(o)})
    return sq, negs


def step_checks(idx, items):
    """Nav-verify checks for the item highlighted after DOWN press idx+1
    (idx 0-based = item idx+1). Name check (hl2) always; desc check
    (panel2) when the profile carries a real desc fragment ('-' = Boot
    Override row, no description column)."""
    name, desc = items[idx]
    all_names = [nm for nm, _ in items]
    sq, negs = hl_checks(name, all_names)
    checks = [("item %d" % (idx + 1), "hl2", (sq, negs))]
    if desc and desc != "-":
        checks.append(("desc item %d" % (idx + 1), "panel2", squash(desc)))
    return checks


def now_iso():
    """Local time as ISO-8601 with an explicit offset (+08:00 style)."""
    off = -time.timezone if not time.daylight else -time.altzone
    sign = "+" if off >= 0 else "-"
    off = abs(off)
    return (time.strftime("%Y-%m-%dT%H:%M", time.localtime())
            + "%s%02d:%02d" % (sign, off // 3600, (off % 3600) // 60))


def write_profile_atomic(path, text):
    """S6: tmp + rename = atomic profile write (no half profile)."""
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)
    try:
        os.chmod(path, 0o644)
    except OSError:
        pass


def sniff_firmware(stream):
    """Best-effort firmware token from the SOL stream (informational only,
    NEVER a gate)."""
    m = re.search(rb"Tuca[_ -]?([0-9]+(?:\.[0-9]+)+[0-9A-Za-z._-]*)", stream)
    if m:
        return "Tuca_" + m.group(1).decode("latin-1")
    m = re.search(rb"(?i)BIOS\s*Version[:\s]+([0-9][0-9A-Za-z._-]{2,30})", stream)
    if m:
        return m.group(1).decode("latin-1")
    return "unknown"


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
                    j2 = data.find(b"\x1b\\\\", i)
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
        """Right-hand description panel (grid columns 55..88, 1-based),
        DESCRIPTION BOX ONLY: the non-frame segments between the first and
        second frame lines of the column slice, joined. The BIOS writes the
        highlighted item's description here, wrapped (verified position:
        CUP 6;55 in real reference captures); joining the panel column
        makes a wrapped sentence contiguous again -- the full screen text
        is useless for that because menu-column text interleaves between
        the fragments.

        Why box-only: Aptio's setup screen draws fixed furniture in this
        column range -- the outer-box top border, the description box, its
        bottom border, the function-key legend ('><: Select Screen ... F4:
        Save & Exit'), the outer-box bottom border, and the 'Version ...
        AMI' footer. Joining the whole column (the old behaviour) mixed
        ALL of it into the desc: frame dashes, the legend, '2025 AMI AB'
        footer junk (verified 2026-11-08: the first real --discover wrote
        polluted descs into profiles/aic_1x.conf, and a polluted Boot
        Override desc would fail the cycle's per-step panel2 check).
        """
        FRAME = set("-\\|/ +")
        parts = []
        started = False
        for line in self.lines():
            seg = line[54:88].replace("|", " ").strip()
            if seg and set(seg) <= FRAME:
                if not started:
                    started = True  # outer-box top border
                else:
                    break  # description-box bottom border
            elif started:
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
        # pty/tty are POSIX-only; imported here (not at module level) so
        # the profile functions stay importable on any host (local tests).
        import pty
        import tty
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


def _check_highlight2(screen, sq_name, sq_negs):
    """Profile highlight check (squash rule): the bold run must contain the
    squashed item name and none of the squashed superset names (see
    hl_checks())."""
    rr = screen.highlight_row()
    if rr is None:
        return False
    run = squash(_bold_run_text(screen, rr))
    if sq_name not in run:
        return False
    return all(n not in run for n in sq_negs)


def _check_panel2(screen, sq_desc):
    """Profile desc check (squash rule): the description panel must contain
    the squashed desc fragment."""
    return sq_desc in squash(screen.panel_text())


def send_key(sol, trace, key, name, settle, checks, abort_flag):
    """Send one key, read the settle window, log the diff, verify.

    checks = list of (label, kind, payload); ALL must pass.
      kind 'text' : payload = substring matched on the rendered screen
                    (whitespace-tolerant, handles wrapped desc sentences).
      kind 'hl'   : payload = (name, neg); the highlighted (SGR-bold) row
                    must contain name (and not neg).
      kind 'hl2'  : payload = (sq_name, sq_negs); profile highlight check
                    (squash substring; negs = derived superset names).
      kind 'panel': payload = substring matched on the description panel.
      kind 'panel2': payload = squashed desc fragment (profile rule).
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
            elif kind == "hl2":
                passed = _check_highlight2(sol.screen, payload[0], payload[1])
            elif kind == "panel2":
                passed = _check_panel2(sol.screen, payload)
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


def nav_fail(sol, trace, why, boot_to, dut_ip, code=2):
    """Nav verify failed: do NOT send ENTER. Safe exit = close SOL + plain
    power reset (persistent order unchanged) + wait for normal boot."""
    log("NAV FAIL: %s" % why)
    trace.append("NAV_FAIL %s" % why)
    sol.close()
    rc, _ = sol.ipmi("chassis", "power", "reset")
    if rc != 0:
        log("NAV FAIL: safe-exit power reset FAILED -- check machine manually")
        return code
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
    return code


def go_to_save_exit_tab(sol, trace, abort_flag, settle_r):
    """S3: RIGHT until the 'Save Options' section header appears (cap 12
    presses). Replaces the old hardcoded 7-press count; the marker is tab
    CONTENT, not the 'Save & Exit' tab label: EVERY tab renders the
    'F4: Save & Exit' function-key legend in the screen footer, so the
    label text false-matches on the wrong tab (verified 2026-11-07 on
    aic_1x: arrival declared after 1 RIGHT on the Advanced tab, then
    enumeration of the wrong tab). 'Save Options' is the Save & Exit tab's
    section header -- the marker of the verified 20/20 path (2026-10/11).
    """
    for i in range(12):
        ok = send_key(sol, trace, RIGHT, "RIGHT", settle_r,
                      [("Save Options (tab arrival)", "text", "Save Options")],
                      abort_flag)
        if ok:
            log("tab 'Save & Exit' reached after %d RIGHT press(es)" % (i + 1))
            return True
    return False


def capture_item(sol):
    """Read the currently highlighted item: (name, desc). name = the
    SGR-bold run (the cursor row); desc = the joined description panel
    ('-' when the panel is empty = Boot Override rows have no desc).
    Returns (None, None) when no qualified bold row is on screen."""
    rr = sol.screen.highlight_row()
    if rr is None:
        return None, None
    name = _bold_run_text(sol.screen, rr)
    if not name:
        return None, None
    desc = " ".join(sol.screen.panel_text().split())
    return name, (desc if desc else "-")


def enumerate_items(sol, trace, abort_flag, settle_d):
    """S4: enumerate the Save & Exit tab by stepping DOWN. items[0] =
    item_1 (the first tab item, highlighted at arrival). Stop at wrap back
    to the first item, or the 24-item safety cap. Returns
    (items, wrapped) -- items None when the screen could not be read or a
    key stuck (abort the discovery rather than record a wrong table)."""
    sol.read(1.0)  # let the tab frame settle before the first capture
    name, desc = capture_item(sol)
    if not name:
        log("enumerate: no qualified bold row on screen (SOL decode?)")
        return None, False
    items = [(name, desc)]
    first_sq = squash(name)
    wrapped = False
    for n in range(2, 25):  # 24-item safety cap
        prev_sq = squash(items[-1][0])
        send_key(sol, trace, DOWN, "DOWN(enumerate %d)" % n, settle_d,
                 None, abort_flag)
        name, desc = capture_item(sol)
        if not name:
            log("enumerate: lost the highlighted row at step %d" % n)
            return None, False
        sq = squash(name)
        if sq == first_sq:
            wrapped = True
            log("enumerate: wrap detected at DOWN %d -- %d item(s)"
                % (n - 1, len(items)))
            break
        if sq == prev_sq:
            # no movement: lost key (or a stuck row). Resend up to twice.
            log("enumerate: no movement at item %d -- resending DOWN" % n)
            moved = False
            for _ in range(2):
                send_key(sol, trace, DOWN, "DOWN(retry enumerate %d)" % n,
                         settle_d, None, abort_flag)
                name, desc = capture_item(sol)
                if not name:
                    return None, False
                if squash(name) != prev_sq:
                    moved = True
                    break
            if not moved:
                log("enumerate: still stuck at item %d after retries "
                    "-- aborting (partial table untrustworthy)" % n)
                return None, False
            sq = squash(name)
            if sq == first_sq:
                wrapped = True
                log("enumerate: wrap detected -- %d item(s)" % len(items))
                break
        items.append((name, desc))
    else:
        log("enumerate: 24-item cap reached without a wrap -- continuing "
            "with the partial list (WARN)")
    return items, wrapped


def print_item_table(items, targets, site=None):
    """S6: the human-readable comparison table (all items, targets marked
    with their DOWN counts). targets = (win_idx, lin_idx) or None."""
    win_idx, lin_idx = targets if targets else (None, None)
    print("==== Save & Exit tab (site=%s, %d items) ===="
          % (site, len(items)))
    for i, (nm, desc) in enumerate(items):
        line = "  item %2d (DOWN %2d): %s" % (i + 1, i, nm)
        if desc and desc != "-":
            line += "   [%s]" % (" ".join(desc.split())[:80])
        if i == win_idx:
            line += "   <-- WINDOWS target_windows_down=%d" % i
        if i == lin_idx:
            line += "   <-- LINUX target_linux_down=%d" % i
        print(line, flush=True)


def build_profile_text(site_name, bmc_ip, dut_mac, firmware, items,
                       win_idx, lin_idx, linux_name, power_entry="cold_on"):
    L = ["# Site profile %s -- written by sol_boot.py --discover (%s)"
         % (site_name, now_iso()),
         "# No secrets: IP/MAC are test-LAN internals. The cycle opens it",
         "# read-only; re-run --discover after firmware updates / UEFI reset."]
    L.append("site=%s" % site_name)
    L.append("bmc_ip=%s" % bmc_ip)
    L.append("dut_mac=%s" % dut_mac.lower())
    L.append("firmware=%s" % firmware)
    L.append("discovered_at=%s" % now_iso())
    L.append("power_entry=%s" % power_entry)
    L.append("item_count=%d" % len(items))
    for i, (nm, desc) in enumerate(items, 1):
        L.append("item_%d=%s::%s" % (i, nm, desc if desc and desc != "-" else "-"))
    L.append("target_windows_down=%d" % win_idx)
    L.append("target_linux_down=%d" % lin_idx)
    L.append("target_linux_name=%s" % linux_name)
    return "\n".join(L) + "\n"


def discard_exit_seq(sol, trace, settle_r):
    """S7: ENTER on 'Discard Changes and Exit' -> Yes/No dialog -> LEFT ->
    ENTER (the calibrated sequence: the dialog opens with the right
    option highlighted; LEFT moves to Yes). Returns
    'ok' | 'no_dialog' | 'no_clear' | 'write_fail'."""
    try:
        os.write(sol.master, ENTER)
    except OSError:
        return "write_fail"
    sol.read(4.0)
    if not (_check_text(sol.screen, "Yes") and _check_text(sol.screen, "No")):
        trace.append("t=%.1f key=ENTER(Discard) NO Yes/No dialog seen" % sol.t())
        return "no_dialog"
    trace.append("t=%.1f key=ENTER(Discard) Yes/No dialog seen -- LEFT then ENTER"
                 % sol.t())
    try:
        os.write(sol.master, LEFT)
    except OSError:
        return "write_fail"
    sol.read(settle_r)
    n_before = len(sol.stream)
    try:
        os.write(sol.master, ENTER)
    except OSError:
        return "write_fail"
    sol.read(6.0)
    tail = sol.stream[-400:]
    new_bytes = len(sol.stream) - n_before
    if b"\x1b[2J" in tail or new_bytes >= 100:
        trace.append("t=%.1f key=ENTER(Yes) setup exit confirmed "
                     "(clear=%s new_bytes=%d)"
                     % (sol.t(), b"\x1b[2J" in tail, new_bytes))
        log("S7: setup exited via Discard Changes and Exit")
        return "ok"
    trace.append("t=%.1f key=ENTER(Yes) no clear and no POST stream "
                 "(new_bytes=%d)" % (sol.t(), new_bytes))
    return "no_clear"


def discover_safe_exit(sol, trace, items, wrapped, boot_to, dut_ip,
                       bmc_ip, bmc_user, bmc_pass, settle_d):
    """S7 safe exit: navigate to 'Discard Changes and Exit' (verified
    step by step against the just-enumerated table) and discard. Any
    failure falls back to a plain power reset (the machine boots the
    persistent order). Returns 'discard' | 'reset' | 'stuck'."""
    d_idx = None
    if items:
        for i, (nm, _) in enumerate(items):
            if squash(nm) == "discardchangesandexit":
                d_idx = i
                break
    if d_idx is None:
        log("discover S7: no 'Discard Changes and Exit' item in the "
            "enumeration -- plain reset")
    else:
        last_idx = 0 if wrapped else len(items) - 1
        dist = (d_idx - last_idx) % len(items)
        ok_nav = True
        for k in range(dist):
            pos = (last_idx + k + 1) % len(items)
            checks = step_checks(pos, items)
            if not send_key(sol, trace, DOWN, "DOWN(S7 exit %d/%d)" % (k + 1, dist),
                            settle_d, checks, abort_flag=None):
                ok_nav = False
                log("discover S7: nav verify failed at item %d -- plain reset"
                    % (pos + 1))
                break
        if ok_nav:
            r = discard_exit_seq(sol, trace, float(os.environ.get("SOL_KEY_SETTLE", "3.0")))
            if r == "ok":
                return "discard"
            log("discover S7: Discard exit did not confirm (%s) -- ESC + plain reset" % r)
            try:
                os.write(sol.master, ESC)
            except OSError:
                pass
            sol.read(2.0)
    sol.close()
    rc, _ = sol.ipmi("chassis", "power", "reset")
    if rc != 0:
        log("!! DISCOVER SAFE EXIT FAILED: machine may be sitting in UEFI "
            "SETUP -- PHYSICAL INTERVENTION REQUIRED")
        trace.append("STUCK in setup (safe-exit reset failed)")
        return "stuck"
    up_at = wait_ping_up(dut_ip, boot_to,
                         dut_mac=os.environ.get("DUT_MAC", ""),
                         dut_net=os.environ.get("DUT_NET", ""))
    if up_at:
        log("discover S7: safe exit via plain reset done, DUT ping UP")
        trace.append("SAFE_EXIT reset done (DUT ping UP)")
    else:
        log("discover S7: DUT ping NOT UP after reset within %.0fs "
            "-- check machine manually" % boot_to)
        trace.append("SAFE_EXIT reset done (DUT ping NOT UP -- check machine)")
    return "reset"


def discover_fail(sol, trace, why, state, items, boot_to, dut_ip,
                  bmc_ip, bmc_user, bmc_pass, settle_d, wrapped=False,
                  profile_written=False):
    """Any S2-S7 failure: print the diagnosis (with the item table when
    available), attempt the safe exit, and map to the exit code:
    7 = machine may be in setup | 2 = profile was written (machine back)
    | 6 = no profile (machine back)."""
    log("DISCOVER FAIL: %s" % why)
    trace.append("DISCOVER_FAIL %s" % why)
    if items:
        print_item_table(items, None, site="diagnosis")
    state["safe_done"] = True
    res = discover_safe_exit(sol, trace, items, wrapped, boot_to, dut_ip,
                             bmc_ip, bmc_user, bmc_pass, settle_d)
    if res == "stuck":
        state["phase"] = "stuck"
        return 7
    state["phase"] = "booting"
    return 2 if profile_written else 6


def discover_flow(sol, trace, bmc_ip, bmc_user, bmc_pass, boot_to, dut_ip,
                  abort_flag, profile_out, site_name, linux_name, dut_mac,
                  state, settle_r, settle_d, power_entry="cold_on"):
    """S2-S7 (S2 = the shared setup entry, already done by the caller).
    Returns the process exit code."""
    log("discover: site=%s linux_name=%s dut_mac=%s power_entry=%s -> %s"
        % (site_name, linux_name, dut_mac, power_entry, profile_out))
    # S3: Save & Exit tab (text search, cap 12)
    if not go_to_save_exit_tab(sol, trace, abort_flag, settle_r):
        return discover_fail(sol, trace,
                             "S3: 'Save & Exit' tab not reached in 12 RIGHT presses",
                             state, None, boot_to, dut_ip, bmc_ip, bmc_user,
                             bmc_pass, settle_d)
    # S4: enumerate
    items, wrapped = enumerate_items(sol, trace, abort_flag, settle_d)
    if not items:
        return discover_fail(sol, trace,
                             "S4: enumeration failed (screen unreadable or key stuck)",
                             state, None, boot_to, dut_ip, bmc_ip, bmc_user,
                             bmc_pass, settle_d)
    # S5: pair the targets
    win_hits = [i for i, (nm, _) in enumerate(items)
                if squash(nm).startswith("windowsbootmanager")]
    lin_hits = [i for i, (nm, _) in enumerate(items)
                if squash(linux_name) in squash(nm)]
    if not win_hits or not lin_hits:
        return discover_fail(
            sol, trace,
            "S5: target pairing failed (windows_hits=%s linux_hits=%s; "
            "LINUX_NAME=%r)" % (win_hits, lin_hits, linux_name),
            state, items, boot_to, dut_ip, bmc_ip, bmc_user, bmc_pass,
            settle_d, wrapped=wrapped)
    win_idx, lin_idx = win_hits[0], lin_hits[0]
    if len(win_hits) > 1 or len(lin_hits) > 1:
        print_item_table(items, (win_idx, lin_idx), site=site_name)
        print("WARN: multiple hits -- windows %s / linux %s; the first of "
              "each will be adopted. ALL of them are listed above."
              % (win_hits, lin_hits))
        if sys.stdin.isatty():
            try:
                ans = input("adopt the first hit of each and continue? "
                            "[Enter=yes / q=abort] ")
            except EOFError:
                ans = ""
            if ans.strip().lower() in ("q", "quit", "abort"):
                return discover_fail(sol, trace,
                                     "S5: aborted by operator (multiple hits)",
                                     state, items, boot_to, dut_ip, bmc_ip,
                                     bmc_user, bmc_pass, settle_d,
                                     wrapped=wrapped)
        else:
            log("discover: WARN non-interactive run -- adopting the first "
                "hit of each without confirmation")
    # S6: write the profile (atomic) + the human-readable table
    firmware = sniff_firmware(sol.stream)
    text = build_profile_text(site_name, bmc_ip, dut_mac, firmware, items,
                              win_idx, lin_idx, linux_name, power_entry)
    try:
        write_profile_atomic(profile_out, text)
    except OSError as e:
        return discover_fail(sol, trace,
                             "S6: profile write failed: %s" % e, state, items,
                             boot_to, dut_ip, bmc_ip, bmc_user, bmc_pass,
                             settle_d, wrapped=wrapped)
    print_item_table(items, (win_idx, lin_idx), site=site_name)
    log("S6: profile written: %s" % profile_out)
    trace.append("PROFILE_WRITTEN %s" % profile_out)
    # S7: leave setup via Discard (any failure -> safe-exit fallback)
    res = discover_safe_exit(sol, trace, items, wrapped, boot_to, dut_ip,
                             bmc_ip, bmc_user, bmc_pass, settle_d)
    if res == "discard":
        state["phase"] = "booting"
        return 0
    state["safe_done"] = True
    if res == "stuck":
        log("!! machine may be sitting in UEFI SETUP -- PHYSICAL INTERVENTION "
            "REQUIRED (profile WAS written: %s)" % profile_out)
        state["phase"] = "stuck"
        return 7
    state["phase"] = "booting"
    log("discover S7: plain-reset fallback done (profile WAS written: %s)"
        % profile_out)
    return 2


def setup_exit_flow(sol, trace, boot_to, dut_ip, bmc_ip, bmc_user, bmc_pass,
                    settle_r, settle_d, state):
    """RECOVERY: the machine is ON and in UEFI setup (a one-shot latch was
    active at power on). Leave it via 'Discard Changes and Exit' — item_2
    on every calibrated site — NO enumeration (that is --discover's job):
    one verified DOWN, then the calibrated discard sequence. Any failure
    -> plain power reset (persistent order unchanged). Exit code:
    0 = discard done | 2 = plain-reset fallback done | 7 = STUCK."""
    if not go_to_save_exit_tab(sol, trace, None, settle_r):
        trace.append("SETUP_EXIT tab arrival failed")
        log("setup-exit: 'Save & Exit' tab not reached in 12 RIGHT presses")
    else:
        # name-only check (desc '-'): a layout-tolerant recovery helper;
        # the SGR-bold row must read 'Discard Changes and Exit'.
        mini = [("Save Changes and Exit", "-"),
                ("Discard Changes and Exit", "-")]
        checks = step_checks(1, mini)
        if not send_key(sol, trace, DOWN, "DOWN(setup-exit to item_2)",
                        settle_d, checks, None):
            log("setup-exit: item_2 verify failed")
        else:
            r = discard_exit_seq(sol, trace,
                                 float(os.environ.get("SOL_KEY_SETTLE", "3.0")))
            if r == "ok":
                state["phase"] = "booting"
                log("setup-exit: Discard Changes and Exit done -- machine "
                    "booting the persistent order")
                trace.append("SETUP_EXIT discard done")
                return 0
            log("setup-exit: Discard exit did not confirm (%s) -- ESC + plain reset" % r)
            try:
                os.write(sol.master, ESC)
            except OSError:
                pass
            sol.read(2.0)
    # fallback: plain power reset (never leaves the machine in setup)
    sol.close()
    rc, _ = sol.ipmi("chassis", "power", "reset")
    if rc != 0:
        log("!! SETUP-EXIT FAILED AND RESET FAILED: machine may be sitting "
            "in UEFI SETUP -- PHYSICAL INTERVENTION REQUIRED")
        trace.append("STUCK in setup (setup-exit reset failed)")
        state["phase"] = "stuck"
        return 7
    state["phase"] = "booting"
    state["safe_done"] = True
    up_at = wait_ping_up(dut_ip, boot_to,
                         dut_mac=os.environ.get("DUT_MAC", ""),
                         dut_net=os.environ.get("DUT_NET", ""))
    if up_at:
        log("setup-exit: plain-reset fallback done, DUT ping UP")
        trace.append("SETUP_EXIT reset done (DUT ping UP)")
    else:
        log("setup-exit: DUT ping NOT UP after reset within %.0fs "
            "-- check machine manually" % boot_to)
        trace.append("SETUP_EXIT reset done (DUT ping NOT UP -- check machine)")
    return 2


def cycle_flow(sol, trace, profile, target, boot_to, dut_ip, abort_flag,
               state, settle_r, settle_d):
    """Run phase: profile-driven navigation. Returns the process exit code
    (0 = handoff confirmed, the caller does the boot capture)."""
    items = profile["items"]
    if target == "windows":
        target_downs = profile["target_windows_down"]
    else:
        target_downs = profile["target_linux_down"]
    log("cycle: target=%s -> %d DOWN press(es) (profile %s, read-only)"
        % (target, target_downs, os.path.basename(profile["path"])))
    if not go_to_save_exit_tab(sol, trace, abort_flag, settle_r):
        return nav_fail(sol, trace,
                        "tab arrival: 'Save & Exit' not reached in 12 RIGHT presses",
                        boot_to, dut_ip, code=2)
    for p in range(target_downs):
        idx = p + 1  # after DOWN press p+1, item idx+1 is highlighted
        checks = step_checks(idx, items)
        if not send_key(sol, trace, DOWN, "DOWN", settle_d, checks, abort_flag):
            if p == 0:
                # the layout gate (design 5.3): first item live-verified
                return nav_fail(
                    sol, trace,
                    "LAYOUT DRIFT: item_2 mismatch (profile says %r) -- "
                    "re-run: ./os_flip.sh --discover" % (items[idx][0],),
                    boot_to, dut_ip, code=6)
            return nav_fail(
                sol, trace,
                "DOWN press %d/%d verify failed (expecting item %d: %r)"
                % (p + 1, target_downs, idx + 1, items[idx][0]),
                boot_to, dut_ip, code=2)
    r = do_enter(sol, trace)
    if r == "handoff":
        state["phase"] = "booting"
        return 0
    return nav_fail(sol, trace,
                    "ENTER response was %r, not the 24B handoff clear" % r,
                    boot_to, dut_ip, code=2)


def main():
    argv = sys.argv[1:]
    if not argv:
        print(__doc__)
        sys.exit(2)
    mode = argv[0]

    if mode == "resolve":
        if len(argv) != 3:
            print(__doc__)
            sys.exit(2)
        site, base_dir = argv[1], argv[2]
        p, src = resolve_profile(site, base_dir)
        if p is None:
            print("no profile for site %r (looked in %s/profiles and %s/sites)"
                  % (site, base_dir, base_dir), file=sys.stderr)
            avail = []
            for sub in ("profiles", "sites"):
                d = os.path.join(base_dir, sub)
                if os.path.isdir(d):
                    avail += [f[:-5] for f in os.listdir(d) if f.endswith(".conf")]
            if avail:
                print("available: %s" % ", ".join(sorted(set(avail))),
                      file=sys.stderr)
            sys.exit(2)
        print(p)
        sys.exit(0)

    if mode == "gate":
        if len(argv) not in (4, 5):
            print(__doc__)
            sys.exit(2)
        site = argv[4] if len(argv) == 5 else ""
        sys.exit(do_gate(argv[1], argv[2], argv[3], site))

    if mode == "cycle":
        if len(argv) != 14:
            print(__doc__)
            sys.exit(2)
        (bmc_ip, bmc_user, bmc_pass, target, raw_f, clean_f, trace_f,
         setup_to, boot_to, dut_ip, abort_flag, power_action,
         profile_path) = argv[1:14]
        profile, perr = load_profile(profile_path)
        if perr:
            log("FATAL: profile unparseable: %s" % perr)
            sys.exit(2)
        if target not in ("windows", "linux"):
            log("FATAL: bad target %r (want 'windows' or 'linux')" % target)
            sys.exit(2)
        if power_action not in ("on", "reset"):
            log("FATAL: bad power_action %r (want 'on' or 'reset')" % power_action)
            sys.exit(2)
        site_name, linux_name, dut_mac = None, None, None
        discover_out = None
        power_entry = "cold_on"  # unused in cycle mode (set in discover)
    elif mode == "discover":
        if len(argv) != 16:
            print(__doc__)
            sys.exit(2)
        (bmc_ip, bmc_user, bmc_pass, raw_f, clean_f, trace_f,
         setup_to, boot_to, dut_ip, abort_flag, discover_out, site_name,
         linux_name, dut_mac, power_entry) = argv[1:16]
        if (not site_name or "/" in site_name or "\\" in site_name
                or ".." in site_name):
            log("FATAL: bad site name %r" % site_name)
            sys.exit(2)
        if not linux_name:
            log("FATAL: LINUX_NAME is empty")
            sys.exit(2)
        if power_entry not in POWER_ENTRIES:
            log("FATAL: bad POWERENTRY %r (want one of %s)"
                % (power_entry, list(POWER_ENTRIES)))
            sys.exit(2)
        profile, target = None, None
        power_action = "reset" if power_entry == "warm_reset" else "on"
    elif mode == "setup-exit":
        if len(argv) != 10:
            print(__doc__)
            sys.exit(2)
        (bmc_ip, bmc_user, bmc_pass, raw_f, clean_f, trace_f,
         setup_to, boot_to, dut_ip) = argv[1:10]
        profile, target, power_action = None, None, "setup-exit"
        abort_flag, discover_out, site_name, linux_name, dut_mac = (None,) * 5
    else:
        print("unknown mode %r" % mode, file=sys.stderr)
        print(__doc__)
        sys.exit(2)

    setup_to = float(setup_to)
    boot_to = float(boot_to)
    deact_wait = float(os.environ.get("SOL_DEACT_WAIT", "10"))
    pre_reset_wait = float(os.environ.get("SOL_PRE_RESET_WAIT", "8"))
    pre_poweron_wait = float(os.environ.get("SOL_PRE_POWERON_WAIT", "3"))
    settle_r = float(os.environ.get("SOL_KEY_SETTLE", "3.0"))
    settle_d = float(os.environ.get("SOL_DOWN_SETTLE", "4.0"))
    up_tail = float(os.environ.get("SOL_UP_TAIL", "15"))
    dut_mac = dut_mac or os.environ.get("DUT_MAC", "")
    dut_net = os.environ.get("DUT_NET", "")

    state = {"phase": "idle", "safe_done": False}

    def _on_term(signum, frame):
        log("signal %d -- exiting through safe path" % signum)
        raise SystemExit(143)

    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)

    sol = Sol(bmc_ip, bmc_user, bmc_pass)
    trace = []
    code = 0
    t_reset = time.time()
    try:
        log("phase: deactivate SOL, wait %.0fs" % deact_wait)
        sol.deactivate()
        time.sleep(deact_wait)
        setup_seen = False
        if power_action == "setup-exit":
            # RECOVERY: the machine is OFF (a one-shot latch may be active).
            # A live SOL session only sees NEW bytes, so open SOL FIRST and
            # power on, watching the boot from the start: if the latch held,
            # 'Aptio Setup' streams in and we safe-exit via Discard Changes
            # and Exit; if it dropped, the machine boots normally and
            # nothing is done. An already-on machine is refused (a static
            # setup screen could not be detected).
            rc, out = sol.ipmi("chassis", "status")
            if rc != 0 or not re.search(r"System Power\s*:\s*off", out, re.I):
                log("FATAL: setup-exit requires System Power: off (got: %s) "
                    "-- the boot must be watched from the start; check the "
                    "machine manually" % (" ".join(out.split())[:80]))
                raise SystemExit(2)
            sol.open()
            state["phase"] = "pre"
            log("setup-exit: SOL session open, wait %.0fs then COLD power on "
                "(watching for UEFI setup)" % pre_poweron_wait)
            time.sleep(pre_poweron_wait)
            t_reset = time.time()
            rc, _ = sol.ipmi("chassis", "power", "on")
            if rc != 0:
                time.sleep(3)
                rc, _ = sol.ipmi("chassis", "power", "on")
            if rc != 0:
                log("FATAL: power on failed")
                state["phase"] = "idle"
                raise SystemExit(5)
            state["phase"] = "post"
            log("cold power on sent (t=%.1fs)" % sol.t())
            setup_seen = sol.wait_for(b"Aptio Setup", setup_to, None)
            if not setup_seen:
                log("setup-exit: no UEFI setup within %.0fs -- machine "
                    "presumably booted normally (one-shot latch dropped "
                    "or absent); NO further action taken" % setup_to)
                state["phase"] = "booting"
                raise SystemExit(0)
            log("setup-exit: UEFI setup reached at t=%.0fs" % sol.t())
            state["phase"] = "setup"
            code = setup_exit_flow(sol, trace, boot_to, dut_ip,
                                   bmc_ip, bmc_user, bmc_pass,
                                   settle_r, settle_d, state)
            raise SystemExit(code)
        elif power_action == "on":
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
        if mode == "cycle":
            code = cycle_flow(sol, trace, profile, target, boot_to, dut_ip,
                              abort_flag, state, settle_r, settle_d)
            if code == 0:
                ok, up_at = boot_capture(sol, dut_ip, t_reset, boot_to,
                                         abort_flag, trace, up_tail,
                                         dut_mac=dut_mac, dut_net=dut_net)
                if not ok:
                    log("FAIL: boot not confirmed (ping not UP within %.0fs) -- "
                        "SOL evidence saved" % boot_to)
                    raise SystemExit(3)
                trace.append("BOOT_UP reset_plus=%.0f" % (up_at - t_reset))
                log("boot confirmed: ping UP at reset+%.0fs" % (up_at - t_reset))
        else:
            code = discover_flow(sol, trace, bmc_ip, bmc_user, bmc_pass,
                                 boot_to, dut_ip, abort_flag, discover_out,
                                 site_name, linux_name, dut_mac, state,
                                 settle_r, settle_d, power_entry)
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
            # handoff / the discard exit is in progress); phase "stuck"
            # already failed a reset attempt.
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
