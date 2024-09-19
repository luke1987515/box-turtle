#!/bin/bash

# 取得當前 UTC 日期和時間
current_datetime=$(date -u +"%m/%d/%Y %H:%M:%S")

# 顯示當前 UTC 日期與時間
echo "當前 UTC 日期與時間是：$current_datetime"

# 使用 ipmitool 設定遠端 BMC 的時間
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin123 sel time set "$current_datetime"

# 檢查命令是否執行成功
if [ $? -eq 0 ]; then
    echo "BMC 時間設定成功！"
else
    echo "BMC 時間設定失敗！"
fi

