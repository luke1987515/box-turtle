#!/bin/bash

# --- 工具路徑定義 ---
STORCLI2="/opt/MegaRAID/storcli2/storcli2"
STORCLI64="/opt/MegaRAID/storcli/storcli64"
SGSES="/usr/bin/sg_ses"
LEDCTL="/usr/sbin/ledctl"

echo "================================================================================"
echo "      伺服器硬碟 LED 測試工具 v10.4 (Integrated ledctl)"
echo "================================================================================"

# --- 環境動態掃描 ---
DECLARE_ADAPTERS=()
scan_environment() {
    DECLARE_ADAPTERS=()
    # 1. StorCLI2 掃描
    if [ -f "$STORCLI2" ]; then
        CTRL_LIST=$($STORCLI2 show | awk '/^-+$/{p++} p==2 && $1 ~ /^[0-9]+$/ {print $1}')
        for c_idx in $CTRL_LIST; do
            EID_LIST=$($STORCLI2 /c$c_idx show | grep -A 50 "Enclosure List" | awk '/^[0-9]+/{print $1}' | grep -E "^[0-9]+$")
            for eid in $EID_LIST; do DECLARE_ADAPTERS+=("$STORCLI2|/c$c_idx/e$eid"); done
        done
    fi
    # 2. StorCLI64 掃描
    if [ -f "$STORCLI64" ]; then
        CTRL_LIST=$($STORCLI64 show | awk '/^-+$/{p++} p==2 && $1 ~ /^[0-9]+$/ {print $1}')
        for c_idx in $CTRL_LIST; do
            EID_LIST=$($STORCLI64 /c$c_idx show | grep -A 30 "PD LIST" | awk '/^-+$/{e++} e==2 && $1 ~ /^[0-9]+:[0-9]+$/ {split($1,a,":"); print a[1]}' | sort -u)
            for eid in $EID_LIST; do DECLARE_ADAPTERS+=("$STORCLI64|/c$c_idx/e$eid"); done
        done
    fi
    SES_DEVS=$(lsscsi -g | grep "enclosu" | awk '{print $NF}')
}

# --- 拆分後的邏輯 1：StorCLI 尋找 ---
find_by_storcli() {
    local TARGET_DEV=$1
    local TARGET_SN=$(lsblk -dn -o SERIAL "/dev/$TARGET_DEV" | tr -d ' ')
    
    for item in "${DECLARE_ADAPTERS[@]}"; do
        IFS='|' read -r BIN_PATH ADPT_PATH <<< "$item"
        local RAW_DATA=$($BIN_PATH $ADPT_PATH/sall show all 2>/dev/null)
        local SLOT_DATA=$(echo "$RAW_DATA" | grep -i -B 80 "Number = $TARGET_SN" | grep "Drive $ADPT_PATH" | tail -n 1)
        [ -z "$SLOT_DATA" ] && SLOT_DATA=$(echo "$RAW_DATA" | grep -i -B 80 "SN = $TARGET_SN" | grep "Drive $ADPT_PATH" | tail -n 1)

        if [[ "$SLOT_DATA" =~ /s([0-9]+) ]]; then
            local SLOT_NUM="${BASH_REMATCH[1]}"
            echo "STORCLI|$ADPT_PATH/s$SLOT_NUM|$BIN_PATH $ADPT_PATH/s$SLOT_NUM start locate|$BIN_PATH $ADPT_PATH/s$SLOT_NUM stop locate"
            return 0
        fi
    done
    return 1
}

# --- 拆分後的邏輯 2：sg_ses 尋找 ---
find_by_sgses() {
    local TARGET_DEV=$1
    local TARGET_WWN=$(smartctl -i "/dev/$TARGET_DEV" 2>/dev/null | grep -Ei "LU WWN Device Id|Logical Unit id" | awk '{print $NF}' | sed 's/^0x//i' | tr '[:upper:]' '[:lower:]')
    
    if [ ! -z "$TARGET_WWN" ]; then
        local FUZZY_KEY=$(echo "$TARGET_WWN" | sed 's/.*\(.\{8\}\)$/\1/' | sed 's/.$//')
        for SG in $SES_DEVS; do
            local DESC=$($SGSES "$SG" --join 2>/dev/null | grep -i -B 30 "$FUZZY_KEY" | grep -E "^Disk[0-9]+" | tail -n 1 | awk '{print $1}')
            if [ ! -z "$DESC" ]; then
                echo "SGSES|$SG (Desc:$DESC)|$SGSES --descriptor=$DESC --set=ident $SG|$SGSES --descriptor=$DESC --clear=ident $SG"
                return 0
            fi
        done
    fi
    return 1
}

