# RVI Fan-Sweep Automation — 24-bay JBOD storage DUT

Automates the customer "Rotation Vibration" (RVI) IOPS-vs-fan-PWM test:
sweep 13 fan PWM levels (20→100%), and at each level run **both** IOMeter
profiles (4K Random Writes + 256K Sequential Writes) on **all drives
simultaneously**, saving one CSV per level per test (26 CSVs total).

Stack (all on the DUT, per design decision "Option A"):
Ubuntu 24.04.1 + native IOMeter 1.1.0 **dynamo** agent (raw `/dev/sdX`) +
**Wine** + `iometer.exe` **batch mode** (`/c …/r …/t …`, no GUI clicks).
Fan control via local `ipmitool raw 0x36 0xFA/0xFB` (vendor BMC).

## Provenance

Designed and validated by Luke Chen; developed with the assistance of an AI
agent (Hermes Agent by Nous Research; self-hosted Qwen model family — earlier
development sessions may have used other models).

Verification record: full 13-level sweep on the 24-bay JBOD DUT
(2026-11-17/18): 26/26 CSVs, 24/24 DISK rows per run, 0 I/O errors, fan
set/verified 13/13, fan state restored and verified at the end; preflight
smoke24 rc=0 with 24/24 DISK rows in ~81 s. FAIL_COUNT=0.

## Files

| File | Role |
|---|---|
| `rvi.conf` | all tunables (levels, paths, timeouts, retries) |
| `00_preflight.sh` | pre-test self-check incl. batch-mode **smoke test** |
| `10_fan_sweep.sh` | main loop (fan set → verify → settle → 2 ICF runs per level) |
| `20_iometer_run.sh` | helpers + IOMeter batch runner (sourced, not run directly) |
| `30_report.py` | post-sweep summary into `report/` (raw CSVs untouched) |

## Prerequisites (on the DUT, root)

```bash
apt install -y wine64 xvfb ipmitool sdparm smartmontools
# IOMeter 1.1.0 (Intel open source):
#   iometer.exe  -> /opt/iometer/iometer.exe
#   dynamo (Linux build) -> /opt/iometer/dynamo  (chmod +x)
# NOTE: wine must be invoked as `wine64` directly — the `wine` symlink
# fails with "could not exec the wine loader" on this install.
# NOTE: EULA is suppressed by seeding HKCU\Software\iometer.org\Iometer\Settings\
# Version=1.1.0 in the wine registry (ensure_eula in 20_iometer_run.sh).
mkdir -p /root/rvi/icf /root/rvi/results /root/rvi/logs /root/rvi/report
```

## ICFs (generated, not hand-edited)

`make_icf.py` generates all four from the GUI-saved reference template
(`ref_minimal.icf`); run on the DUT:

```bash
python3 make_icf.py /root/rvi/icf --template <ref_minimal.icf> --manager-ip 127.0.0.1
```

- `4K_Random_Writes.icf` — 4 KB, 100% random writes, QD8, 30 s ramp, 2 min
- `256K_Seq_Writes.icf` — 256 KB, 100% sequential writes, QD8, 30 s ramp, 2 min
- `smoke.icf` — 10 s, 1 worker (sdb only)
- `smoke24.icf` — 60 s, all 24 workers (preflight end-to-end check)

One DISK worker per drive, one target per worker → per-disk rows in the CSV.
Manager name `rvi-dut` @ 127.0.0.1 must match `dynamo -n rvi-dut`.

## Run

```bash
cd /root/rvi
bash 00_preflight.sh     # must PASS (incl. batch-mode smoke test)
nohup bash 10_fan_sweep.sh >> logs/sweep_nohup.log 2>&1 &
# ~85 min for 13 levels; safe to re-run after any interruption (idempotent resume)
```

After the sweep: `report/` contains `summary_4K_Random.csv`,
`summary_256K_Seq.csv`, `audit_missing.csv`, `errors_summary.txt`.
The 26 raw CSVs stay in `results/` untouched.

## Operator runbook (HDD-swap scenario)

For the technician running the sweep after the customer-specified HDDs are
installed (all as root on the DUT):

```bash
# 1. Confirm the 24 data disks. If the names are NOT sdb..sdy,
#    update TEST_DISKS in rvi.conf first.
lsblk

# 2. Preflight — must PASS (checks WCE=0 on all drives + 24-disk smoke).
#    New drives may ship with WCE=1: `sdparm --set WCE=0 /dev/sdX` per
#    drive, then re-run preflight.
cd /root/rvi
bash 00_preflight.sh

# 3. Start the sweep (detached; ~95 min for 13 levels).
nohup bash 10_fan_sweep.sh >> logs/sweep_nohup.log 2>&1 &

# 4. Monitor progress (fan_ok / run_start / run_ok / sweep_done events).
tail -f logs/fan_timeline.log

# 5. Verify completion: expect 26.
ls results/fan_*.csv | wc -l

# 6. Report + fan restoration check (first two levels should read 3c 3c
#    = 60% 60% on this machine).
ls report/
ipmitool raw 0x36 0xFB
```

## Error policy (summary)

- Fan set/readback mismatch → retries ×3 → **hard abort** (state unknown)
- IOMeter run fail/timeout/short CSV → retry level (≤ 2) → record failure,
  **continue** sweep; re-run script later to retry only the missing runs
- Drive list changes mid-sweep → **hard abort** (spec failure event, scene preserved)
- dmesg I/O errors → logged to `errors.log`, test continues (evidence, not verdict)

## Verified on the DUT (2026-11-17)

- **Fan protocol**: SET = `0x36 0xFA 0x00` + exactly **16** PWM bytes
  (any other length → rsp 0xC7 "Request data length invalid"). Only value[0]
  takes effect — it drives BOTH physical fans (system + PSU); values 1–15
  are ignored. The 14-byte form in the requirements doc does not work on
  this firmware. READ = `0x36 0xFB`, 34 bytes; fan levels at 0-based
  indices 2 (exact) and 18 (±1 drift). See rvi.conf for the full note.
- **Drive set**: 24 JBOD data bays sdb–sdy; /dev/nvme0n1 = OS boot disk and
  /dev/sda = 0B BMC virtual disk are excluded (`TEST_DISKS` in rvi.conf).
- **Write cache**: hdparm -W does not work behind the mpt3sas HBA; preflight
  uses `sdparm --get/--set WCE` (drives shipped with WCE=1 — now 0).
- **Batch mode**: preflight smoke (24-disk, 60 s) passes through the
  production code path — rc=0, 24/24 DISK rows, 0 errors, ~81 s.
- **Wine**: EULA skipped via registry seed; wine64 direct; Xvfb :99 headless.

## Still open (confirm with the platform vendor)

1. System/PSU design minimum PWM (`MIN_PWM_LEVEL`, default 0 = run all 13)
2. Final CSV naming (currently `fan_40_pct_4K_Random_Writes.csv`)
3. Whether the vibration fixture is mounted for the run (IOPS data is only
   meaningful as RVI evidence when the shaker is running)
