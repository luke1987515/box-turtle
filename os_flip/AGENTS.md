# AGENTS.md

Operating guidance for AI agents (and humans) working in this directory.

## What this is

`os_flip` is a deterministic dual-OS (e.g. Windows Server 2022 + Ubuntu 24.04
on one disk) **UEFI one-shot Boot Override** cycle tester for AIC servers.
Each cycle: clean/warm shutdown -> latch `chassis bootdev bios option=efiboot`
while power is off -> cold power on -> drive the BMC **SOL** console (pty)
through the UEFI setup menu (profile-driven key path: RIGHT until the
"Save & Exit" tab -> DOWN x <profile target> -> ENTER, with a live item_2
verify after the first DOWN) -> wait for the DUT on the LAN (SOL stream +
ping) -> identify the booted OS (SOL "EFI stub" hint + SSH probe +
hostname) -> collect system info. Every cycle is fully logged under
`$WORK_DIR/os_flip_<ts>/`.

## Running it

```bash
# Sandbox (no hardware; stubbed ssh/ping/ipmitool/ip in sandbox/bin/):
./sandbox/run_case.sh A    # cases A..L; see sandbox/run_case.sh

# Real hardware (Linux runner: bash, ip, ping, ipmitool, python3 + pexpect,
# layer-2 reachability to DUT and BMC):
cp os_flip.env.example os_flip.env    # fill in, chmod 600
./discovery.sh                        # first run: locate DUT/BMC, ask creds
./os_flip.sh --check                  # readiness only (SSH/BMC/ping/env/profile)
./os_flip.sh --discover               # one-time site calibration (~5 min)
./os_flip.sh 10                       # 10 cycles (entry mode per the
                                      # profile's power_entry; SHUTDOWN_MODE
                                      # only applies when it says cold_on)
SHUTDOWN_MODE=clean ./os_flip.sh 10   # (profile cold_on) graceful SSH
                                      # shutdown, bootdev latched while off
./ac_cycle.sh                         # one real AC cycle (relay; graceful
                                      # shutdown by default; PRE_SHUTDOWN=0 =
                                      # legacy hard cut, non-Windows only)
```

`SITE_NAME` (env) selects the profile: `profiles/<SITE>.conf` (local,
gitignored) wins over `sites/<SITE>.conf` (repo baseline). Without a
profile the cycle exits 2 — run `--discover` first.

## Invariants (never break)

- **Never write the persistent UEFI boot order.** Only one-shot overrides
  (`chassis bootdev ... option=efiboot`); each is consumed after one boot.
  A run must end with the persistent order unchanged.
- **`os_flip.env` is a secret** (real IPs, credentials). Gitignored; never
  commit it, print it, or let it into logs.
- **SOL (BMC serial-over-LAN pty) is the only console control channel.** Do
  not invent alternate console paths (no IPMI keyboard, no virtual media).
- **The DUT's IP drifts (DHCP).** Resolve it by MAC (`DUT_MAC`) via the ARP
  scan in `discovery.sh`; never hard-code an IP.
- **Failures abort, never flail.** Nav-verify failure -> ENTER is never sent,
  SOL closed, plain reset to normal boot, run aborts. Never leave the machine
  in UEFI setup or a custom boot state.
- **The profile is read-only for `--check` and the cycle; `--discover` is
  the only phase that writes it** (atomic .tmp+rename into `profiles/`;
  `sites/` baselines are never touched). Identity gate (profile
  bmc_ip/dut_mac/site vs env) before any power action; layout gate (live
  item_2 name+desc after the first DOWN) before ENTER. `firmware=` is
  informational, never a gate. The profile's `power_entry` (schema v1.1)
  is the single source of truth for how UEFI is entered: `cold_on`
  (default: clean shutdown + latch-while-off + cold power on) or
  `warm_reset` (bootdev while running + warm reset — required on
  platforms like aic_1x/Tuca_0.09.0 that ignore the one-shot on a cold
  boot; verified 2026-11-07). `SHUTDOWN_MODE` only applies when the
  profile says `cold_on`.
- The ~24-byte screen clear after ENTER on a Boot Override entry is the BIOS
  **handoff**, not "no response" — after it, send nothing and never issue an
  abort reset (an abort reset after handoff kills the target boot).

## Layout

- `os_flip.sh` — main driver (cycles, identification, collection, logging)
- `ac_cycle.sh` — one real AC power cycle (relay; graceful shutdown default)
- `sol_boot.py` — SOL/pty boot-override driver (profile-driven nav, --discover)
- `discovery.sh` — DUT/BMC discovery (ARP/MAC scan), one-time credential setup
- `ssh_cmd.py` — small ssh helper used by the driver
- `sites/` — repo baseline profiles (no secrets: test-LAN IP/MAC only)
- `tests/test_site_profiles.py` — local verification (parser/resolution/gate)
- `sandbox/` — stubbed test harness (cases A..H) with copies of the scripts

## Provenance

```
generated_by : AI-assisted development — Hermes Agent (Nous Research)
designed_by  : luke1987515 (requirements, environment decisions, acceptance)
model        : Qwen3.8-27B (self-hosted, 4-bit quant); earlier sessions may
               have used other models
verified     : 2026-11-01 — sandbox cases + real hardware 10/10 cycles PASS;
               2026-11-02 — real hardware 10/10 os_flip + 3/3 ac_cycle AC
               cycles PASS (dual-OS DUT); sandbox 12/12 cases (A..L)
               (FAIL_COUNT=0, persistent boot order unchanged)
```
