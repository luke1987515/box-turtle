# Server Fan-Speed Lock + IOMeter Auto Test (Windows bat) — ZELUS / Sophos (Pegatron 2MS)

> English version (this file) | 繁體中文版本：[README.zh-TW.md](README.zh-TW.md)

Windows batch automation for the DQA "fan speed lock + IOMeter" test:
sweeps 13 chassis-fan PWM levels (20 → 100%) and at each level locks the
chassis fans (OEM `raw 0x36 0xFA`), runs **both** IOMeter profiles
(4K Random Writes + 256K Sequential Writes), and logs **chassis fan RPM
and PSU fan RPM** at 3 points per stage (Before 4K / Before 256K /
Stage Completed) into `Fan_Speed_Log.txt`. After the last stage the fan
speed is restored to 60%.

V03 addition over V02: **PSU fan speed logging** via the BMC OEM raw
command (method provided by AIC BMC RD, 2026-11-26). V02 logged chassis
fans only.

## PSU fan reading (Zelus / Sophos — system-specific)

```
ipmitool raw 0x3A 0x6A 0x0 <psu_bus> 0x1 <addr> 0x2 0x90
```

| param | meaning | ZELUS value |
|---|---|---|
| `psu_bus` | i2c bus the PSU is mounted on | `0x7` |
| `<addr>` | PSU position on that i2c bus | PSU1 `0xB0`, PSU2 `0xB2` |

> These two values are **system-specific** (per BMC RD). For other
> systems, edit `psu_bus` / `psu1_addr` / `psu2_addr` at the top of
> `run_fan_iometer_V03.bat` and confirm with BMC RD.

### Decode

The reply is two bytes `<lo> <hi>`; interpret as `val = hi*256 + lo`.

```
RPM = 2^(upper 5 bits of val) * (lower 11 bits of val)
```

Worked example: reply `6c 30` → `val = 0x306C = 12396` →
`exp = 6`, `mult = 108` → `2^6 * 108 = 6912 RPM`.

> Note: BMC RD's original email example had a typo (`e7 28` vs binary
> `0010 1000 1110 0100` = `0x28E4`); the formula above is validated
> against the BMC Web UI PSU page values.

## Files

| File | Role |
|---|---|
| `run_fan_iometer_V03.bat` | main test (interactive: asks BMC IP/user/password) |
| `psu_fan_test.bat` | 30 s read-only check of the PSU fan read only (no fan lock, no IOMeter) |
| `README.md` | this file |
| `README.zh-TW.md` | Chinese (Traditional) version of this README |

## Requirements (all in the same folder)

- `ipmitool.exe` (works with the Cygwin build used in the lab)
- `IOmeter.exe` (IOMeter 1.1.0)
- `4K_Random_Writes.icf`, `256K_Sequential_Writes.icf`

## Usage

Double-click `run_fan_iometer_V03.bat`, enter BMC IP / user / password.
Outputs: `Fan_Speed_Log.txt` + 26 CSVs (`Fan_<pct>pct_<test>.csv`).
Full run ≈ 75 min (13 stages × ~5.5 min).

Log line format: `PSU1 Fan1: 6912 RPM (raw 6c 30)`

## Provenance

Designed by Luke Chen (luke1987515); developed with the assistance of an
AI agent (Hermes Agent by Nous Research). PSU fan OEM raw command and
decode formula provided by AIC BMC RD (Jonny Chung) on 2026-11-26.

Verification record (2026-11-26, Pegatron 2MS / ZELUS DUT, BMC
192.168.15.57): full 13-stage run 19:23:51 → 20:36:28 — 39/39 log
points present, 26/26 IOMeter CSVs, 0 N/A PSU readings, 0 decode
mismatches; chassis fans tracked the PWM ramp 5700 → 20700 RPM; PSU
fans held 6784–6976 RPM throughout (PSU self-controlled, unaffected by
chassis lock); fan speed restored to 60% at the end.

Author: Luke.Chen <luke1987515@gmail.com>
Date:   2026-11-26
