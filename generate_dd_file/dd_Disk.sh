#!/bin/bash

# 捕捉 SIGINT (Ctrl+C) 訊號，發送 kill 0 徹底清除當前程序群組下的所有子程序後安全退出
trap 'echo -e "\n[!] 偵測到 Ctrl+C，正在強制停止所有 dd 抹除程序..."; kill 0; exit 1' INT

# 1. 預先取得 sudo 權限
sudo -v || exit 1

# 2. 自動在背景保持 sudo 權限，避免 dd 執行太久導致最後 smartctl 跳出密碼提示
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &

# 0. 自動建立存放 Log 的資料夾並匯出變數 (解決 xargs 變數傳遞問題)
export LOG_DIR="logs"
mkdir -p "$LOG_DIR"

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

# 詢問是否確定執行
read -p "確定要開始抹除上述 $COUNT 個硬碟？(y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "已取消操作。"
    exit 0
fi

# 詢問完成後是否自動關機 (預設 Y)
read -p "抹除完成後是否自動關機？(Y/n): " AUTO_OFF

# 3. 並行抹除作業（抹除前後記錄 SMART 健康狀態、時間與耗時，並將 Log 存放至 logs 資料夾）
echo "$TARGET_DISKS" | xargs -P 0 -I {} sh -c '
  dev="/dev/{}"
  name="{}"
  
  # 抓取硬碟型號與序號 (SN)
  model=$(lsblk -d -no MODEL "$dev" | xargs)
  sn=$(lsblk -d -no SERIAL "$dev" | xargs)
  
  # 處理空白/未知欄位與特殊字元過濾
  if [ -z "$model" ]; then
      model_display="未知"
      model_safe="UNKNOWN_MODEL"
  else
      model_display="$model"
      model_safe=$(echo "$model" | tr " /" "__")
  fi

  if [ -z "$sn" ]; then
      sn_display="未知"
      sn_safe="UNKNOWN_SN"
  else
      sn_display="$sn"
      sn_safe=$(echo "$sn" | tr " /" "__")
  fi

  # 組合包含硬碟代號、型號與 SN 的日誌檔名
  log_file="${LOG_DIR}/dd_output_${name}_${model_safe}_${sn_safe}_bs_4M.log"

  echo "開始抹除 $dev (型號: $model_display, SN: $sn_display) ..."

  # 記錄開始時間與 Unix 時間戳記
  start_sec=$(date +%s)
  start_time=$(date "+%Y-%m-%d %H:%M:%S")

  # 抓取抹除前的 SMART 健康狀態
  smart_health_before=$(sudo smartctl -H "$dev" | grep -i "result" || echo "SMART 健康檢測失敗或不支援")

  # 寫入 Log 開頭資訊與 SMART 狀態
  {
    echo "=========================================="
    echo "目標硬碟: $dev"
    echo "硬碟型號: $model_display"
    echo "硬碟序號: $sn_display"
    echo "抹除開始時間: $start_time"
    echo "SMART 開始前健康狀態: $smart_health_before"
    echo "------------------------------------------"
    echo "[SMART 開始前詳細屬性]"
    sudo smartctl -A "$dev" 2>&1
    echo "=========================================="
  } > "$log_file"

  # 執行抹除作業 (append 模式寫入 log)
  sudo dd if=/dev/zero of="$dev" bs=4M status=progress conv=fsync 2>&1 | tee -a "$log_file"
  sudo sync

  # 記錄結束時間與計算總耗時
  end_sec=$(date +%s)
  end_time=$(date "+%Y-%m-%d %H:%M:%S")
  elapsed_sec=$(( end_sec - start_sec ))

  hours=$(( elapsed_sec / 3600 ))
  minutes=$(( (elapsed_sec % 3600) / 60 ))
  seconds=$(( elapsed_sec % 60 ))

  # 抓取抹除後的 SMART 健康狀態
  smart_health_after=$(sudo smartctl -H "$dev" | grep -i "result" || echo "SMART 健康檢測失敗或不支援")

  # 寫入 Log 結尾資訊與 SMART 狀態
  {
    echo "=========================================="
    echo "抹除完成時間: $end_time"
    echo "總花費時間: ${hours} 小時 ${minutes} 分 ${seconds} 秒 (共 ${elapsed_sec} 秒)"
    echo "SMART 完成後健康狀態: $smart_health_after"
    echo "------------------------------------------"
    echo "[SMART 完成後詳細屬性]"
    sudo smartctl -A "$dev" 2>&1
    echo "=========================================="
  } >> "$log_file"

  echo "$dev (型號: $model_display, SN: $sn_display) 抹除完成 (耗時: ${hours}h ${minutes}m ${seconds}s)，日誌已儲存至 $log_file"
'

# 4. 根據使用者選擇決定是否關機
sudo sync
sudo sync
sudo sync

if [[ "$AUTO_OFF" =~ ^[Nn]$ ]]; then
    echo "=========================================="
    echo "所有硬碟抹除作業已完成，保持系統開機。"
    echo "=========================================="
else
    echo "=========================================="
    echo "所有硬碟抹除作業已完成，系統即將關機..."
    echo "=========================================="
    sudo poweroff
fi
