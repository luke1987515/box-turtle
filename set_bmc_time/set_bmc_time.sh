#!/bin/bash

# 設定遠端 BMC 資訊
BMC_IP="192.168.11.11"
BMC_USER="admin"
BMC_PASS="admin123"

# 取得當前 UTC 日期和時間
current_datetime=$(date -u +"%m/%d/%Y %H:%M:%S")
echo "當前 UTC 日期與時間是：$current_datetime"

# 確保 ipmitool 存在
if ! command -v ipmitool &> /dev/null; then
    echo "錯誤：ipmitool 未安裝，請先安裝後再執行！"
    exit 1
fi

# 設定 BMC 時間
if ipmitool -I lanplus -H "$BMC_IP" -U "$BMC_USER" -P "$BMC_PASS" sel time set "$current_datetime"; then
    echo "BMC 時間設定成功！"
else
    echo "BMC 時間設定失敗！"
    exit 1
fi
