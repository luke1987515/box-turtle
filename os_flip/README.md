# os_flip — dual-OS Boot Override cycle test

Automated reliability test for a dual-OS DUT (e.g. **Windows Server 2022 +
Ubuntu 24.04** on one disk): cycles one-shot UEFI **Boot Override** switching
between the two OSes, verifies which OS actually booted, and collects that
OS's system info — every cycle fully logged.

The one-shot override never touches the **persistent** boot order; each cycle
consumes its override, so the run ends on the last booted OS with the
persistent order unchanged.

## Provenance

Designed and validated by **luke1987515**; developed with the assistance of an
AI agent (**Hermes Agent** by Nous Research; self-hosted **Qwen3.8-27B**
model — earlier development sessions may have used other models).

Verified before publishing: sandbox **8/8** test cases + real-hardware
**10/10** cycle PASS run on **2026-11-01** (FAIL_COUNT=0; persistent boot
order unchanged; machine left on the last booted OS).

## How a cycle works

```
clean shutdown via SSH (or legacy warm reset)
  -> wait for System Power: off
  -> latch `chassis bootdev bios option=efiboot` while power is off
  -> cold power on
  -> SOL pty: wait "Aptio Setup" -> RIGHT x7 (Save & Exit tab)
     -> DOWN x10 (Ubuntu) / DOWN x9 (Windows) -> ENTER  (one-shot handoff)
  -> stream SOL + poll ping until the DUT is UP
  -> identify the booted OS (SOL "EFI stub" hint + SSH probe + hostname)
  -> collect that OS's system info
```

Boot confirmation is **SOL stream + ping**; ping is the ground truth (SOL may
be silent during boot on some platforms). OS identification runs in retry
rounds because the SSH daemon can come up well after the first ping.

## Requirements (on the runner)

