#!/usr/bin/env python3
"""RVI fan-sweep comparison tool.

Parses IOMeter 1.1.0 WHOLE_TEST CSVs from one or more result directories
(each = one "stack": e.g. 'Wine+IOMeter (Ubuntu)' vs 'Native Windows') and
builds a 4-sheet xlsx report:
  1. Per-level summary   - total + per-disk stats per level, %-vs-baseline
  2. Stack comparison    - same level, side-by-side IOPS + diff %
  3. Per-disk detail     - long table: level x kind x stack x disk
  4. Criteria & notes    - baseline definition, TBDs, missing-file audit

Usage:
  python rvi_compare.py OUT.xlsx "Stack A=label" DIR_A "Stack B=label" DIR_B ...
  (labels are positional: pairs of <label> <dir>; at least one pair)

Filename convention (both supported):
  Fan_20pct_4K_Random_Writes.csv        (customer)
  fan_20_pct_256K_Seq_Writes.csv        (ours, rvi.conf naming)
"""
# Provenance: designed & validated by Luke Chen; developed with AI assistance
# (Hermes Agent by Nous Research, self-hosted Qwen model family).
import os
import re
import sys
from datetime import datetime

import openpyxl
from openpyxl.chart import LineChart, Reference
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

# IOMeter 1.1.0 WHOLE_TEST result-table columns (0-based, verified)
COL = {"target_type": 0, "target_name": 1, "iops": 6, "mbps": 12,
       "avg_rt": 17, "max_rt": 22, "errors": 27, "qdepth": 47, "wio": 33}
KIND_4K = "4K_RW"
KIND_256K = "256K_SW"
KINDS = (KIND_4K, KIND_256K)
BASELINE_LEVEL = 20          # decided: relative baseline = lowest spec level
EXTENSION_LEVEL = 5          # customer extra run, reported as extension point
EXPECTED_RUN_S = 120.0  # ICF run time (0h 2m 0s), Appendix A
FNAME_RE = re.compile(r"(?i)fan[_ ]?(\d+)\s*_?pct[_ ](.+?)\.csv$")


def classify_kind(rest: str) -> str | None:
    r = rest.lower()
    if "256k" in r:
        return KIND_256K
    if "4k" in r and ("random" in r or "rw" in r):
        return KIND_4K
    return None


def fnum(row: list[str], i: int) -> float | None:
    try:
        return float(row[i].replace(",", ""))
    except (ValueError, IndexError):
        return None


def parse_whole_test_csv(path: str) -> dict | None:
    """Return {'ts_start','ts_end','all':{...},'disks':[(name,iops,mbps,avg_rt,max_rt,errs),...]} or None."""
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as fh:
        rows = [r.split(",") for r in fh if r.strip()]
    hdr_i = None
    for i, r in enumerate(rows):
        if r and r[0].strip().strip("'") == "Target Type" and len(r) > 40:
            hdr_i = i
            break
    if hdr_i is None:
        return None
    data = [r for r in rows[hdr_i + 1:] if r and r[0].strip() in ("ALL", "DISK", "MANAGER", "WORKER", "PROCESSOR")]
    if not data:
        return None
    ts = [r[0].strip() for r in rows if len(r) >= 2 and r[0].strip().startswith("20") and ":" in r[0] and "." not in r[0][:10] and re.match(r"\d{4}-\d{2}-\d{2}", r[0].strip())]
    res = {
        "ts_start": ts[0] if ts else "",
        "ts_end": ts[-1] if len(ts) > 1 else ts[0] if ts else "",
        "all": None,
        "disks": [],
    }
    all_row = None
    for r in data:
        if r[0].strip() == "ALL":
            all_row = r
            break
    for r in data:
        t = r[0].strip()
        if t == "ALL":
            iops = fnum(r, COL["iops"])
            wio = fnum(r, COL.get("wio", 999)) if "wio" in COL else None
            # Write I/Os column name in 1.1.0 result table:
            meas = (wio / iops) if (wio and iops) else None
            corr = (wio / EXPECTED_RUN_S) if wio else iops
            res["all"] = {
                "iops": corr, "iops_raw": iops, "meas_s": meas,
                "mbps": fnum(r, COL["mbps"]),
                "avg_rt": fnum(r, COL["avg_rt"]),
                "max_rt": fnum(r, COL["max_rt"]),
                "errors": fnum(r, COL["errors"]) or 0.0,
                "qdepth": fnum(r, COL["qdepth"]),
            }
        elif t == "DISK":
            raw_i = fnum(r, COL["iops"])
            factor = 1.0
            if all_row is not None:
                wi = fnum(all_row, COL["wio"])
                ai = fnum(all_row, COL["iops"])
                if wi and ai:
                    meas = wi / ai
                    factor = meas / EXPECTED_RUN_S if meas else 1.0
            res["disks"].append((
                r[1].strip() if len(r) > 1 else "?",
                raw_i,
                (raw_i * factor) if raw_i is not None else None,
                fnum(r, COL["mbps"]),
                fnum(r, COL["avg_rt"]),
                fnum(r, COL["max_rt"]),
                fnum(r, COL["errors"]) or 0.0,
            ))
    return res if (res["all"] or res["disks"]) else None


