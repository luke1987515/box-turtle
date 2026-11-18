#!/usr/bin/env bash
# Functional test for 30_report.py: mock IOMeter CSVs -> verify parsing.
set -u
T="$(cygpath -w "$1")"          # -> C:\Users\<user>\...\rvi_test
T_FWD="${T//\\//}"              # -> C:/Users/<user>/.../rvi_test (sed-safe, Python-friendly)
rm -rf "$T"
mkdir -p "$T/results" "$T/report" "$T/logs"

# conf copy pointing at test dir
sed -e "s|^BASE_DIR=.*|BASE_DIR=\"$T_FWD\"|" \
    -e 's|^PWM_LEVELS=.*|PWM_LEVELS="20 40 100"|' \
    "${RVI_SRC_DIR:?set RVI_SRC_DIR to this repo dir}/rvi.conf" > "$T/rvi.conf"

mkcsv() { # file, drive1_iops, drive2_iops
    local f="$1" d1="$2" d2="$3" i
    {
      echo "IOMeter Version,1.1.0"
      echo "Test Name,RVI Fan Sweep"
      echo "Start Time,2026-11-18 09:00:00"
      echo "Worker Name,Worker #,I/O per Second,Transfer per Second,Avg Response (ms),Errors"
      for i in $(seq 1 150); do
        echo "PHYSICALDRIVE:0,1,$d1,3.4,9.3,0"
        echo "PHYSICALDRIVE:1,2,$d2,3.3,9.4,0"
      done
    } > "$f"
}

# levels 20, 40 present for both tests; level 100: only 4K present (SEQ missing)
mkcsv "$T/results/fan_20_pct_4K_Random_Writes.csv" 850.2 842.7
mkcsv "$T/results/fan_20_pct_256K_Seq_Writes.csv" 5120.0 5105.5
mkcsv "$T/results/fan_40_pct_4K_Random_Writes.csv" 831.4 828.9
mkcsv "$T/results/fan_40_pct_256K_Seq_Writes.csv" 5090.1 5077.7
mkcsv "$T/results/fan_100_pct_4K_Random_Writes.csv" 800.3 795.1
# fan_100_pct_256K_Seq_Writes.csv intentionally missing

# an unparsed file (no recognizable header)
echo "garbage no header here" > "$T/results/bogus.csv"

cp "${RVI_SRC_DIR:?set RVI_SRC_DIR to this repo dir}/30_report.py" "$T/30_report.py"

# errors.log sample
printf '=== 2026-11-18T09:40:00 level=40 ===\n[12345.678] sd 1:0:1:0 sdb: I/O error, dev sdb, sector 512\n' > "$T/logs/errors.log"

python3 "$T_FWD/30_report.py"
echo "---- summary_4K_Random.csv ----"
cat "$T/report/summary_4K_Random.csv"
echo "---- summary_256K_Seq.csv ----"
cat "$T/report/summary_256K_Seq.csv"
echo "---- audit_missing.csv ----"
cat "$T/report/audit_missing.csv"
echo "---- errors_summary.txt (head) ----"
head -6 "$T/report/errors_summary.txt"