# --- 拆分後的邏輯 3：ledctl 尋找 ---
find_by_ledctl() {
    local TARGET_DEV=$1
    if [ -f "$LEDCTL" ] && [ -b "/dev/$TARGET_DEV" ]; then
        echo "LEDCTL|/dev/$TARGET_DEV|$LEDCTL locate=/dev/$TARGET_DEV|$LEDCTL off=/dev/$TARGET_DEV"
        return 0
    fi
    return 1
}

# 最佳命令判斷封裝
find_best_cmd() {
    local RESULT
    # 1. 優先試用 StorCLI
    RESULT=$(find_by_storcli "$1") && { echo "$RESULT"; return; }
    # 2. 嘗試 sg_ses
    RESULT=$(find_by_sgses "$1") && { echo "$RESULT"; return; }
    # 3. 嘗試 ledctl
    RESULT=$(find_by_ledctl "$1") && { echo "$RESULT"; return; }
    
    echo "NONE"
}

show_disk_list() {
    echo -e "\n--- [目前磁碟清單] ---"
    printf "%-5s %-18s %-20s %-5s\n" "NAME" "MODEL" "SERIAL (SN)" "TYPE"
    echo "--------------------------------------------------------------------------------"
    for dev in $(lsblk -dn -o NAME | grep -v "loop"); do
        MODEL=$(lsblk -dn -o MODEL "/dev/$dev" | xargs)
        SERIAL=$(lsblk -dn -o SERIAL "/dev/$dev" | xargs)
        TYPE=$(smartctl -i "/dev/$dev" 2>/dev/null | grep -qi "SAS" && echo "SAS" || echo "SATA")
        [ ! -z "$SERIAL" ] && printf "%-5s %-18s %-20s %-5s\n" "$dev" "${MODEL:0:17}" "$SERIAL" "$TYPE"
    done
}

scan_environment
show_disk_list

while true; do
    echo -e "\n[主選單]"
    echo "1) 手動點燈測試 (可選模式)"
    echo "2) 執行批次自動點燈 (自動比對所有硬碟)"
    echo "l) 顯示磁碟清單"
    echo "q) 離開"
    read -p "請選擇功能: " MAIN_CHOICE

    case "$MAIN_CHOICE" in
        l) show_disk_list ;;
        q) exit 0 ;;
        2)
            echo -e "\n--- 開始批次自動點燈 (3秒/槽) ---"
            for dev in $(lsblk -dn -o NAME | grep -v "loop"); do
                RES=$(find_best_cmd "$dev")
                if [ "$RES" != "NONE" ]; then
                    IFS='|' read -r TYPE ADDR CMD_ON CMD_OFF <<< "$RES"
                    echo -e "\n[測試]: /dev/$dev -> $ADDR"
                    echo -e " \033[1;34mCMD: $CMD_ON\033[0m"
                    $CMD_ON >/dev/null 2>&1
                    echo -ne " \033[1;32m[FLASHING]\033[0m" ; sleep 3 ; $CMD_OFF >/dev/null 2>&1
                    echo -e "\r \033[1;30m[OFF]\033[0m"
                fi
            done
            ;;
        1)
            read -p "請輸入 Device 名稱 (如 sdf): " USER_IN
            DEV=${USER_IN#/dev/}
            [[ ! -b "/dev/$DEV" ]] && echo "!! 錯誤: 設備不存在" && continue

            echo -e "\n請選擇點燈模式:"
            echo "1) Broadcom StorCLI (原生控制 - 推薦)"
            echo "2) 通用 sg_ses (AIC 特殊背板比對)"
            echo "3) 通用 ledctl (OS 標準模式)"
            read -p "請選擇 [1-3]: " MODE_CHOICE

            MATCHED=false
            case "$MODE_CHOICE" in
                1)
                    RES=$(find_by_storcli "$DEV")
                    [ $? -eq 0 ] && IFS='|' read -r TYPE ADDR CMD_ON CMD_OFF <<< "$RES" && MATCHED=true
                    ;;
                2)
                    RES=$(find_by_sgses "$DEV")
                    [ $? -eq 0 ] && IFS='|' read -r TYPE ADDR CMD_ON CMD_OFF <<< "$RES" && MATCHED=true
                    ;;
                3)
                    RES=$(find_by_ledctl "$DEV")
                    [ $? -eq 0 ] && IFS='|' read -r TYPE ADDR CMD_ON CMD_OFF <<< "$RES" && MATCHED=true
                    ;;
            esac

            if [ "$MATCHED" = true ]; then
                echo -e "成功鎖定路徑: $ADDR"
                echo -e "執行指令: \033[1;34m$CMD_ON\033[0m"
                $CMD_ON >/dev/null 2>&1
                read -p "--- [LED 閃爍中] 按下 Enter 熄燈 ---"
                $CMD_OFF >/dev/null 2>&1
                echo ">> 已熄燈。"
            else
                echo "!! 匹配失敗。請確認工具是否安裝或該硬碟是否支援該模式。"
            fi
            ;;
    esac
done
