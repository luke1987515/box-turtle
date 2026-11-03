# AGENTS.md

Operating guidance for AI agents (and humans) working in this directory.

## What this is

`os_flip` is a deterministic dual-OS (e.g. Windows Server 2022 + Ubuntu 24.04
on one disk) **UEFI one-shot Boot Override** cycle tester for AIC servers.
Each cycle: clean/warm shutdown -> latch `chassis bootdev bios option=efiboot`
while power is off -> cold power on -> drive the BMC **SOL** console (pty)
through the UEFI setup menu (verified key path: RIGHT x7 -> DOWN x9/x10 ->
ENTER) -> wait for the DUT on the LAN (SOL stream + ping) -> identify the
booted OS (SOL "EFI stub" hint + SSH probe + hostname) -> collect system
info. Every cycle is fully logged under `$WORK_DIR/os_flip_<ts>/`.

## Running it

```bash
# Sandbox (no hardware; stubbed ssh/ping/ipmitool/ip in sandbox/bin/):
./sandbox/run_case.sh A    # cases A..L; see sandbox/run_case.sh

# Real hardware (Linux runner: bash, ip, ping, ipmitool, python3 + pexpect,
# layer-2 reachability to DUT and BMC):
cp os_flip.env.example os_flip.env    # fill in, chmod 600
./discovery.sh                        # first run: locate DUT/BMC, ask creds
./os_flip.sh 10                       # reset mode (legacy warm reset)
SHUTDOWN_MODE=clean ./os_flip.sh 10   # clean mode (graceful SSH shutdown,
                                      # bootdev latched while power is off)
./ac_cycle.sh                         # one real AC cycle (relay; graceful
                                      # shutdown by default; PRE_SHUTDOWN=0 =
                                      # legacy hard cut, non-Windows only)
SHUTDOWN_MODE=clean ./os_flip.sh 10   # clean mode (graceful SSH shutdown,
                                      # bootdev latched while power is off)
```

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
- The ~24-byte screen clear after ENTER on a Boot Override entry is the BIOS
  **handoff**, not "no response" — after it, send nothing and never issue an
  abort reset (an abort reset after handoff kills the target boot).

## Layout

- `os_flip.sh` — main driver (cycles, identification, collection, logging)
- `ac_cycle.sh` — one real AC power cycle (relay; graceful shutdown default)
- `sol_boot.py` — SOL/pty boot-override driver (the verified key path lives here)
- `discovery.sh` — DUT/BMC discovery (ARP/MAC scan), one-time credential setup
- `ssh_cmd.py` — small ssh helper used by the driver
- `sandbox/` — stubbed test harness (cases A..H) with copies of the scripts

## Provenance

```
generated_by : AI-assisted development — Hermes Agent (Nous Research)
designed_by  : luke1987515 (requirements, environment decisions, acceptance)
model        : Qwen3.8-27B (self-hosted, 4-bit quant); earlier sessions may
               have used other models
verified     : 2026-11-01 — sandbox cases + real hardware 10/10 cycles PASS;
               2026-11-02 — real hardware 10/10 os_flip + 3/3 ac_cycle AC
               cycles PASS (TUCANA); sandbox 12/12 cases (A..L)
               (FAIL_COUNT=0, persistent boot order unchanged)
```
