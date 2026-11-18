#!/usr/bin/env python3
# =============================================================================
# 30_report.py — post-sweep summary for the RVI fan sweep.
#
# READ-ONLY against RESULT_DIR (the 26 raw IOMeter CSVs are never modified).
# Writes only to REPORT_DIR:
#   summary_4K_Random.csv   level x slot/worker -> mean IOPS
#   summary_256K_Seq.csv    same for 256K sequential
#   audit_missing.csv       expected-but-missing result files
#   errors_summary.txt      condensed dmesg I/O-error evidence (if any)
#
# NOTE: IOMeter CSV column names are calibrated against the preflight
# smoke CSV. If a file cannot be parsed it is flagged in audit_missing.csv
# as UNPARSED instead of guessing.
# Provenance: designed & validated by Luke Chen; developed with AI assistance
# (Hermes Agent by Nous Research, self-hosted Qwen model family).
# =============================================================================

import csv
import glob
import os
import re
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))


def load_conf(path):
    """Minimal KEY=VALUE parser for rvi.conf (comments via #, optional quotes).
    Also expands $VAR / ${VAR} references from within the conf itself."""
    conf = {}
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            v = v.strip()
            if v.startswith('"'):
                end = v.find('"', 1)
                v = v[1:end] if end != -1 else v[1:]
            elif v.startswith("'"):
                end = v.find("'", 1)
                v = v[1:end] if end != -1 else v[1:]
            else:
                v = v.split("#", 1)[0].strip()
            conf[k.strip()] = v

    def expand(val, depth=0):
        if depth > 10 or "$" not in val:
            return val
        def sub(m):
            name = m.group(1) or m.group(2)
            return conf.get(name, m.group(0))
        return re.sub(r"\$\{(\w+)\}|\$(\w+)", sub, val)

    for k in conf:
        conf[k] = expand(conf[k])
    return conf


def parse_iometer_csv(path):
    """Return list of (worker_name, iops_float) summary rows, or None if unparseable.

    Finds the header row (a row containing a worker-ish column AND an IOPS-ish
    column) and averages the IOPS values per worker over all data rows.
    """
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as fh:
        rows = [r for r in csv.reader(fh) if any(c.strip() for c in r)]
    if not rows:
        return None

    header_idx = None
    worker_col = iops_col = None
    for i, row in enumerate(rows):
        low = [c.strip().lower() for c in row]
        # IOMeter 1.1.0 CSVs identify targets by "Target Name" (not "Worker
        # Name"); accept both so older/newer exports both parse.
        w = next((j for j, c in enumerate(low) if re.search(r"target\s*name|\bworker\b", c)), None)
        p = next((j for j, c in enumerate(low) if re.search(r"i/o.*per.*sec|iops", c)), None)
        if w is not None and p is not None:
            header_idx, worker_col, iops_col = i, w, p
            break
    if header_idx is None:
        return None

    acc = {}
    for row in rows[header_idx + 1:]:
        if len(row) <= max(worker_col, iops_col):
            continue
        worker = row[worker_col].strip()
        if not worker:
            continue
        try:
            iops = float(row[iops_col].replace(",", ""))
        except ValueError:
            continue
        acc.setdefault(worker, []).append(iops)

    out = []
    for worker, vals in sorted(acc.items(), key=lambda kv: kv[0]):
        if vals:
            out.append((worker, sum(vals) / len(vals), len(vals)))
    return out or None


def main():
    conf = load_conf(os.path.join(HERE, "rvi.conf"))
    result_dir = conf["RESULT_DIR"]
    report_dir = conf["REPORT_DIR"]
    min_level = int(conf.get("MIN_PWM_LEVEL", "0"))
    levels = [int(x) for x in conf.get("PWM_LEVELS", "").split()]
    fmt_4k = conf["CSV_4K_FMT"]
    fmt_seq = conf["CSV_SEQ_FMT"]
    log_dir = conf["LOG_DIR"]

    os.makedirs(report_dir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M")

    missing = []
    summaries = {"4K_Random": [], "256K_Seq": []}

    for kind, fmt, key in (
        ("4K_Random", fmt_4k, "4K_Random"),
        ("256K_Seq", fmt_seq, "256K_Seq"),
    ):
        for L in levels:
            if L < min_level:
                continue
            fname = fmt % L
            fpath = os.path.join(result_dir, fname)
            if not os.path.isfile(fpath):
                missing.append([fname, L, kind, "MISSING"])
                continue
            parsed = parse_iometer_csv(fpath)
            if parsed is None:
                missing.append([fname, L, kind, "UNPARSED"])
                continue
            for worker, iops, n in parsed:
                summaries[key].append([L, worker, round(iops, 1), n])

    # --- write summaries ----------------------------------------------------------
    for key, path in (
        ("4K_Random", os.path.join(report_dir, "summary_4K_Random.csv")),
        ("256K_Seq", os.path.join(report_dir, "summary_256K_Seq.csv")),
    ):
        with open(path, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["fan_pwm_pct", "worker", "mean_iops", "samples"])
            w.writerows(summaries[key])

    # --- audit ---------------------------------------------------------------------
    audit = os.path.join(report_dir, "audit_missing.csv")
    with open(audit, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["file", "level", "test", "status"])
        w.writerows(missing)

    # --- errors evidence -------------------------------------------------------------
    err_src = os.path.join(log_dir, "errors.log")
    err_dst = os.path.join(report_dir, "errors_summary.txt")
    if os.path.isfile(err_src):
        with open(err_src, "r", encoding="utf-8", errors="replace") as fh:
            content = fh.read()
        with open(err_dst, "w", encoding="utf-8") as fh:
            fh.write(f"RVI errors.log excerpt — generated {stamp}\n")
            fh.write(f"source: {err_src}\n{'=' * 60}\n")
            fh.write(content)
    else:
        with open(err_dst, "w", encoding="utf-8") as fh:
            fh.write("no errors.log — no I/O-error events captured during sweep\n")

    # --- console report ----------------------------------------------------------------
    expected = sum(2 for L in levels if L >= min_level)
    present = len(summaries["4K_Random"]) + len(summaries["256K_Seq"])
    print("=" * 60)
    print(f"RVI report generated: {report_dir}")
    print(f"  worker rows parsed: {present}")
    print(f"  files missing/unparsed: {len(missing)}")
    for m in missing:
        print(f"    - {m[0]} (level {m[1]}, {m[2]}): {m[3]}")
    print("=" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
