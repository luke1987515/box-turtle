#!/bin/bash

# 1. 自動找出根目錄 `/` 所在的實體母硬碟名稱
SYS_DISK=$(lsblk -no PKNAME $(df / | tail -n1 | awk '{print $1}'))
if [ -z "$SYS_DISK" ]; then
    SYS_DISK=$(lsblk -no NAME $(df / | tail -n1 | awk '{print $1}'))
fi

echo "=========================================="
echo "偵測到系統碟為: /dev/$SYS_DISK (已自動排除)"
echo "=========================================="

# 2. 自動抓取所有 sd* 硬碟，並剔除「系統碟」與「USB 介面裝置」
TARGET_DISKS=$(lsblk -d -n -o NAME,TRAN | grep "^sd" | awk '$2 != "usb" {print $1}' | grep -v "^${SYS_DISK}$")

# 計算目標數量 (處理空字串情境)
if [ -z "$TARGET_DISKS" ]; then
    COUNT=0
else
    COUNT=$(echo "$TARGET_DISKS" | wc -l)
fi

if [ "$COUNT" -eq 0 ]; then
    echo "錯誤：未找到任何可抹除的目標硬碟（已自動排除系統碟與 USB 裝置）！"
    exit 1
fi

echo "準備進行抹除的硬碟清單 ($COUNT 個，已排除 USB 裝置):"

# 顯示 /dev/sdX (型號 + SN)
while read -r disk; do
    [ -z "$disk" ] && continue
    model=$(lsblk -d -no MODEL "/dev/$disk" | xargs)
    sn=$(lsblk -d -no SERIAL "/dev/$disk" | xargs)
    echo "  /dev/$disk (型號: ${model:-未知}, SN: ${sn:-未知})"
done <<< "$TARGET_DISKS"

echo "=========================================="

read -p "確定要開始抹除上述 $COUNT 個硬碟？(y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "已取消操作。"
    exit 0
fi

# 3. 並行抹除作業（動態抓取硬碟 SN 並命名 Log 檔）
echo "$TARGET_DISKS" | xargs -P 0 -I {} sh -c '
  dev="/dev/{}"
  name="{}"
  
  # 抓取硬碟序號 (SN)，並過濾掉前後空白與特殊字元
  sn=$(lsblk -no SERIAL "$dev" | xargs)
  if [ -z "$sn" ]; then
      sn="UNKNOWN_SN"
  else
      # 避免 SN 內含不合法的檔名字元，將空白或斜線替換為底線
      sn=$(echo "$sn" | tr " /" "__")
  fi

  # 組合包含硬碟代號與 SN 的日誌檔名
  log_file="dd_output_${name}_${sn}_bs_4M.log"

  echo "開始抹除 $dev (SN: $sn) ..."
  sudo dd if=/dev/zero of="$dev" bs=4M status=progress conv=fsync 2>&1 | tee "$log_file"
  sudo sync
  echo "$dev 抹除完成，日誌已儲存至 $log_file"
'

# 4. 全部完成後關機
sudo sync
sudo sync
sudo sync
sudo poweroff
