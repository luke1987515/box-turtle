#!/bin/bash

# 檢查並刪除可能存在的舊檔案
files_to_delete=("ipmi_sdr_output.txt" "ipmi_sdr_labels.txt")

for file in "${files_to_delete[@]}"; do
  if [[ -f "$file" ]]; then
    echo "檔案 $file 存在，正在刪除..."
    rm "$file"
    if [[ $? -eq 0 ]]; then
      echo "成功刪除檔案 $file."
    else
      echo "刪除檔案 $file 失敗！"
      exit 1
    fi
  fi
done

# 第一部分：IPMI資訊擷取並生成標籤檔案
# 提供使用者互動輸入
echo "You have 10 seconds to enter each value, or the default will be used."
read -t 10 -p "Enter IPMI Host (default: 192.168.11.11): " IPMI_HOST
IPMI_HOST=${IPMI_HOST:-192.168.11.11}

read -t 10 -p "Enter IPMI Username (default: admin): " IPMI_USER
IPMI_USER=${IPMI_USER:-admin}

read -t 10 -sp "Enter IPMI Password (default: admin123): " IPMI_PASS
echo  # 換行
IPMI_PASS=${IPMI_PASS:-admin123}

# 顯示使用者輸入的資訊
echo "Using the following IPMI credentials:"
echo "Host: $IPMI_HOST"
echo "User: $IPMI_USER"
echo "Password: $IPMI_PASS"

# 執行 ipmitool 指令
OUTPUT=$(./ipmitool -I lanplus -H "$IPMI_HOST" -U "$IPMI_USER" -P "$IPMI_PASS" sdr)

# 檢查指令執行是否成功
if [ $? -eq 0 ]; then
    echo "Command executed successfully."
    echo "$OUTPUT" >> ipmi_sdr_output.txt

    # 生成標籤檔案
    awk -F '|' '{print $1}' ipmi_sdr_output.txt > ipmi_sdr_labels.txt
    echo "Generated file with labels: ipmi_sdr_labels.txt"
else
    echo "Failed to execute ipmitool command. Please check your connection and credentials."
    exit 1
fi

# 第二部分：統計關鍵字出現次數
# 定義標籤檔案和輸入檔案
label_file="ipmi_sdr_labels.txt"
input_file="H3_AC_counter_cold_log.txt"

# 檢查檔案是否存在
if [[ ! -f "$label_file" ]]; then
  echo "標籤檔案 $label_file 不存在！"
  exit 1
fi

if [[ ! -f "$input_file" ]]; then
  echo "輸入檔案 $input_file 不存在！"
  exit 1
fi

# 從標籤檔案中讀取關鍵字並存儲到陣列
mapfile -t items < "$label_file"

# 設置對齊格式
printf "%-25s | %s\n" "Label" "count"
printf "%-25s | %s\n" "-------------------------" "---------"

# 統計關鍵字出現次數並輸出
for item in "${items[@]}"; do
  exact_count=$(awk -v item="$item" '$0 ~ item && $0 ~ /\|.*ok/ {count++} END {print count}' "$input_file")
  printf "%-25s | %d\n" "$item" "${exact_count:-0}"
done