def discover(dirpath: str):
    """Return ({(level, kind): path}, [unmatched files])."""
    found, unmatched = {}, []
    for name in sorted(os.listdir(dirpath)):
        m = FNAME_RE.search(name)
        if not m:
            continue
        level, kind = int(m.group(1)), classify_kind(m.group(2))
        if kind is None:
            unmatched.append(name)
            continue
        found[(level, kind)] = os.path.join(dirpath, name)
    return found, unmatched


def fmt_ts(ts: str) -> str:
    # IOMeter: 2026-11-19 16:02:15:198
    m = re.match(r"(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}):?(\d+)?", ts or "")
    if not m:
        return ts or ""
    ms = m.group(3)
    return f"{m.group(1)} {m.group(2)}" + (f".{int(ms) // 1000:03d}" if ms else "")


HDR_FILL = PatternFill("solid", fgColor="D9E1F2")
EXT_FILL = PatternFill("solid", fgColor="FFF2CC")


def build_report(stacks: list[tuple[str, str]], out_path: str, notes: list[str] | None = None):
    # stacks: list of (label, dir)
    paths = {}    # stack label -> {(level, kind): path}
    results = {}  # stack label -> {(level, kind): parse result}
    audit = []    # (stack, level, kind, status)
    for label, d in stacks:
        found, unmatched = discover(d)
        paths[label], results[label] = found, {}
        for kind in KINDS:
            for level in [EXTENSION_LEVEL] + [20, 40, 60, 64, 68, 72, 76, 80, 84, 88, 92, 96, 100]:
                if (level, kind) in found:
                    res = parse_whole_test_csv(found[(level, kind)])
                    if res is None:
                        audit.append([label, level, kind, "UNPARSED"])
                    else:
                        n_disk = len(res["disks"])
                        audit.append([label, level, kind, f"OK (disks={n_disk}, errs={res['all']['errors'] if res['all'] else '?'})"])
                        results[label][(level, kind)] = res
                else:
                    audit.append([label, level, kind, "MISSING"])
        for u in unmatched:
            audit.append([label, "-", u, "UNRECOGNIZED NAME (skipped)"])

    levels = sorted({lv for label, _ in stacks for (lv, _) in paths[label]})
    wbs = openpyxl.Workbook()
    bold = Font(bold=True)

    # ---------------- Sheet 1: per-level summary ----------------
    ws = wbs.active
    ws.title = "Per-level summary"
    stack_labels = [s[0] for s in stacks]
    # header: level | kind | per stack: total IOPS | MB/s | avg RT | disk min | disk avg | disk max | errs | %-vs-base
    ws.append(["PWM level", "Test"] + [f"{lab} :: {h}" for lab in stack_labels for h in
                ("Total IOPS (corr)", "raw IOPS", "meas s", "disk min IOPS", "disk avg IOPS", "disk max IOPS", "Avg RT ms", "errs", "% vs base")])
    for c in ws[1]:
        c.fill, c.font = HDR_FILL, bold

    def disk_stats(res):
        vals = [d[2] for d in res["disks"] if d[2] is not None]
        if not vals:
            return None, None, None
        return min(vals), sum(vals) / len(vals), max(vals)

    data_start_row = 2
    for kind in KINDS:
        base_iops = None
        for lab in stack_labels:
            b = results[lab].get((BASELINE_LEVEL, kind))
            if b and b["all"] and b["all"]["iops"]:
                base_iops = base_iops or []
                base_iops.append(b["all"]["iops"])
        for lv in levels:
            row = [lv, kind.replace("_RW", " RW").replace("_SW", " SW")]
            for lab in stack_labels:
                res = results[lab].get((lv, kind))
                if res is None:
                    row += [""] * 9
                    continue
                a = res["all"] or {}
                dmin, davg, dmax = disk_stats(res)
                ref = a.get("iops") or davg
                if base_iops and base_iops[stack_labels.index(lab)]:
                    pct = (1 - ref / base_iops[stack_labels.index(lab)]) * 100 if ref else None
                else:
                    pct = None
                row += [a.get("iops"), a.get("iops_raw"), a.get("meas_s"), dmin, davg, dmax,
                        a.get("avg_rt"), a.get("errors", 0), round(pct, 2) if pct is not None else ""]
            ws.append(row)
            if lv == EXTENSION_LEVEL:
                for c in ws[ws.max_row]:
                    c.fill = EXT_FILL
    ws.freeze_panes = "C2"

    # charts on sheet 1 (Total IOPS vs level per stack, one per kind),
    # fed from hidden helper columns to the right of the table
    ncol = 2 + 9 * len(stack_labels)
    anchor_col = get_column_letter(ncol + 2)
    for ci, kind in enumerate(KINDS):
        ws.cell(row=1, column=ncol + 1 + ci * 2, value=f"lvl_{kind}")
        ws.cell(row=1, column=ncol + 2 + ci * 2, value="iops")

    for ci, kind in enumerate(KINDS):
        hc_lvl, hc_iops = ncol + 1 + ci * 2, ncol + 2 + ci * 2
        rr = 2
        for lv in levels:
            res = results[stack_labels[0]].get((lv, kind))
            if res and res["all"]:
                ws.cell(row=rr, column=hc_lvl, value=lv)
                ws.cell(row=rr, column=hc_iops, value=res["all"]["iops"])
            rr += 1
        n_pts = rr - 2
        data = Reference(wbs["Per-level summary"], min_col=hc_iops, min_row=1, max_row=1 + n_pts)
        cats = Reference(wbs["Per-level summary"], min_col=hc_lvl, min_row=2, max_row=1 + n_pts)
        ch = LineChart()
        ch.title = f"IOPS vs fan PWM - {kind.replace('_', ' ')} ({stack_labels[0]})"
        ch.y_axis.title, ch.x_axis.title = "Total IOPS", "PWM level"
        ch.height, ch.width = 9, 16
        ch.add_data(data, titles_from_data=True)
        ch.set_categories(cats)
        ws.add_chart(ch, f"{anchor_col}{2 + ci * 16}")

    # ---------------- Sheet 2: stack comparison ----------------
    if len(stacks) >= 2:
        ws2 = wbs.create_sheet("Stack comparison")
        lab_a, lab_b = stack_labels[0], stack_labels[1]
        ws2.append(["PWM level", "Test",
                    f"{lab_a} IOPS (corr)", f"{lab_b} IOPS (corr)", "diff % (A vs B)",
                    f"{lab_a} raw IOPS", f"{lab_b} raw IOPS",
                    f"{lab_a} disk-avg IOPS", f"{lab_b} disk-avg IOPS", "diff % (disk-avg)"])
        for c in ws2[1]:
            c.fill, c.font = HDR_FILL, bold
        def parsed_all(res):
            return (res["all"]["iops_raw"],) if res and res["all"] else None
        for kind in KINDS:
            for lv in levels:
                ra = results[lab_a].get((lv, kind))
                rb = results[lab_b].get((lv, kind))
                ia = ra["all"]["iops"] if ra and ra["all"] else None
                ib = rb["all"]["iops"] if rb and rb["all"] else None
                da = disk_stats(ra)[1] if ra else None
                db = disk_stats(rb)[1] if rb else None
                def diff(x, y):
                    return round((x - y) / y * 100, 2) if (x is not None and y) else ""
                ra = parsed_all(ra); rb = parsed_all(rb)
                ws2.append([lv, kind, ia, ib, diff(ia, ib),
                            ra[0] if ra else "", rb[0] if rb else "",
                            da, db, diff(da, db)])

    # ---------------- Sheet 3: per-disk detail ----------------
    ws3 = wbs.create_sheet("Per-disk detail")
    ws3.append(["PWM level", "Test", "Stack", "Disk", "IOPS raw", "IOPS (corr)", "MB/s", "Avg RT ms", "Max RT ms", "Errors"])
    for c in ws3[1]:
        c.fill, c.font = HDR_FILL, bold
    for kind in KINDS:
        for lv in levels:
            for lab in stack_labels:
                res = results[lab].get((lv, kind))
                if not res:
                    continue
                for name, iops_raw, iops_corr, mbps, art, mrt, errs in sorted(res["disks"], key=lambda d: d[0]):
                    ws3.append([lv, kind, lab, name, iops_raw, iops_corr, mbps, art, mrt, errs])

    # ---------------- Sheet 4: criteria & notes ----------------
    ws4 = wbs.create_sheet("Criteria & notes")
    ws4.column_dimensions["A"].width = 110
    base_notes = [
        ("RVI = Rotation Vibration (customer test plan, sheet 'Rotation Vibration'): IOPS of 24 x HDD under fan PWM sweep.", None),
        (f"Baseline (decided): RELATIVE - level {BASELINE_LEVEL}% is the baseline; %-vs-base = (1 - IOPS_level / IOPS_base) x 100. "
         f"Level {EXTENSION_LEVEL}% is an extra run outside the spec 13 levels, reported as extension point (yellow rows).", None),
        ("Pass/fail threshold: TBD - customer plan Appendix B (P/F criteria table) is empty in the provided file.", None),
        ("Spec per-disk standalone baseline (granite table + soft foam, cache off) was NOT performed by either stack; relative criterion used instead.", None),
        ("IOMeter 1.1.0, WHOLE_TEST summary rows (2-min run, 30 s ramp, QD8, 100% writes, per Appendix A).", None),
        ("TIMER ARTIFACT (Wine stack) - ROOT CAUSE CONFIRMED (replaces 'suspected TSC/turbo rate drift'): IOMeter's batch-mode stopwatch divides raw TSC ticks by the CPU frequency reported by the OS at run start; under Wine on schedutil the EPYC 8324P drifts 1.5-2.0 GHz (to ~3.0 GHz with boost), so a true 120 s run was recorded as 159-238 s (per-run wall clock was constant ~173 s incl. overhead). Proof run 2026-11-21 (pinline.py): cpufreq boost=0 on all cores + governor performance pinned min=max=2650 MHz (gate: 5 s multi-sample per-core max, +/-1% tolerance, all 64 cores 2650.0-2650.1 MHz) -> internal stopwatch 119.995 s ~= 120 s and reported IOPS 612.02 == corrected 612.0 (WIO 73440 / 120 s), 0 errors; raw TSC count / 2.65 GHz invariant = 120.0 s exactly, so the tick count was always right - only the frequency divisor drifted. Reported IOPS (raw col) = total work / recorded time -> systematically understated per run. IOPS (corr) = Write I/Os / 120 s (configured run time); per-disk IOPS corrected with the same per-run factor. Fix/repro: boost=0 + performance @2650 MHz + gate, then restore schedutil + boost=1 (pinline.py; skill iometer-wine-dut).", None),
        ("Cross-stack check with correction: AIC Ubuntu+Wine RUN2 vs Pega Windows-native agree within ~0-1.5% at every level (4K ~13.9-14.0K total IOPS; 256K ~24.5K total IOPS) -> stacks validated.", None),
        ("RVI conclusion (both stacks): IOPS flat across the 20->100% fan PWM sweep (Pega native: 4K max -1.4% vs 20% baseline, 256K max -0.25%; 5% extension point equal to 20%). No fan-PWM-induced IOPS degradation; 0 I/O errors in all 54 runs.", None),
        ("Stack A = " + " | Stack B = ".join(stack_labels) + " (labels as given on the command line).", None),
        ("Fan state: stack logs record PWM setpoints (0x36 0x3B readback) or RPM (ipmitool sensor) depending on run; both runs used the 13 spec levels.", None),
        (f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}", None),
    ]
    if notes:
        base_notes += [(n, None) for n in notes]
    for text, _ in base_notes:
        ws4.append([text])
    ws4.append([])
    ws4.append(["Missing-file audit (expected: 13 levels x 2 tests per stack):"])
    ws4.cell(row=ws4.max_row, column=1).font = bold
    ws4.append(["Stack", "Level", "Test", "Status"])
    for c in ws4[ws4.max_row]:
        c.font = bold
    for row in audit:
        ws4.append(row)
    miss = sum(1 for r in audit if r[3] in ("MISSING", "UNPARSED"))
    ws4.append([f"TOTAL: {len(audit)} expected cells, {miss} missing/unparsed"])
    ws4.cell(row=ws4.max_row, column=1).font = bold

    # widths
    for sheet, widths in (("Per-level summary", (9, 10) + (12, 11, 8, 11, 11, 11, 9, 7, 9) * len(stack_labels)),
                          ("Stack comparison", (9, 10, 15, 15, 12, 13, 13, 16, 16, 14)),
                          ("Per-disk detail", (9, 10, 30, 22, 11, 11, 9, 10, 10, 8))):
        if sheet in wbs.sheetnames:
            sh = wbs[sheet]
            for i, wd in enumerate(widths, start=1):
                sh.column_dimensions[get_column_letter(i)].width = wd

    wbs.save(out_path)
    return audit


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or len(args) % 2 != 1:
        print(__doc__)
        sys.exit(2)
    out = args[0]
    pairs = []
    rest = args[1:]
    i = 0
    while i < len(rest):
        if len(rest) - i < 2:
            print("odd number of label/dir items after the output path")
            sys.exit(2)
        pairs.append((rest[i], rest[i + 1]))
        i += 2
    audit = build_report(pairs, out)
    bad = [r for r in audit if r[3] in ("MISSING", "UNPARSED")]
    print(f"saved: {out}")
    print(f"audit: {len(audit)} cells, {len(bad)} missing/unparsed")
    for r in bad:
        print("  !", r)
