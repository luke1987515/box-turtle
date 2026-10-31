#!/usr/bin/env python3
"""Sandbox stub for ipmitool. Hermetic: never touches the network.
State dir: $SB_STATE.

The "sol activate" mode emulates the vendor BIOS UEFI SOL terminal: waits for
the warm reset, prints the setup banner, then serves FULL-SCREEN redraws
(CUP positioning + SGR bold on the highlighted item row, wrapped
description panel) matching the real Aptio frame structure verified on
2026-10-29. Keys: RIGHT (tab move), DOWN (item move), ENTER (on a Boot
Override entry = one-shot boot handoff: 24-byte double clear).
"""
import os
import sys
import time
import threading
import subprocess

STATE = os.environ.get("SB_STATE", "/tmp/sbstate")
os.makedirs(STATE, exist_ok=True)

BOOT_SECS = int(os.environ.get("SB_BOOT_SECS", "2"))
NAVFAIL_AT = os.environ.get("SB_NAVFAIL_AT")
NO_BOOT = bool(os.environ.get("SB_NOBOOT"))


def sp(*p):
    return os.path.join(STATE, *p)


args = sys.argv[1:]
sub = sub2 = sub3 = ""
host = ""
k = 0
while k < len(args):
    a = args[k]
    if a in ("-I", "-H", "-U", "-P"):
        if a == "-H":
            host = args[k + 1]
        k += 2
        continue
    if a.startswith("-"):
        k += 1
        continue
    sub = a
    k += 1
    if k < len(args):
        sub2 = args[k]
        k += 1
    if k < len(args):
        sub3 = args[k]
    break


# The stub only impersonates this site's BMC (the IP in $BMC_IP). IPMI aimed at
# any other IP (e.g. the DUT itself) must fail, so discovery's default-cred
# probe can split BMC vs DUT inside a MAC block.
if host and host != (os.environ.get("BMC_IP") or "127.0.0.1"):
    sys.stderr.write("Unable to Open IPMI v2.0 RMCP+ session to bmc channel : "
                     "Unable to open LAN session\n")
    sys.exit(1)


def inproc_later(sec, fn):
    """Run fn() after sec; process must stay alive (threads die with it)."""
    def go():
        time.sleep(sec)
        fn()
    t = threading.Thread(target=go, daemon=True)
    t.start()


def subprocess_later(sec, check_path, write_path):
    """Survives the stub's exit: a separate interpreter sleeps, then writes
    the wall clock to write_path iff check_path still exists."""
    code = ("import time,os; time.sleep(%d); "
            "open(%r,'w').write(str(int(time.time()))) if os.path.exists(%r) else None"
            % (sec, write_path, check_path))
    subprocess.Popen([sys.executable, "-c", code], start_new_session=True)


# ---------------- Save & Exit tab model (vendor BIOS, verified 2026-10-28) ------
TABS = ["Main", "Advanced", "Platform Configuration", "Socket Configuration",
        "Server Mgmt", "Security", "Boot", "Save & Exit"]

# row 4..22 of the screen: (text, kind) ; kind: header/item/blank
MENU = [
    ("Save Options", "header"),                       # row 4
    ("Save Changes and Exit", "item"),                # row 5  (item 1)
    ("Discard Changes and Exit", "item"),             # row 6  (item 2)
    ("", "blank"),                                    # row 7
    ("Save Changes and Reset", "item"),               # row 8  (item 3)
    ("Discard Changes and Reset", "item"),            # row 9  (item 4)
    ("", "blank"),                                    # row 10
    ("Save Changes", "item"),                         # row 11 (item 5)
    ("Discard Changes", "item"),                      # row 12 (item 6)
    ("", "blank"),                                    # row 13
    ("Default Options", "header"),                    # row 14
    ("Restore Defaults", "item"),                     # row 15 (item 7)
    ("Save as User Defaults", "item"),                # row 16 (item 8)
    ("Restore User Defaults", "item"),                # row 17 (item 9)
    ("", "blank"),                                    # row 18
    ("Boot Override", "header"),                      # row 19
    ("Windows Boot Manager (P1: PLEXTOR PX-128G5Se)", "item"),  # row 20 (item 10)
    ("Ubuntu (P1: PLEXTOR PX-128G5Se)", "item"),      # row 21 (item 11)
]
# row index (0-based into MENU) of each selectable item, in cursor order
ITEM_ROWS = [1, 2, 4, 5, 7, 8, 11, 12, 13, 16, 17]
ITEM_DESCS = [
    "Exit system setup after saving the changes.",
    "Exit system setup without saving any changes.",
    "Reset the system after saving the changes.",
    "Reset system setup without saving any changes.",
    "Save Changes done so far to any of the setup option",
    "Discard Changes done so far",
    "Restore/Load Default values for all the setup options.",
    "Save the changes done so far as User Defaults.",
    "Restore the User Defaults to all the setup options.",
    None,  # item 10 (entry)
    None,  # item 11 (entry)
]
KEY_HELP = [">: Select Screen", "^v: Select Item", "Enter: Select",
            "+/-: Change Opt."]


