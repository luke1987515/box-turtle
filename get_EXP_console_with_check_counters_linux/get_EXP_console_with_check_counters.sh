#!/bin/bash

# 定義 ANSI 轉義碼來設置顏色
RED='\033[0;31m'
GRE='\033[0;32m'
NC='\033[0m' # 恢復顏色為預設值


if [ $(whoami) = "root" ]; then
    echo "當前使用者是 root 使用者"
else
    echo "當前使用者不是 root 使用者"
    echo "請使用下列 command 切換"
    echo
    echo "sudo su"
    echo
fi

if [ -f "g4Xdiagnostics.x86_64" ]; then
   echo "太好了有 g4Xdiagnostics.x86_64 工具"
else
   echo "沒有 g4Xdiagnostics.x86_64 工具"
   echo "請到下列路徑找到此工具"
   echo
   echo "\\\192.168.1.22\dqa-tools\G4XTOOLS"
   echo
fi

check_counters () {
    MyFile=$1

    # 刪除空行，以及只包含空白字元的行
    sed -i '/^[[:space:]]*$/d' "$MyFile"

    # 刪除 非數字 的行
    sed -i '/^[^0-9]/d' "$MyFile"

    # 設定變數 Check_All_Status=0
    # 如果有 PHYID 有 error counters，則設定成 1
    Check_All_Status=0

    # 我不知道為什麼單行讀要這麼讀，
    # 但 It work!!
    # https://ioflood.com/blog/bash-read-file-line-by-line/

    while IFS= read -r line
        do
            # echo $line
            counters_list=($line)
            if [ "${counters_list[1]}" = "00000000" ] && \
               [ "${counters_list[2]}" = "00000000" ] && \
               [ "${counters_list[3]}" = "00000000" ] && \
               [ "${counters_list[4]}" = "00000000" ]
            then
                echo -e PHYID ${counters_list[0]}: "${GRE}[PASS]${NC}"
            else
                echo -e PHYID ${counters_list[0]}: "${RED}[FAIL]${NC}" ${counters_list[1]} \
                                                                       ${counters_list[2]} \
                                                                       ${counters_list[3]} \
                                                                       ${counters_list[4]}
               # get error counters set Check_All_Status=1
               Check_All_Status=1
            fi
        done < $MyFile

    # 檢查全部是不是 PASS
    echo
    echo log 檢查結果如下
    if [ "$Check_All_Status" = 0 ]; then
        echo -e $1 : "${GRE}[PASS]${NC}"
    else
        echo -e $1 : "${RED}[FAIL]${NC}"
        echo
        echo "有 error 請依上述資訊,確認是否為 Storage Devcie 或是 cable 導致"
    fi
    echo
}


# ./g4Xdiagnostics.x86_64 --list | grep 500 | cut -d ":"  -f 1 | rev | cut -c -8 | rev


# ./g4Xdiagnostics.x86_64 --list | grep 50015b | cut -c 26-42

SASaddr=($(./g4Xdiagnostics.x86_64 --list | grep 50015b | cut -c 26-42))

for addr in "${SASaddr[@]}"
do
    echo "$addr"
    WWID=$(echo "$addr" | sed 's/://g')
    ./g4Xdiagnostics.x86_64 -wwid $WWID show
    # ./g4Xdiagnostics.x86_64 -wwid $WWID cli counters reset
    ./g4Xdiagnostics.x86_64 -wwid $WWID cli counters | tee counters_$WWID.log
    check_counters counters_$WWID.log
    echo
    echo "$addr"
    echo
    echo 下一個 EXP Controller
    echo

done
