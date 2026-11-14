# AGENTS.md

Operating guidance for AI agents (and humans) working in this directory.

## What this is

`ac_temp_protect.sh` cuts AC power when one BMC temperature sensor stays
at/above a threshold for a configured window, then **stays cut**: power
restore is only a deliberate manual action (`power-on`, or `clean` with an
explicit yes). It polls the BMC via `ipmitool sdr list`, keeps state in a
flat file, and drives the AC relay through three external helper scripts
in `$AC_HELPER_DIR` (site-specific; not published here).

## Running it

```bash
./ac_temp_protect.sh setup            # interactive: BMC IP/creds, sensor pick,
                                      # threshold / window (min) / poll (s)
./ac_temp_protect.sh run              # foreground monitor; Ctrl+C to stop
./ac_temp_protect.sh run --dry-run    # logs only; never touches the relay
./ac_temp_protect.sh status           # state + relay (read-only)
./ac_temp_protect.sh power-on         # manual restore after a trip
./ac_temp_protect.sh clean            # reset state to NORMAL baseline;
                                      # prompts to restore if relay is OFF
                                      # (--yes skips the prompt)
```

Sandbox-style verification (no hardware): point `AC_HELPER_DIR` at a stub
directory whose three helpers read/write a local flag file and print
`AC Power ON` / `AC Power OFF`; then exercise the matrix: TRIPPED die
path, relay-OFF warning, all `clean` branches.

## Invariants (never break)

- **Never restore AC power automatically.** Restore happens only via an
  explicit `power-on` or an explicit `clean` yes (prompt or `--yes`).
- **Never cut power in `--dry-run`.**
- `ac_temp_protect.conf` is a **secret** (real BMC credentials): chmod 600,
  never commit it, never print it, never let it into logs or tickets.
- While the state is `TRIPPED`, `run` must refuse to start and point at
  `clean` — it must not silently continue an old trip.
- The state reset after a failed restore must NOT happen: a failed
  power-on helper leaves the state untouched (die, keep state).
- Relay hardware I/O goes only through the three helpers — never
  re-implement register/UART writes in this script.

## Provenance

```
generated_by : AI-assisted development — Hermes Agent (Nous Research)
designed_by  : luke1987515 (requirements, environment decisions, acceptance)
model        : Qwen (self-hosted; earlier sessions may have used other models)
verified     : 2026-11-14 — sandbox 7/7 scenarios PASS (flag-file relay
               stub, zero hardware); real-hardware rollout 3/3 AC servers
               (CentOS 7/8): bash -n 3/3, dry-run rounds PASS, clean 3/3
               (stale TRIPPED from a 2026-10-30 real trip resolved, relay
               already ON); relay confirmed ON 3/3; zero relay writes —
               power-off/on helpers never executed on real hardware
```
