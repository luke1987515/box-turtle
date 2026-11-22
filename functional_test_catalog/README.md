# Functional Test Item Catalog (AIC DQA)

Catalog of functional test items mined from past AIC DQA functional test
reports and curated into a single reference list.

## Files

| File | Purpose |
|---|---|
| `catalog.json` | The catalog (machine-readable). 80 items: 73 plain items + 7 parameterized skeletons. |
| `catalog_curation.xlsx` | Curation record: all 303 mined items with per-item decisions (`決定` column). Sheets: `items` (full inventory, 303), `new-items` (272 curated items), `sub-steps` (3,977 procedure/criteria lines, for later dedup). |

## Source corpus

- `dqa-report / Functional Report` (company file server, read-only): **456 PDFs**
  (SSG 342, ESG 51, PSG 51, PPLM 11, IAG 1).
- Mined: **6,236** test-item instances → **303** distinct item names.
- Mined 2026-11-14; curated & finalized 2026-11-22 (Luke Chen).

## Curation rules (decision log)

| Class | Count | Decision | Rationale |
|---|---|---|---|
| TOC noise | 149 | noise | Table-of-contents dot-leaders picked up as "items" in old reports. |
| Chapter/number noise | 4 | noise | Chapter headings (`JBOD Functional Test`) or section numbers (`30.8`) picked up as items. |
| In 2023 superset | 31 | carried over | Already covered by the 2023 superset item list; no action. |
| Card variants | 53 | variant | RAID/HBA card model + interface params (`"RAID Card" with SAS 12G HDD Config`, `Adaptec 3154-8i8e …`, `9207-8e …`). Absorbed into card skeletons; card model / interface go to params. |
| Other variants | 6 | variant | `Feature (by RR12/RR6 code base)` → code-base param; `System Stress-Linux/Windows` → OS param; `EDFB on <fw versions>` → firmware-version param. |
| Merged | 16 | merge | Same test under a drifted name (e.g. `SSD Hot-swap` → `NVMe SSD hot-swap`, `RJ45 Port` → `LAN Card Test`) or sub-variants of `Customer requirement` (11 names). |
| Kept | 44 | keep | Distinct functional test items. |

Accounting: 303 = 153 noise + 31 superset + 59 variants + 16 merged + 44 kept.

## catalog.json schema

```jsonc
{
  "items": [
    {
      "name": "NVMe SSD hot-swap",
      "chapter": "3. JBOF Functional Test",
      "type": "item",              // "item" | "skeleton"
      "reports": 5,                // number of source reports containing the item
      "merged_from": ["SSD Hot-swap"]   // names folded into this item (items only)
    },
    {
      "name": "RAID Card with <card> <interface> HDD Config",
      "chapter": "4. RAID Card Test",
      "type": "skeleton",
      "reports": 428,              // sum across variants
      "params": ["card", "interface"],
      "variants": ["\"RAID Card\" with SAS 12G HDD Config", "Adaptec 3154-8i8e with SAS 12G HDD config"]
    }
  ]
}
```

Skeletons: RAID Card / HBA Card / eHBA Card / Onboard IOC (card + interface
params), EDFB (firmware versions), Feature (code base), System Stress (OS).

## Notes

- Chapter numbering drifts across report vintages (`3. BMC Function Test` vs
  `6. BMC Function Test` etc.); chapter strings are kept as mined.
- `sub-steps` sheet is the next curation pass (synonym dedup of the 3,977
  procedure/criteria lines) — not yet finalized.
