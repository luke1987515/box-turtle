#!/bin/bash

# 取得當前 UTC 時間
local_time=$(date -u +"%Y-%m-%d %H:%M:%S")
echo "系統 UTC 時間：$local_time"

# 從 BMC 讀取時間，並格式轉換成 YYYY-MM-DD HH:MM:SS 格式
bmc_time=$(ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin123 sel time get | grep -oP '\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}' | sed 's|\([0-9]\{2\}\)/\([0-9]\{2\}\)/\([0-9]\{4\}\) \([0-9:]\{8\}\)|\3-\1-\2 \4|')
echo "BMC 時間：$bmc_time"

# 比較兩者時間
if [ "$local_time" == "$bmc_time" ]; then
    echo "系統 UTC 時間與 BMC 時間相同。"
else
    echo "系統 UTC 時間與 BMC 時間不同。"
    # 計算時間差異
    local_unix=$(date -u -d "$local_time" +%s)
    bmc_unix=$(date -u -d "$bmc_time" +%s)
    time_diff=$((local_unix - bmc_unix))
    echo "時間差異為：$time_diff 秒"
fi

