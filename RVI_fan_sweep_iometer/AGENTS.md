# AGENTS.md — RVI fan-sweep automation (IOMeter batch mode)

## What this is
Automation for the "Rotation Vibration" (RVI) IOPS-vs-fan-PWM test on a
24-bay JBOD storage DUT. Sweeps 13 fan PWM levels (20→100) via the local
BMC (`ipmitool raw 0x36 0xFA/0xFB`); at each level runs both IOMeter 1.1.0
profiles — 4K random writes and 256K sequential writes (QD8, 30 s ramp,
2 min) — across all 24 drives simultaneously, producing one CSV per level
per test (26 raw CSVs).

Stack: Ubuntu 24.04 + native IOMeter `dynamo` agent (raw `/dev/sdX`) +
Wine + `iometer.exe` batch mode (`/c <icf> /r <csv> /t <s>`, Xvfb headless).

## How to run
- Sandbox (no hardware): `bash test_30_report.sh && bash test_fan_logic.sh`
- Real hardware (root on the DUT):
  ```bash
  cd /root/rvi
  bash 00_preflight.sh     # must PASS (WCE=0 check + 24-disk smoke)
  nohup bash 10_fan_sweep.sh >> logs/sweep_nohup.log 2>&1 &
  ```
  See `README.md` "Operator runbook" for the full step-by-step.

## Invariants (never break)
- The 26 raw result CSVs in `results/` are NEVER modified or deleted by any
  tool in this repo (report tool is read-only against them).
- Fan state MUST be restored to the pre-sweep original (saved in
  `fan_original.txt`) on every exit path, including hard aborts.
- Fan set/readback mismatch after retries = hard abort (never continue with
  unknown fan state).
- Drive list changing mid-sweep = hard abort (scene preserved for evidence).
- WCE (write cache) must be 0 on all test drives before any run — preflight
  enforces this; do not bypass.
- BMC SET command length is firmware-specific (16 PWM bytes on the
  validated firmware; other lengths are rejected 0xC7) — see rvi.conf.

## Layout
| Path | Purpose |
|---|---|
| `rvi.conf` | all tunables (levels, disks, paths, timeouts, retries) |
| `00_preflight.sh` | pre-test self-check incl. batch-mode smoke |
| `10_fan_sweep.sh` | main loop (idempotent resume) |
| `20_iometer_run.sh` | shared helpers + IOMeter batch runner (sourced only) |
| `30_report.py` | post-sweep summary → `report/` (raw CSVs untouched) |
| `make_icf.py` | generates the 4 ICFs from a GUI-saved reference template |
| `make_1w.py` | converts the 24-worker ICFs to the customer 1-worker/24-target form (`*_1w.icf`) |
| `run3_driver.py` | pinned per-run sweep driver (pin+gate, WCE check, A/B gate, auto-restore) |
| `rvi_compare.py` | cross-stack xlsx report generator (Windows side) |
| `setup_fresh_dut.sh` | one-shot bootstrap of a fresh Ubuntu Server into a ready RVI DUT |
| `icf/` | the 4 ICF files (2 test profiles + 2 smoke) + 2 customer 1-worker ICFs (`*_1w.icf`) |
| `test_*.sh` | sandbox tests (report parser, fan logic) |

## Provenance (machine-readable)
```yaml
generated_by: Hermes Agent (Nous Research) — self-hosted Qwen model family
designed_by: Luke Chen
verified: 2026-11-17/18 full 13-level sweep on 24-bay JBOD DUT,
          26/26 CSV, 24/24 DISK rows per run, 0 I/O errors, FAIL_COUNT=0;
          2026-11-21 RUN3 pinned 1-worker sweep 26/26, 0 I/O errors,
          A/B gate 4K 1.32% / 256K 0.16%, FAIL_COUNT=0
```
