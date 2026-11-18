#!/usr/bin/env python3
# =============================================================================
# make_icf.py — generate RVI test ICF files for IOMeter 1.1.0 batch mode
#
# ICF = plain text (verified against a real file saved by IOMeter 1.1.0 GUI and
# against the 1.1.0 source: Worker::SaveConfig, PageSetup, ManagerList).
#
# Customer RVI spec (test plan, sheet "Rotation Vibration", Appendix A):
#   Profile 4K : 4KB block, 100% random, 100% writes, QD8, 30s ramp, 2min run
#   Profile SEQ: 256KB block, 100% sequential, 100% writes, QD8, 30s ramp, 2min
#
# Topology: manager 'rvi-dut' @ 127.0.0.1 (dynamo running locally on the DUT,
# launched with: dynamo -n rvi-dut -i 127.0.0.1 -m 127.0.0.1). One DISK worker
# per drive; each worker gets exactly one target (sdb..sdy) and exactly one
# access spec (the profile spec). This yields per-disk IOPS in the CSV.
#
# Usage:
#   make_icf.py <outdir> [--disks sdb sdc ...] [--manager-ip 127.0.0.1]
#
# Generates:
#   4K_Random_Writes.icf   256K_Seq_Writes.icf   smoke.icf (10s, 1 worker)
#   smoke24.icf            60s, 10s ramp, ALL disks (preflight end-to-end check)
# Provenance: designed & validated by Luke Chen; developed with AI assistance
# (Hermes Agent by Nous Research, self-hosted Qwen model family).
# =============================================================================
import argparse
import os
import sys

# Access spec names must match EXACTLY the names in the ACCESS SPECIFICATIONS
# section of the reference template (see ref_minimal.icf).
SPEC_4K = "4 KiB aligned; 0% Read; 100% random"   # 4096,100,0,100,0,1,4096,0
SPEC_SEQ = "256 KiB; 0% Read; 0% random"          # 262144,100,0,0,0,1,0,0

DISKS_ABC = [f"sd{c}" for c in "bcdefghijklmnopqrstuvwxyz"]
# DUT: sdb..sdy (24 drives, verified /proc/partitions 2026-11-18)
DEFAULT_DISKS = DISKS_ABC[:24]

MANAGER_NAME = "rvi-dut"
QUEUE_DEPTH = 8
RAMP_S = 30
RUN_MIN = 2
SMOKE_RUN_S = 10
SMOKE_RAMP_S = 5


def worker_block(n: int, disk: str, spec: str) -> list:
    return [
        "'Worker",
        f"\tWorker {n}",
        "'Worker type",
        "\tDISK",
        "'Default target settings for worker",
        "'Number of outstanding IOs,test connection rate,transactions per connection,use fixed seed,fixed seed value",
        f"\t{QUEUE_DEPTH},DISABLED,1,DISABLED,0",
        "'Disk maximum size,starting sector,Data pattern",
        "\t0,0,0",
        "'End default target settings for worker",
        "'Assigned access specs",
        f"\t{spec}",
        "'End assigned access specs",
        "'Target assignments",
        "'Target",
        f"\t{disk}",
        "'Target type",
        "\tDISK",
        "'End target",
        "'End target assignments",
        "'End worker",
    ]


def build_icf(template: str, desc: str, hours: int, minutes: int, seconds: int,
              ramp: int, disks: list, spec: str, manager_ip: str) -> str:
    out = template.splitlines(keepends=False)

    # --- patch TEST SETUP values -------------------------------------------
    i = 0
    while i < len(out):
        line = out[i]
        if line.startswith("'Test Description"):
            out[i + 1] = "\t" + desc
        elif line.startswith("'Run Time"):
            # value line is two lines after the key (key, header comment, value)
            # template: 'Run Time / 'hours minutes seconds / \t0 0 0
            if i + 2 < len(out) and out[i + 2].startswith("\t"):
                out[i + 2] = f"\t{hours}          {minutes}          {seconds}"
        elif line.startswith("'Ramp Up Time"):
            if i + 1 < len(out) and out[i + 1].startswith("\t"):
                out[i + 1] = f"\t{ramp}"
        i += 1

    # cut everything from 'MANAGER LIST onward; we rebuild it
    cut = None
    for i, line in enumerate(out):
        if line.startswith("'MANAGER LIST"):
            cut = i
            break
    if cut is None:
        sys.exit("ERROR: template missing 'MANAGER LIST section")
    head = out[:cut]

    # --- rebuild MANAGER LIST ----------------------------------------------
    mg = []
    mg.append("'MANAGER LIST ==================================================================")
    mg.append("'Manager ID, manager name")
    mg.append(f"\t1,{MANAGER_NAME}")
    mg.append("'Manager network address")
    mg.append(f"\t{manager_ip}")
    for n, disk in enumerate(disks, start=1):
        mg.extend(worker_block(n, disk, spec))
    mg.append("'End manager")
    mg.append("'END manager list")
    mg.append("Version 1.1.0 ")

    text = "\r\n".join(head) + "\r\n" + "\r\n".join(mg) + "\r\n"
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--template", required=True, help="ref_minimal.icf (GUI-saved reference)")
    ap.add_argument("--disks", nargs="+", default=DEFAULT_DISKS)
    ap.add_argument("--manager-ip", default="127.0.0.1")
    a = ap.parse_args()

    with open(a.template, "r", encoding="ascii") as f:
        template = f.read()

    os.makedirs(a.outdir, exist_ok=True)

    targets = {
        "4K_Random_Writes.icf": build_icf(
            template, "RVI 4K random writes QD8", 0, RUN_MIN, 0, RAMP_S,
            a.disks, SPEC_4K, a.manager_ip),
        "256K_Seq_Writes.icf": build_icf(
            template, "RVI 256K sequential writes QD8", 0, RUN_MIN, 0, RAMP_S,
            a.disks, SPEC_SEQ, a.manager_ip),
        "smoke.icf": build_icf(
            template, "RVI smoke test 10s", 0, 0, SMOKE_RUN_S, SMOKE_RAMP_S,
            [a.disks[0]], SPEC_4K, a.manager_ip),
        "smoke24.icf": build_icf(
            template, "RVI smoke24 test 60s", 0, 1, 0, 10,
            a.disks, SPEC_4K, a.manager_ip),
    }
    for name, text in targets.items():
        path = os.path.join(a.outdir, name)
        with open(path, "w", encoding="ascii", newline="") as f:
            f.write(text)
        print(f"wrote {path} ({len(text)} bytes)")
    print(f"disks ({len(a.disks)}): {' '.join(a.disks)}")
    print(f"manager: {MANAGER_NAME} @ {a.manager_ip}")


if __name__ == "__main__":
    main()
