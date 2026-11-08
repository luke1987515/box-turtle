#!/usr/bin/env python3
"""Local (no hardware) verification for the site-profile rework --
test plan item 1 of DESIGN-site-profiles.md section 8:
profile parser + resolution order + gate logic (+ the nav-check
derivation that feeds the layout gate).

Run:   python3 tests/test_site_profiles.py     (from the os_flip/ dir)
Exit:  0 = all pass | 1 = failures
Needs: python3 only (no pty -- sol_boot.py imports pty lazily).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
import sol_boot  # noqa: E402  (must import cleanly on any host)

PY = sys.executable

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


# ---------------- helpers ----------------

def valid_profile(site="x", bmc_ip="1.2.3.4", mac="AA:BB:CC:DD:EE:FF"):
    return (
        "site=%s\n" % site
        + "bmc_ip=%s\n" % bmc_ip
        + "dut_mac=%s\n" % mac
        + "firmware=Test_1.0\n"
        + "discovered_at=2026-11-07T00:00+08:00\n"
        + "item_count=3\n"
        + "item_1=Save Changes and Exit::a1\n"
        + "item_2=Discard Changes and Exit::b2\n"
        + "item_3=Some Linux Entry::-\n"
        + "target_windows_down=1\n"
        + "target_linux_down=2\n"
        + "target_linux_name=linux\n"
    )


def write(tmp, text, fname="p.conf"):
    f = os.path.join(tmp, fname)
    with open(f, "w") as fh:
        fh.write(text)
    return f


def run_cli(mode, *args, env=None):
    e = None
    if env:
        e = dict(os.environ)
        e.update(env)
    r = subprocess.run([PY, os.path.join(ROOT, "sol_boot.py"), mode] + list(args),
                       capture_output=True, text=True, timeout=60, env=e)
    return r.returncode, r.stdout, r.stderr


# ---------------- 1. parser: the two repo baselines ----------------

def t_parse_tucana():
    p, err = sol_boot.load_profile(os.path.join(ROOT, "sites", "tucana.conf"))
    assert err is None, "parse error: %s" % err
    assert p["site"] == "tucana"
    assert p["bmc_ip"] == "192.0.2.1"
    assert p["dut_mac"] == "00:00:00:00:00:00"
    assert p["item_count"] == 11 and len(p["items"]) == 11
    assert p["target_windows_down"] == 9
    assert p["target_linux_down"] == 10
    assert p["target_linux_name"] == "ubuntu"
    assert p["power_entry"] == "cold_on"
    assert p["items"][0][0] == "Save Changes and Exit"
    assert p["items"][1][0] == "Discard Changes and Exit"
    assert p["items"][9][0] == "Windows Boot Manager"
    assert p["items"][10][0] == "Ubuntu"
    assert p["items"][9][1] == "-"          # Boot Override rows: no desc
    assert p["items"][1][1] != "-"          # exit items carry a desc fragment
    # the targets must land on the right rows (design: item_N = N-1 DOWNs)
    assert p["items"][p["target_windows_down"]][0] == "Windows Boot Manager"
    assert p["items"][p["target_linux_down"]][0] == "Ubuntu"


def t_parse_aic_1x():
    p, err = sol_boot.load_profile(os.path.join(ROOT, "sites", "aic_1x.conf"))
    assert err is None, "parse error: %s" % err
    assert p["site"] == "aic_1x"
    assert p["bmc_ip"] == "192.168.1.116"
    assert p["dut_mac"] == "00:15:b2:b0:51:17"
    assert p["firmware"] == "Tuca_0.09.0"
    assert p["item_count"] == 15 and len(p["items"]) == 15
    assert p["target_windows_down"] == 9
    assert p["target_linux_down"] == 13
    # cold boot IGNORES the one-shot on this platform -> warm reset entry
    assert p["power_entry"] == "warm_reset"
    # item order = the 2026-11-06 calibration (item_N = N-1 DOWNs)
    assert p["items"][0][0] == "Save Changes and Exit"
    assert p["items"][1][0] == "Discard Changes and Exit"
    assert p["items"][9][0].startswith("Windows Boot Manager")
    assert p["items"][13][0].startswith("ubuntu")
    assert p["items"][14][0].startswith("Launch EFI Shell")
    # the targets must land on the right rows
    assert p["items"][p["target_windows_down"]][0].startswith("Windows Boot Manager")
    assert p["items"][p["target_linux_down"]][0].startswith("ubuntu")
    # the first-item gate target: item_2 = items[1]
    assert p["items"][1][1] != "-"


def t_squash():
    assert sol_boot.squash("Save  Changes\tand Exit") == "savechangesandexit"
    assert sol_boot.squash("UEFI: PXE IPv4 Intel") == "uefi:pxeipv4intel"
    assert sol_boot.squash("Ubuntu ") == "ubuntu"
    assert sol_boot.squash("") == ""
    assert sol_boot.squash(None) == ""


# ---------------- 2. parser: malformed inputs ----------------

def t_malformed():
    base = valid_profile()
    with tempfile.TemporaryDirectory() as tmp:
        p, err = sol_boot.load_profile(write(tmp, base))
        assert err is None, "control profile should parse: %s" % err
        # power_entry omitted -> default cold_on (old profiles keep working)
        assert p["power_entry"] == "cold_on", p.get("power_entry")
        cases = [
            (base.replace("site=x", "sitex=x"), "unknown key"),
            (base.replace("dut_mac=", "dut_mac_typo="), "unknown key (typo)"),
            (base.replace("item_2=Discard Changes and Exit::b2\n", ""), "missing item"),
            (base + "item_2=Duplicate::dup\n", "duplicate item"),
            (base.replace("item_2=Discard Changes and Exit::b2", "item_2=NoSeparator"), "no ::"),
            (base.replace("item_2=Discard Changes and Exit::b2", "item_2=::b2"), "empty name"),
            (base.replace("target_windows_down=1", "target_windows_down=3"), "target out of range"),
            (base.replace("target_linux_down=2", "target_linux_down=0"), "target zero"),
            (base.replace("item_count=3", "item_count=4"), "item_count mismatch"),
            (base.replace("dut_mac=AA:BB:CC:DD:EE:FF", "dut_mac=nope"), "bad MAC"),
            (base.replace("bmc_ip=1.2.3.4", "bmc_ip=300.1.2.3"), "bad IP"),
            (base.replace("bmc_ip=1.2.3.4", "bmc_ip=abc"), "non-numeric IP"),
            (base + "power_entry=hot_swap\n", "bad power_entry value"),
        ]
        for mutated, why in cases:
            p, err = sol_boot.load_profile(write(tmp, mutated))
            assert p is None and err, "%s should be rejected, got %r / %r" % (why, p, err)
            assert "unparseable" not in (err or "")  # sanity: it is a real reason
        # missing file
        p, err = sol_boot.load_profile(os.path.join(tmp, "nope.conf"))
        assert p is None and err


def t_duplicate_squash_names():
    text = (valid_profile()
            .replace("item_1=Save Changes and Exit::a1", "item_1=Save Changes and Exit::a1")
            .replace("item_2=Discard Changes and Exit::b2", "item_2=save changes and exit::b2"))
    with tempfile.TemporaryDirectory() as tmp:
        p, err = sol_boot.load_profile(write(tmp, text))
        assert p is None and err and "squashed name" in err, \
            "same-squash names must be rejected: %r" % err


# ---------------- 3. resolution order ----------------

def t_resolve():
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "profiles"))
        os.makedirs(os.path.join(tmp, "sites"))
        open(os.path.join(tmp, "sites", "s1.conf"), "w").write(valid_profile("s1"))
        open(os.path.join(tmp, "sites", "s2.conf"), "w").write(valid_profile("s2"))
        open(os.path.join(tmp, "profiles", "s2.conf"), "w").write(
            valid_profile("s2", bmc_ip="9.9.9.9"))
        # sites-only -> sites
        p, src = sol_boot.resolve_profile("s1", tmp)
        assert src == "sites" and p.endswith("s1.conf"), (p, src)
        # both -> profiles wins, and it really is the local file
        p, src = sol_boot.resolve_profile("s2", tmp)
        assert src == "profiles", src
        pr, err = sol_boot.load_profile(p)
        assert err is None and pr["bmc_ip"] == "9.9.9.9", pr
        # neither -> None
        assert sol_boot.resolve_profile("nope", tmp) == (None, None)
        # traversal / weird names rejected
        assert sol_boot.resolve_profile("../sites/s1", tmp) == (None, None)
        assert sol_boot.resolve_profile("a/b", tmp) == (None, None)
        assert sol_boot.resolve_profile("a\\b", tmp) == (None, None)
        assert sol_boot.resolve_profile("", tmp) == (None, None)
        # no dirs at all
        assert sol_boot.resolve_profile("s1", os.path.join(tmp, "empty")) == (None, None)


def t_resolve_cli():
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "sites"))
        open(os.path.join(tmp, "sites", "s1.conf"), "w").write(valid_profile("s1"))
        rc, out, err = run_cli("resolve", "s1", tmp)
        assert rc == 0 and "s1.conf" in out, (rc, out, err)
        rc, out, err = run_cli("resolve", "nope", tmp)
        assert rc == 2 and "s1" in err, (rc, out, err)  # stderr lists available
        rc, out, err = run_cli("resolve", "../sites/s1", tmp)
        assert rc == 2, (rc, out, err)


# ---------------- 4. the identity gate ----------------

def t_gate():
    with tempfile.TemporaryDirectory() as tmp:
        prof = write(tmp, valid_profile())
        rc, out, err = run_cli("gate", prof, "1.2.3.4", "AA:BB:CC:DD:EE:FF", "x")
        assert rc == 0, (rc, out, err)
        # MAC compare is case-insensitive
        rc, out, err = run_cli("gate", prof, "1.2.3.4", "aa:bb:cc:dd:ee:ff", "x")
        assert rc == 0, (rc, out, err)
        # site-name compare
        rc, out, err = run_cli("gate", prof, "1.2.3.4", "aa:bb:cc:dd:ee:ff", "y")
        assert rc == 3 and "site" in (out + err).lower(), (rc, out, err)
        # bmc mismatch -> 3
        rc, out, err = run_cli("gate", prof, "5.6.7.8", "aa:bb:cc:dd:ee:ff", "x")
        assert rc == 3 and "bmc_ip" in (out + err), (rc, out, err)
        # mac mismatch -> 3
        rc, out, err = run_cli("gate", prof, "1.2.3.4", "11:22:33:44:55:66", "x")
        assert rc == 3 and "dut_mac" in (out + err), (rc, out, err)
        # both mismatched -> one message with both
        rc, out, err = run_cli("gate", prof, "5.6.7.8", "11:22:33:44:55:66", "x")
        assert rc == 3 and "bmc_ip" in (out + err) and "dut_mac" in (out + err), (rc, out, err)
        # missing file -> 2
        rc, out, err = run_cli("gate", os.path.join(tmp, "missing.conf"),
                               "1.2.3.4", "aa:bb:cc:dd:ee:ff", "x")
        assert rc == 2, (rc, out, err)
        # unparseable file -> 2
        bad = write(tmp, "this is not a profile", "bad.conf")
        rc, out, err = run_cli("gate", bad, "1.2.3.4", "aa:bb:cc:dd:ee:ff", "x")
        assert rc == 2, (rc, out, err)
        # env side empty (legacy: no MAC in env) -> gate skips that half
        rc, out, err = run_cli("gate", prof, "1.2.3.4", "", "x")
        assert rc == 0, (rc, out, err)


# ---------------- 5. nav-check derivation (the layout gate inputs) -------

def t_nav_checks():
    p, err = sol_boot.load_profile(os.path.join(ROOT, "sites", "aic_1x.conf"))
    assert err is None, err
    items = p["items"]
    names = [nm for nm, _ in items]
    # 'Save Changes' (item_5): negs = the two 'Save Changes and ...' supersets
    sq, negs = sol_boot.hl_checks("Save Changes", names)
    assert sq == "savechanges"
    assert sol_boot.squash("Save Changes and Exit") in negs
    assert sol_boot.squash("Save Changes and Reset") in negs
    assert len(negs) == 2, negs
    # 'Discard Changes' (item_6): negs = the two 'Discard Changes and ...'
    sq, negs = sol_boot.hl_checks("Discard Changes", names)
    assert sq == "discardchanges" and len(negs) == 2, (sq, negs)
    # 'Discard Changes and Exit' (item_2): a superset itself -> no negs
    sq, negs = sol_boot.hl_checks("Discard Changes and Exit", names)
    assert negs == [], negs
    # a Boot Override name: no supersets
    sq, negs = sol_boot.hl_checks("Windows Boot Manager", names)
    assert negs == [], negs
    # step_checks: the gate step (item_2) has name + desc checks
    checks = sol_boot.step_checks(1, items)
    kinds = [k for _, k, _ in checks]
    assert "hl2" in kinds and "panel2" in kinds, checks
    # a Boot Override step (item_10 = windows on aic_1x): name check only
    checks = sol_boot.step_checks(9, items)
    assert [k for _, k, _ in checks] == ["hl2"], checks
    # tucana: 'Ubuntu' must not be neg'd by any superset
    p, err = sol_boot.load_profile(os.path.join(ROOT, "sites", "tucana.conf"))
    assert err is None, err
    sq, negs = sol_boot.hl_checks("Ubuntu", [nm for nm, _ in p["items"]])
    assert negs == [], negs


# ---------------- 6. profile build/roundtrip (what --discover writes) ----

def t_build_roundtrip():
    items = [("Save Changes and Exit", "-"),
             ("Discard Changes and Exit", "without saving any changes"),
             ("Windows Boot Manager (SSD X)", "-"),
             ("ubuntu (SSD X)", "-")]
    text = sol_boot.build_profile_text("testsite", "10.0.0.2", "AA:BB:CC:DD:EE:FF",
                                       "Test_9.9", items, 2, 3, "ubuntu",
                                       power_entry="warm_reset")
    with tempfile.TemporaryDirectory() as tmp:
        f = write(tmp, text)
        p, err = sol_boot.load_profile(f)
        assert err is None, err
        assert p["site"] == "testsite"
        assert p["bmc_ip"] == "10.0.0.2"
        assert p["dut_mac"] == "aa:bb:cc:dd:ee:ff"
        assert p["item_count"] == 4 and len(p["items"]) == 4
        assert p["items"] == items
        assert p["target_windows_down"] == 2
        assert p["target_linux_down"] == 3
        assert p["target_linux_name"] == "ubuntu"
        assert p["power_entry"] == "warm_reset", p.get("power_entry")
        assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}[+-]\d{2}:\d{2}$",
                        p["discovered_at"]), p["discovered_at"]
        # atomic writer leaves no .tmp behind
        sol_boot.write_profile_atomic(os.path.join(tmp, "sub", "q.conf"), text)
        assert os.path.isfile(os.path.join(tmp, "sub", "q.conf"))
        assert not os.path.exists(os.path.join(tmp, "sub", "q.conf.tmp"))


def t_sniff_firmware():
    assert sol_boot.sniff_firmware(b"x Tuca_0.09.0 y") == "Tuca_0.09.0"
    assert sol_boot.sniff_firmware(b"nothing here") == "unknown"


# ---------------- 7. syntax smoke of the shell entry point ---------------

def t_shell_syntax():
    r = subprocess.run(["bash", "-n", os.path.join(ROOT, "os_flip.sh")],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    # the subcommand strings exist in the script
    with open(os.path.join(ROOT, "os_flip.sh")) as fh:
        s = fh.read()
    for token in ("--check", "--discover", "SITE_NAME", "LINUX_NAME",
                  "resolve_profile", "profile_gate", "acquire_lock",
                  "wait_dut_ping"):
        assert token in s, "missing %r in os_flip.sh" % token


# ---------------- 8. CLI argc gates (2026-11-07 field failure) -----------
# --discover once printed the usage and exited 2 in under a second because
# the argv length check was off by one (the SOL phase never started, the
# DUT was left off). These tests pin the exact arg counts os_flip.sh sends.

USAGE_MARK = "Modes (argv[1])"

def _args14():
    # the exact positional set os_flip.sh passes after the mode name
    return ["192.0.2.2", "u", "p", "t1", "t2", "t3", "120", "240",
            "192.0.2.10", "abort.flag"]


def t_cli_argc():
    bad = []
    # cycle: exactly 13 positionals (os_flip.sh's call)
    for n in (12, 14):
        a = (_args14() + ["linux", "on",
                          os.path.join(ROOT, "sites", "aic_1x.conf"),
                          "extra"])[:n]
        assert len(a) == n, a
        rc, out, err = run_cli("cycle", *a)
        if not (rc == 2 and USAGE_MARK in out):
            bad.append("cycle argc=%d -> rc=%d" % (n, rc))
    # 13 positionals + unparseable profile = past the argc gate, fails at
    # load_profile (proves the gate no longer eats the real call)
    with tempfile.TemporaryDirectory() as tmp:
        f = write(tmp, "not a profile", "bad.conf")
    rc, out, err = run_cli("cycle", *_args14(), "linux", "on", f)
    if not (rc == 2 and "profile unparseable" in (out + err)
            and USAGE_MARK not in out):
        bad.append("cycle argc=13 good -> rc=%d %r" % (rc, (out + err)[:120]))
    # discover: exactly 15 positionals (os_flip.sh's call, incl. POWERENTRY)
    for n in (14, 16):
        a = (_args14() + ["out.conf", "s1", "ubuntu",
                          "AA:BB:CC:DD:EE:FF", "cold_on", "extra"])[:n]
        assert len(a) == n, a
        rc, out, err = run_cli("discover", *a)
        if not (rc == 2 and USAGE_MARK in out):
            bad.append("discover argc=%d -> rc=%d" % (n, rc))
    # 15 positionals + bad site name = past the argc gate (fails fast, no SOL)
    rc, out, err = run_cli("discover", *_args14(), "o.conf", "../x",
                           "ubuntu", "AA:BB:CC:DD:EE:FF", "cold_on")
    if not (rc == 2 and "bad site name" in (out + err)
            and USAGE_MARK not in out):
        bad.append("discover argc=15 good -> rc=%d %r" % (rc, (out + err)[:120]))
    # 15 positionals + empty LINUX_NAME = past the argc gate
    rc, out, err = run_cli("discover", *_args14(), "o.conf", "s1", "",
                           "AA:BB:CC:DD:EE:FF", "cold_on")
    if not (rc == 2 and "LINUX_NAME is empty" in (out + err)
            and USAGE_MARK not in out):
        bad.append("discover empty LINUX_NAME -> rc=%d %r" % (rc, (out + err)[:120]))
    # 15 positionals + bad POWERENTRY = past the argc gate, rejected
    rc, out, err = run_cli("discover", *_args14(), "o.conf", "s1", "ubuntu",
                           "AA:BB:CC:DD:EE:FF", "hot_swap")
    if not (rc == 2 and "bad POWERENTRY" in (out + err)
            and USAGE_MARK not in out):
        bad.append("discover bad POWERENTRY -> rc=%d %r" % (rc, (out + err)[:120]))
    # setup-exit: exactly 9 positionals (recovery helper). Only the BAD
    # argc cases are exercised: the correct-argc call has no pre-hardware
    # validation, so on a POSIX host it would really open SOL against the
    # (fake) BMC. n=8/n=10 pin the check (a wrong check would let one of
    # these through the gate).
    for n in (8, 10):
        a = (_args14()[:9] + ["extra"])[:n]
        assert len(a) == n, a
        rc, out, err = run_cli("setup-exit", *a)
        if not (rc == 2 and USAGE_MARK in out):
            bad.append("setup-exit argc=%d -> rc=%d" % (n, rc))
    assert not bad, "; ".join(bad)


def main():
    print("== os_flip site-profile local verification (test plan item 1) ==")
    print("python: %s\n" % PY)
    check("parse baseline: sites/tucana.conf", t_parse_tucana)
    check("parse baseline: sites/aic_1x.conf", t_parse_aic_1x)
    check("squash rule", t_squash)
    check("parser rejects malformed profiles (12 cases)", t_malformed)
    check("parser rejects duplicate squashed names", t_duplicate_squash_names)
    check("resolution order profiles/ > sites/ > none", t_resolve)
    check("resolve CLI (path out / available list / traversal)", t_resolve_cli)
    check("identity gate (0/2/3, case-insensitive MAC, site compare)", t_gate)
    check("nav-check derivation (hl negs from the profile itself)", t_nav_checks)
    check("profile build + roundtrip + atomic write", t_build_roundtrip)
    check("firmware sniff (informational)", t_sniff_firmware)
    check("os_flip.sh bash -n + subcommand tokens", t_shell_syntax)
    check("CLI argc gates (cycle=13, discover=15 positionals)", t_cli_argc)
    print()
    if FAILS:
        print("FAILED: %d/%d -> %s" % (len(FAILS), 13, ", ".join(FAILS)))
        return 1
    print("ALL PASS (13/13)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