def wrap(text, width=23):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w) if cur else w
    if cur:
        lines.append(cur)
    while len(lines) < 3:
        lines.append("")
    return lines[:3]


def render(out, tab, cursor, drift=False):
    """Full-screen redraw (real BIOS style: CUP per row, SGR bold on the
    highlighted item name and the title band)."""
    if drift:
        eff = (cursor + 2) % 11   # cursor drift emulation (nav-fail case)
    else:
        eff = cursor
    out.write("\x1b[H")
    # row 1: title band (bold)
    title = "Aptio Setup - AMI"
    out.write("\x1b[1;1H\x1b[1m" + " " * 32 + title + "\x1b[0m")
    # row 2: tab row (only the last few tabs shown, like the real frame)
    out.write("\x1b[2;1H")
    tabstr = ""
    for i, t in enumerate(TABS):
        mark = "<" if i == tab else " "
        tabstr += "%s%s  " % (mark, t)
    out.write(tabstr)
    # row 3: top border
    out.write("\x1b[3;1H/" + "-" * 85 + "+" + "-" * 32 + "\\")
    # rows 4..22: menu column + description/help panel
    panel = [KEY_HELP[0], KEY_HELP[1], KEY_HELP[2]]
    if tab == 7:
        if cursor < 9:
            panel = wrap(ITEM_DESCS[cursor])
        for ri in range(len(MENU)):
            row = ri + 4
            text, kind = MENU[ri]
            is_item = kind == "item"
            hl = is_item and ITEM_ROWS.index(ri) == eff
            pcol = 55
            border = 89
            ptext = panel[ri % 3]
            if hl:
                out.write("\x1b[%d;1H|  \x1b[1m%s\x1b[0m" % (row, text))
                pad = (pcol - 2) - (2 + len(text))
                out.write(" " * max(0, pad) + "| " +
                          ptext.ljust(border - pcol - 1) + "|")
            else:
                line = "|" + ("  " + text).ljust(pcol - 2) + "|"
                line += (" " + ptext).ljust(border - pcol - 1) + "|"
                out.write("\x1b[%d;1H%s" % (row, line))
    else:
        for ri in range(len(MENU)):
            row = ri + 4
            text = ("%s tab content (sandbox placeholder)" % TABS[tab]) if ri == 0 else ""
            out.write("\x1b[%d;1H|  %s%s" % (row, text, "|" if text else ""))
    # row 23: bottom border
    out.write("\x1b[23;1H\\" + "-" * 85 + "+" + "-" * 32 + "/")
    # row 24-25
    out.write("\x1b[24;1H                    Version 2.22.1282 Copyright (C) 2024 AMI")
    out.write("\x1b[25;1HBMC IP Address:   0.  0.  0.  0")
    out.flush()


def sol_activate():
    with open(sp("stub_env_dbg"), "w") as f:
        f.write("SB_NAVFAIL_AT=%r NOBOOT=%r\n" % (
            os.environ.get("SB_NAVFAIL_AT"), os.environ.get("SB_NOBOOT")))
    # Wait for a power event (warm reset OR cold power-on) that carries the
    # bootdev latch (setup). A power event without the latch = normal boot:
    # POST line only, then the SOL session ends (no setup on serial).
    # Freshness: markers left by an earlier cycle are ignored (mtime must
    # be after this SOL session opened), so cycle 2 does not start on a
    # stale event from cycle 1.
    t0 = time.time()
    started = False
    for _ in range(200):
        ev = ""
        if os.path.exists(sp("reset_at")) and os.path.getmtime(sp("reset_at")) >= t0:
            ev = "reset_at"
        elif os.path.exists(sp("poweron_at")) and os.path.getmtime(sp("poweron_at")) >= t0:
            ev = "poweron_at"
        if ev:
            for _ in range(20):
                if os.path.exists(sp("setup_pending")):
                    started = True
                    break
                time.sleep(0.15)
            break
        time.sleep(0.3)
    time.sleep(1)
    out = sys.stdout
    out.write("POST 2.22 (sandbox) CPU x86_64 RAM 32G\n")
    out.flush()
    if not started:
        # normal boot: no Aptio Setup text, session goes quiet
        return
    out.write("Aptio Setup Utility v2.22\n")
    out.write("  Main   Advanced   Platform Configuration   Socket Configuration"
              "   Server Mgmt   Security   Boot   Save & Exit\n")
    out.flush()
    tab = 0
    cursor = 0
    downs = 0
    csi = 0
    while True:
        b = sys.stdin.buffer.read(1)
        if not b:
            break
        c = b[0]
        if csi == 1:
            csi = 2 if c == ord("[") else 0
            continue
        if csi == 2:
            if c == ord("C"):
                if tab < 7:
                    tab += 1
                render(out, tab, cursor)
                csi = 0
            elif c == ord("B"):
                if tab == 7 and downs < 10:
                    cursor += 1
                    downs += 1
                drift = bool(NAVFAIL_AT and downs == int(NAVFAIL_AT) and tab == 7)
                with open(sp("stub_down_log"), "a") as f:
                    f.write("down=%d cursor=%d tab=%d drift=%s\n"
                            % (downs, cursor, tab, drift))
                render(out, tab, cursor, drift=drift)
                csi = 0
            else:
                csi = 3
            continue
        if csi == 3:
            if 0x40 <= c <= 0x7E:
                csi = 0
            continue
        if c == 0x1B:
            csi = 1
            continue
        if c == 0x0D:
            if tab == 7 and downs == 10:
                with open(sp("bootsed"), "w") as f:
                    f.write("ubuntu")
                try:
                    os.unlink(sp("reset_boots"))
                except FileNotFoundError:
                    pass
                out.write("\x1b[2J\x1b[1;1H\x1b[2J\x1b[1;1H")
                out.flush()
                if not NO_BOOT:
                    def efi():
                        time.sleep(1)
                        out.write("EFI stub: Loaded initrd from "
                                  "LINUX_EFI_INITRD_MEDIA_GUID (sandbox)\r\n")
                        out.flush()
                    inproc_later(1, efi)
                    inproc_later(BOOT_SECS, lambda: (
                        open(sp("boot_at"), "w").write(str(int(time.time())))))
            elif tab == 7 and downs == 9:
                with open(sp("bootsed"), "w") as f:
                    f.write("windows")
                try:
                    os.unlink(sp("reset_boots"))
                except FileNotFoundError:
                    pass
                out.write("\x1b[2J\x1b[1;1H\x1b[2J\x1b[1;1H")
                out.flush()
                if not NO_BOOT:
                    inproc_later(BOOT_SECS, lambda: (
                        open(sp("boot_at"), "w").write(str(int(time.time())))))
            elif tab == 7:
                out.write("Save configuration and exit?  Yes  No\r\n")
                out.flush()
            csi = 0