- Linux with `bash`, `ip`, `ping`, `ipmitool` (RMCP+ to the DUT's BMC)
- `python3` with `pexpect` (the SOL/SSH drivers are Python)
- Layer-2 reachability to the DUT and BMC (same broadcast domain)
- BMC web/API defaults or credentials (any vendor with SOL; the key path was
  validated on an AMI Aptio UEFI)

## Quick start

```bash
git clone <this repo>
cd os_flip
./discovery.sh        # first run: finds the DUT/BMC, asks passwords once
./os_flip.sh 10       # 10 cycles
```

On first run, `discovery.sh` fills the missing site config into
**`os_flip.env`** (created next to the scripts, `chmod 600`, gitignored) and
never asks again. Resolution priority:

```
CLI environment variables  >  ./os_flip.env  >  interactive discovery
```

## Discovery (first run)

Two identity-discovery modes, automatic in this order:

1. **Power-off fingerprint** — when `RELAY_OFF_CMD` + `RELAY_ON_CMD` are set
   (each a full shell command your runner uses to cut/restore the DUT's AC):
   scan the segment (MAC sweep filtered by vendor OUIs) → cut the relay →
   scan again → the **MAC diff** is exactly the machines on that relay's
   power domain. Boards ship with a small block of consecutive MACs (default
   3 per board, `BLOCK_GAP=2`); within a block the BMC is the member whose IP
   answers IPMI with the public vendor-default credentials, the DUT is the
   remaining member. The relay is restored immediately and the DUT's return
   is awaited.
2. **Manual** (no relay, or the fingerprint finds nothing): you give the DUT's
   current IP; its MAC is read from the ARP/neigh cache (the MAC is the
   stored identity, so DHCP drift is transparent); the BMC is auto-searched
   among alive same-OUI MACs in the same block that answer IPMI with the
   vendor-default credentials, and you confirm or override.

Passwords: the BMC is first tried with the public vendor defaults (no prompt
if they work); the Windows/Ubuntu accounts are asked once and stored in
`os_flip.env`. If authentication fails **after** a boot is confirmed, the
run pauses and re-asks that credential once (failures during the boot wait
are plain retries — the machine may simply still be starting).

`./discovery.sh --dry-run` does a read-only sweep + board grouping (no power
cut, no writes) — useful for sanity-checking the environment.
`./discovery.sh --reauth` forgets the stored config and starts over.

## Configuration (environment / os_flip.env)

| Variable | Default | Meaning |
|---|---|---|
| `DUT_IP` / `DUT_MAC` | — (required: one of them) | DUT identity; the MAC re-resolves the IP on DHCP drift |
| `BMC_IP`, `BMC_USER`, `BMC_PASS` | — (required) | BMC IPMI access |
| `WIN_USER`/`WIN_PASS`, `UBU_USER`/`UBU_PASS` | user names pre-filled | DUT OS accounts |
| `DUT_NET` | runner's own /24 | MAC sweep range (`a.b.c.d/24`) |
| `KNOWN_OUI` | `00:15:b2` | vendor OUI prefixes (comma-separated) |
| `RELAY_OFF_CMD` / `RELAY_ON_CMD` | unset | enable the power-off fingerprint |
| `BLOCK_GAP` | `2` | same-board MAC block width (3 MACs → gap ≤ 2) |
| `CYCLES` | `10` (or argv 1) | number of switch cycles |
| `SHUTDOWN_MODE` | `clean` | `clean` = SSH shutdown → off → bootdev-while-off → power on (COLD); `reset` = legacy warm reset |
| `SETUP_TIMEOUT` / `BOOT_TIMEOUT` | `120` / `240` | UEFI setup / boot-confirmation budgets (s) |
| `PROBE_TIMEOUT` / `ID_PROBE_BUDGET` | `30` / `240` | single SSH probe / whole identification budget (s) |
| `COLLECT_TIMEOUT` | `120` | system-info collection budget (s) |
| `BMC_DEFAULT_USER` / `BMC_DEFAULT_PASS` | vendor defaults | used only for discovery's first trial |

## Failure semantics

- **nav verify fail** → ENTER is never sent, safe exit (SOL closed + plain
  reset to normal boot), cycle FAIL, **abort the whole run**
- **boot timeout / identification fail / wrong OS** → cycle FAIL, abort
- **collection failure after a correct boot** → cycle **PARTIAL**, continue

Every cycle writes: nav key trace (`t/key/+bytes/text`), boot duration
(reset → ping UP), OS identification evidence, the full system-info output,
and the failure reason. All artifacts land in `$WORK_DIR/os_flip_<ts>/`
(default `~/os_flip/`). Stop with `pkill -f os_flip`.

## Sandbox (hermetic self-test)

`sandbox/` stubs `ssh`/`ping`/`ipmitool`/`ip` (state-machine simulation of
the DUT power/boot/OS state) so the whole controller logic runs with no
hardware:

```bash
cd sandbox
./run_case.sh A    # normal 2 cycles (reset mode)
./run_case.sh B    # nav verify fail -> safe exit, abort
./run_case.sh C    # boot timeout after ENTER handoff
./run_case.sh D    # collect failure -> PARTIAL, continue
./run_case.sh E    # normal 2 cycles (clean mode, both shutdown paths)
./run_case.sh F    # clean mode, SSH hangs -> forced off/on, PASS + WARN
./run_case.sh G    # clean mode, BIOS drops the latch -> setup retry recovers
./run_case.sh H    # first-run discovery (manual mode) + 1 cycle
```

All cases must exit 0.

## Safety notes

- The relay is only ever touched through the two commands **you** configured
  (`RELAY_OFF_CMD`/`RELAY_ON_CMD`); nothing is guessed, and the fingerprint
  restores power immediately after the diff.
- `os_flip.env` holds real passwords: it is `chmod 600` and gitignored;
  never commit it. The repository contains no site IPs, no credentials, and
  no project codenames.
- The run never changes the persistent boot order; if you must leave the DUT
  on a specific OS, one plain `chassis power reset` lands it on the
  persistent default.
