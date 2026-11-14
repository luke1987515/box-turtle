# ac_temp_protect — BMC inlet-temp AC protection (no auto power restore)

Cuts AC power when a selected BMC temperature sensor stays at or above a
threshold for a configurable window — then **stays cut**. Power restore is
always a deliberate, manual action. Built for long thermal tests where an
over-temperature must not silently re-energize the DUT.
中文版本：[README.zh-TW.md](README.zh-TW.md)

## Provenance

Designed and validated by **luke1987515** (AIC DQA); developed with the
assistance of an AI agent (**Hermes Agent** by Nous Research; self-hosted
**Qwen** model family — earlier development sessions may have used other
models).

Verified before publishing (**2026-11-14**): sandbox **7/7** functional
scenarios PASS (TRIPPED die path; relay-OFF warning + continue; all three
`clean` branches incl. `--yes` with post-restore relay re-read; setup
pre-clear display — relay emulated by a file flag, zero hardware) +
real-hardware rollout on **3/3** AC servers (CentOS 7/8): `bash -n` 3/3,
dry-run rounds PASS, `clean` 3/3 PASS (a stale TRIPPED from a real
2026-10-30 trip was resolved with the relay already ON, logged as
restored-externally), relay confirmed **ON 3/3** by register read.
**Zero relay writes**: the power-off/on helpers were never executed on real
hardware during verification.

## What it does

- Reads one BMC temperature sensor (`ipmitool sdr list`) every
  `POLL_SECONDS`.
- `temp >= THRESHOLD`: hot-seconds accumulate; when the accumulated time
  reaches `WINDOW_SECONDS` the AC is cut via the power-off helper and the
  state becomes `TRIPPED`.
- **Never restores power automatically.** After a trip, monitoring
  continues (reads keep flowing) and every round re-checks the physical
  relay; if the cut has been released from outside (harness or manual), it
  warns loudly that protection has been defeated.
- BMC read failure: no action; the accumulation clock pauses (the gap is
  not counted into the window).
- Startup check (read-only): state `TRIPPED` → refuses to start and points
  at `clean`; relay reads OFF but state `NORMAL` → big warning (the DUT's
  AC may still be cut) but the run proceeds.
- `clean`: shows status + relay; if the relay is OFF it asks
  "restore power? [y/N]" (`--yes` skips the prompt); only on `y` does it
  run the power-on helper **and** re-read the relay — only if the relay
  reads ON is the state reset; relay ON while `TRIPPED` → logged as
  "restored externally". It then unconditionally resets the state to the
  NORMAL baseline (`ACCUM=0`, `TRIP_AT` cleared). It never touches `conf`,
  and the log is append-only.

## Files (created next to the script)

| File | Purpose |
|---|---|
| `ac_temp_protect.conf` | Settings produced by `setup` (**includes the BMC password**; chmod 600 — never commit) |
| `ac_temp_protect.state` | Run state (`NORMAL`/`TRIPPED`, accumulators) — survives restarts |
| `ac_temp_protect.log` | Log (Taipei-time timestamps) |
| `.ac_temp_protect_raw` | Last raw `ipmitool` output (diagnostics) |

## Required AC relay helpers (not included)

The script drives the AC through three helper scripts in `$AC_HELPER_DIR`
(env-overridable; default `/ED/QT_Cycling_Multi-SVR-AC`). They are
site-specific hardware drivers and are **intentionally not published** —
bring your own. Requirements:

- state reader (`013.read.gpiod7_state.sh`): read-only relay state; its
  stdout must contain `AC Power ON` or `AC Power OFF`;
- power off (`021.ac_power_off.sh`): cut the AC;
- power on (`022.ac_power_on.sh`): restore the AC;
- all are executed **with their own directory as CWD** (they call sibling
  tools by relative path); exit 0 = success.

The names above match the layout this was built in; change the constants
at the top of the script (or override `AC_HELPER_DIR`) if yours differ.

## Usage

```bash
./ac_temp_protect.sh setup            # one-time: BMC IP/creds, pick a temp sensor,
                                      # threshold / window / poll interval
./ac_temp_protect.sh run              # monitor (foreground; Ctrl+C to stop)
./ac_temp_protect.sh run --dry-run    # trial: logs only, never cuts power
./ac_temp_protect.sh status           # show current state + relay state
./ac_temp_protect.sh power-on         # manual power restore after a trip
./ac_temp_protect.sh clean            # reset state to the NORMAL baseline
                                      # (asks about restore if the relay is OFF;
                                      #  --yes skips the prompt)
```

Suggested flow: `setup` → `run --dry-run` for a while → `run` for real.

## Safety notes

- Use `--dry-run` first; a dry run never touches the relay.
- After a trip, nothing re-energizes the DUT on its own — that is the point.
- `ac_temp_protect.conf` holds real BMC credentials: chmod 600, never
  commit, never paste it into logs or tickets.
- Log timestamps are `Asia/Taipei`.