def _power_state():
    try:
        with open(sp("power")) as f:
            return f.read().strip() or "on"
    except OSError:
        return "on"


def _set_power(state):
    with open(sp("power"), "w") as f:
        f.write(state)


def _apply_bootdev_or_normal(marker_name):
    """Common power-event tail: if the bootdev latch is pending, arm a
    setup session (and consume the latch, like the real one-shot);
    otherwise it is a normal boot.
    SB_NOSUPE (case G): the FIRST latched power event drops the latch
    (models the real BIOS silently ignoring the one-shot, observed on
    vendor BIOS 2026-10-30); later attempts work."""
    with open(sp(marker_name), "w") as f:
        f.write(str(int(time.time())))
    try:
        os.unlink(sp("boot_at"))
    except FileNotFoundError:
        pass
    if (os.environ.get("SB_NOSUPE")
            and os.path.exists(sp("bootdev_latched"))
            and not os.path.exists(sp("nosupe_done"))):
        open(sp("nosupe_done"), "w").close()
        os.unlink(sp("bootdev_latched"))   # one-shot consumed but ignored
    if os.path.exists(sp("bootdev_latched")):
        open(sp("setup_pending"), "w").close()
        os.unlink(sp("bootdev_latched"))
    else:
        try:
            os.unlink(sp("setup_pending"))
        except FileNotFoundError:
            pass
        with open(sp("bootsed"), "w") as f:
            f.write("windows")   # normal boot = persistent first = windows
        with open(sp("reset_boots"), "w") as f:
            f.write("windows")
        if not os.environ.get("SB_NOBOOT"):
            subprocess_later(BOOT_SECS, sp("reset_boots"), sp("boot_at"))


def main():
    if sub == "sol" and sub2 == "deactivate":
        print("SOL session deactivated")
        return 0
    if sub == "sol" and sub2 == "activate":
        sol_activate()
        return 0
    if sub == "chassis" and sub2 == "bootdev":
        # latched while running (reset mode) or while off (clean mode)
        print("Set Boot Device Type to: Bios (%s)" % sub3)
        open(sp("bootdev_latched"), "w").close()
        return 0
    if sub == "chassis" and sub2 == "power" and sub3 == "reset":
        print("Chassis Power Control: Reset")
        _set_power("on")
        _apply_bootdev_or_normal("reset_at")
        return 0
    if sub == "chassis" and sub2 == "power" and sub3 == "off":
        print("Chassis Power Control: Down/Soft-Off")
        _set_power("off")
        try:
            os.unlink(sp("boot_at"))
        except FileNotFoundError:
            pass
        try:
            os.unlink(sp("setup_pending"))
        except FileNotFoundError:
            pass
        with open(sp("poweroff_at"), "w") as f:
            f.write(str(int(time.time())))
        return 0
    if sub == "chassis" and sub2 == "power" and sub3 == "on":
        print("Chassis Power Control: Up")
        _set_power("on")
        _apply_bootdev_or_normal("poweron_at")
        return 0
    if sub == "chassis" and sub2 == "power" and sub3 == "status":
        print("Chassis Power is %s" % ("on" if _power_state() == "on" else "off"))
        return 0
    if sub == "chassis" and sub2 == "status":
        print("System Power         : %s" % _power_state())
        return 0
    print("stub ipmitool: unhandled '%s %s %s'" % (sub, sub2, sub3))
    return 1


if __name__ == "__main__":
    sys.exit(main())
