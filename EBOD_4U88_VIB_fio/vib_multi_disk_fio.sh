#!/usr/bin/env bash
# vib_multi_disk_fio.sh
# eBOD 4U88 / BF3 DPU OS (88x SAS HDD, dual-port)
# 1) 檢查 88 顆 HDD (sda..sdcj)  2) 產生 fio conf  3) 背景執行 + monitor（每秒印整體 MB/s/err，Ctrl+C 終止 fio）
# 用法: sudo bash vib_multi_disk_fio.sh [秒數，預設 900]
set -euo pipefail

# ===== 可調參數 =====
RUNTIME="${1:-900}"    # 參數 1 = 運行秒數（例: 60 / 900），預設 900
if ! [[ "$RUNTIME" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: 參數 1 必須是正整數（秒），例: sudo bash vib_multi_disk_fio.sh 900" >&2
  exit 1
fi
BS=512k
IODEPTH=1
STATUS_INTERVAL=1      # --status-interval：每 N 秒在 log 印出各盤 MB/s（fio 3.28 只能放 CLI，放 conf 會 Bad option 且把 [global] 整個 drop）
N_DISK=88

# conf / pid 放腳本所在資料夾；log 檔名帶時間戳（重跑不覆蓋舊證據）
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$DIR/fio_vib_multi_disk.conf"
LOG="$DIR/fio_vib_multi_disk_$(date +%Y%m%d_%H%M%S).log"
PIDF="$DIR/fio_vib_multi_disk.pid"

# ===== 0) root 檢查 =====
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: 請用 sudo 執行" >&2
  exit 1
fi

# ===== 1) 檢查 88 顆盤 =====
# n=0..25 -> sda..sdz ; n=26..103 -> sdaa..sdcz
LETTERS=(a b c d e f g h i j k l m n o p q r s t u v w x y z)
disk_name() {
  local n=$1
  if (( n < 26 )); then
    printf 'sd%s' "${LETTERS[$n]}"
  else
    printf 'sd%s%s' "${LETTERS[$((( n - 26 ) / 26 ))]}" "${LETTERS[$(( n % 26 ))]}"
  fi
}

echo "== 檢查 $N_DISK 顆盤 (sda..sdcj) =="
missing=()
mounted=()
for (( i=0; i<N_DISK; i++ )); do
  d=$(disk_name "$i")
  if [[ ! -b /dev/$d ]]; then
    missing+=("$d")
    continue
  fi
  if mount | awk '{print $1}' | grep -qx "/dev/$d"; then
    mounted+=("$d")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "ERROR: 只找到 $(( N_DISK - ${#missing[@]} ))/$N_DISK 顆，缺少: ${missing[*]}" >&2
  exit 1
fi
echo "OK: 88/88 顆盤都在 (sda..sdcj)"

if (( ${#mounted[@]} > 0 )); then
  echo "ABORT: 以下盤有 mount，raw 寫入會摧毀檔案系統: ${mounted[*]}" >&2
  echo "       若是空測試盤，先 umount 或修改此段再跑" >&2
  exit 1
fi

# ===== 2) 檢查 fio =====
if ! command -v fio >/dev/null 2>&1; then
  echo "ERROR: fio 未安裝，先: apt install -y fio" >&2
  exit 1
fi
echo "fio: $(fio --version)"

# ===== 3) 產生 conf（整碟：不寫 size；status-interval 只能放 CLI）=====
{
  echo "[global]"
  echo "ioengine=libaio"
  echo "direct=1"
  echo "rw=write"
  echo "bs=$BS"
  echo "iodepth=$IODEPTH"
  echo "runtime=$RUNTIME"
  echo "time_based=1"
  echo "group_reporting=1"
  for (( i=0; i<N_DISK; i++ )); do
    d=$(disk_name "$i")
    echo ""
    echo "[job_$d]"
    echo "filename=/dev/$d"
  done
} > "$CONF"
echo "conf 已寫入: $CONF ($(wc -l < "$CONF") 行)"

# ===== 4) 啟動 fio（setsid 獨立 session，Ctrl+C 不會直接打到 fio）=====
setsid nohup fio --status-interval="$STATUS_INTERVAL" "$CONF" > "$LOG" 2>&1 &
FIO_PID=$!
echo "$FIO_PID" > "$PIDF"
sleep 1
if ! kill -0 "$FIO_PID" 2>/dev/null; then
  echo "ERROR: fio 啟動後立即死亡，log 最後 20 行:" >&2
  tail -n 20 "$LOG" >&2
  exit 1
fi
echo "fio 已啟動: PID=$FIO_PID"
echo "log: $LOG"

# ===== 5) monitor：每秒讀 log，印整體 MB/s（十進位）+ err =====
# group_reporting=1 時每秒只有一組整體 block：
#   job_sda: (groupid=0, jobs=88): err= 0: pid=...: <date>
#     write: IOPS=..., BW=...MiB/s (NNNMB/s)(...)
AWK_PARSE='
/^[A-Za-z0-9_]+: \(groupid=0, jobs=[0-9]+\): err= [0-9]+/ {
  if (match($0, /err= [0-9]+/)) e = substr($0, RSTART+5, RLENGTH-5)
}
/^  write: / {
  if (match($0, /\([0-9.]+MB\/s\)/)) {
    s = substr($0, RSTART+1, RLENGTH-6)
    gsub(/[^0-9.]/, "", s)
    bw = s
  }
}
END {
  if (bw != "") {
    if (e == "") e = "?"
    printf "%s %s\n", bw, e
  }
}
'

show_final() {
  line=$(tail -n 400 "$LOG" | awk "$AWK_PARSE" | tail -1)
  if [[ -n "$line" ]]; then
    read -r f_bw f_e <<< "$line"
    echo "最終: ${f_bw} MB/s  err=${f_e}"
  fi
  echo "log: $LOG"
  echo "（完整 report 在 log 內；要手動停: kill $(cat "$PIDF")）"
}

trap 'echo; echo "收到 Ctrl+C，終止 fio (PID $FIO_PID) ..."; kill -TERM "$FIO_PID" 2>/dev/null || true; wait "$FIO_PID" 2>/dev/null || true; echo "fio 已停止"; show_final; exit 130' INT

echo "monitor 開始（每 $STATUS_INTERVAL 秒更新；按 Ctrl+C 終止 fio）:"
while true; do
  if ! kill -0 "$FIO_PID" 2>/dev/null; then
    echo "fio 已結束（runtime ${RUNTIME}s 到）。"
    show_final
    exit 0
  fi
  line=$(tail -n 400 "$LOG" | awk "$AWK_PARSE" | tail -1)
  if [[ -n "$line" ]]; then
    read -r m_bw m_e <<< "$line"
    printf "%s   %s MB/s   err=%s\n" "$(date +%H:%M:%S)" "$m_bw" "$m_e"
  else
    printf "%s   （等待第一組 status...）\n" "$(date +%H:%M:%S)"
  fi
  sleep "$STATUS_INTERVAL"
done
