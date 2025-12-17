#!/bin/bash

# --- 磁碟掃描與快取關閉區塊 ---

echo "🔍 掃描系統硬碟裝置..."
# 取得 OS 所在磁碟名稱 (例如 nvme0n1p1 -> nvme0n1)
# 確保排除邏輯適用於 /dev/sdX[1-9] 和 /dev/nvmeXnYp[1-9]
os_disk=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/p$//' | xargs basename)
echo "⛔ 排除 OS Disk：$os_disk"

# 步驟 1: 取得初始硬碟清單（排除 OS 及 NVMe/MMCBLK）
# 使用 \b 確保排除的是完整的設備名稱
initial_disks=($(lsblk -d -o NAME,TYPE | grep disk | awk '{print $1}' | grep -v "^$os_disk\b" | grep -v "^nvme" | grep -v "^mmcblk"))

# 步驟 2: 遍歷初始清單，排除 USB 設備，並建構最終清單
disks=() # 初始化空陣列
for disk in "${initial_disks[@]}"; do
    # 獲取總線類型，忽略錯誤輸出
    bus_type=$(udevadm info --query=all --name=/dev/$disk 2>/dev/null | grep ID_BUS | cut -d= -f2)
    if [[ "$bus_type" != "usb" ]]; then
        disks+=("$disk") # 將非 USB 設備添加到最終陣列
    fi
done

echo "💡 關閉所有非 NVMe HDD 的寫入快取..."

for disk in "${disks[@]}"; do
    dev_path="/dev/$disk"

    # 取得磁碟傳輸介面
    tran=$(cat /sys/block/$disk/device/transport 2>/dev/null)
    # 如果 /sys/block/$disk/device/transport 找不到，嘗試 udevadm 取得 bus
    [[ "$tran" == "" ]] && tran=$(udevadm info --query=all --name=$dev_path 2>/dev/null | grep ID_BUS | cut -d= -f2)

    if [[ "$tran" == "ata" ]]; then
        # 對 ATA/SATA 設備使用 hdparm
        echo "⚙️ 關閉 $dev_path 的寫入快取 (SATA/hdparm)..."
        hdparm -W0 $dev_path
    elif [[ "$tran" == "scsi" ]]; then
        # 對 SCSI/SAS 設備使用 sdparm
        echo "⚙️ 關閉 $dev_path 的寫入快取 (SAS/sdparm)..."
        sdparm --set WCE=0 $dev_path
    else
        echo "⏭️ 略過 $dev_path（傳輸介面為 $tran）"
    fi
done

# --- 模式選擇區塊 ---

# 顯示模式選單
echo "🧪 選擇測試模式"
echo "1️⃣ RVI 模式：ramp=300, runtime=600"
echo "   a) 全部硬碟"
echo "   b) 單一硬碟"
echo "   c) 編號區段"
echo "2️⃣ Debug 模式：ramp=30, runtime=300"
echo "   b) 單一硬碟"
echo "   c) 編號區段"
echo "3️⃣ 離開"
read -p "請輸入主選項 (1/2/3)：" mode

# 顯示硬碟清單（含型號與介面）
function list_disks() {
    echo "📦 可選磁碟清單："
    for i in "${!disks[@]}"; do
        dev="/dev/${disks[$i]}"
        model=$(udevadm info --query=all --name=$dev 2>/dev/null | grep ID_MODEL= | cut -d= -f2)
        tran=$(cat /sys/block/${disks[$i]}/device/transport 2>/dev/null)
        [[ "$tran" == "" ]] && tran=$(udevadm info --query=all --name=$dev 2>/dev/null | grep ID_BUS | cut -d= -f2)
        iface="OTHER"
        [[ "$tran" == "ata" ]] && iface="SATA"
        [[ "$tran" == "scsi" ]] && iface="SAS"
        printf "%2d) %-10s 型號:%-20s 介面:%s\n" "$i" "$dev" "$model" "$iface"
    done
}

# 處理選擇模式
case "$mode" in
    1)
        ramp_time=300
        runtime=600
        read -p "請輸入子選項 (a/b/c)：" submode
        case "$submode" in
            a)
                selected_disks=("${disks[@]}")

                # 詢問跑完後是否要關機
                echo "🖥️ 跑完測試後的動作？"
                echo "1️⃣ 跑完測試後待機 180 秒再關機"
                echo "2️⃣ 跑完測試後維持開機"
                read -p "請輸入選項 (1/2)：" shutdown_choice
                [[ "$shutdown_choice" != "1" && "$shutdown_choice" != "2" ]] && { echo "❌ 無效選項"; exit 1; }

                ;;
            b)
                list_disks
                read -p "請輸入要測試的磁碟編號：" idx
                [[ "$idx" =~ ^[0-9]+$ && $idx -ge 0 && $idx -lt ${#disks[@]} ]] || { echo "❌ 無效的磁碟編號"; exit 1; }
                selected_disks=("${disks[$idx]}")
                ;;
            c)
                list_disks
                read -p "請輸入起始編號：" start
                read -p "請輸入結束編號：" end
                selected_disks=("${disks[@]:$start:$(($end - $start + 1))}")
                ;;
            *)
                echo "❌ 無效子選項"; exit 1;;
        esac
        ;;
    2)
        ramp_time=30
        runtime=300
        read -p "請輸入子選項 (b/c)：" submode
        case "$submode" in
            b)
                list_disks
                read -p "請輸入要測試的磁碟編號：" idx
                [[ "$idx" =~ ^[0-9]+$ && $idx -ge 0 && $idx -lt ${#disks[@]} ]] || { echo "❌ 無效的磁碟編號"; exit 1; }
                selected_disks=("${disks[$idx]}")
                ;;
            c)
                list_disks
                read -p "請輸入起始編號：" start
                read -p "請輸入結束編號：" end
                selected_disks=("${disks[@]:$start:$(($end - $start + 1))}")
                ;;
            *)
                echo "❌ 無效子選項"; exit 1;;
        esac
        ;;
    3)
        echo "👋 離開程式"; exit 0;;
    *)
        echo "❌ 無效選項"; exit 1;;
esac

# --- 測試流程區塊 ---

max_disks=120
total=${#selected_disks[@]}
[[ $total -gt $max_disks ]] && total=$max_disks

timestamp=$(date +"%Y%m%d_%H%M%S")
summary_file="summary_${timestamp}.csv"
mkdir -p "RVI_LOG_${timestamp}"
echo "Index,Device,SN,Interface,IOdepth,IOPS,base_iops,Percentage,Pass/Fail" > "$summary_file"

for ((i=0; i<$total; i++)); do
    target="${selected_disks[$i]}"
    fiofile="fio_run_${target}.fio"
    output="fio_result_${target}.json"
    dev_path="/dev/$target"

    tran=$(cat /sys/block/$target/device/transport 2>/dev/null)
    [[ "$tran" == "" ]] && tran=$(udevadm info --query=all --name=$dev_path 2>/dev/null | grep ID_BUS | cut -d= -f2)

    sn=$(udevadm info --query=all --name=$dev_path 2>/dev/null | grep 'ID_MODEL=' | cut -d= -f2)
    [[ "$sn" == "" ]] && sn="UnknownSN"

    if [[ "$tran" == "ata" ]]; then
        bs="6k"; iface="SATA"
    elif [[ "$tran" == "scsi" ]]; then
        bs="2k"; iface="SAS"
    else
        echo "❌ 裝置 $dev_path 使用的傳輸介面是：$tran，無法進行 RVI 測試。"; exit 1;
    fi

    cat > $fiofile <<EOF
[global]
ioengine=libaio
direct=1
time_based=1
runtime=$runtime
ramp_time=$ramp_time
group_reporting
numjobs=1
thread=1
random_generator=tausworthe64
new_group
EOF

    jobcount=0
    for dev in "${disks[@]}"; do
        disk="/dev/$dev"
        [[ "$dev" == "$target" ]] && iodepth=8 || iodepth=1

        tran=$(cat /sys/block/$dev/device/transport 2>/dev/null)
        [[ "$tran" == "" ]] && tran=$(udevadm info --query=all --name=$disk 2>/dev/null | grep ID_BUS | cut -d= -f2)

#SERIAL
        sn_inner=$(udevadm info --query=all --name="$disk" 2>/dev/null | grep 'ID_MODEL=' | cut -d= -f2)
        [[ "$tran" == "ata" ]] && bs="6k" && iface="SATA"
        [[ "$tran" == "scsi" ]] && bs="2k" && iface="SAS"
        [[ "$tran" != "ata" && "$tran" != "scsi" ]] && echo "❌ 裝置 $disk 使用的傳輸介面是：$tran，無法進行 RVI 測試。" && exit 1

        [[ "$sn_inner" == "" ]] && sn_inner="UnknownSN"

        cat >> $fiofile <<EOF

[$dev]
filename=$disk
bs=$bs
rw=randwrite
iodepth=$iodepth
name=${dev}_test_SN_${sn_inner}

EOF
        ((jobcount++))
    done

    echo "📄 已寫入 $jobcount 個磁碟設定至 $fiofile"

    fio $fiofile --output-format=json --output=$output
    echo "✅ 測試完成：$output"

    iops=$(jq -r ".jobs[] | select(.jobname==\"${target}_test_SN_${sn}\") | .write.iops" $output)

# 擷取 SN 前綴（取 "-" 前）
sn_key="${sn%%-*}"

# 抓對應 Base_IOPS
base_iops=$(awk -F',' -v key="$sn_key" 'NR > 1 {
    gsub(/^[ \t]+|[ \t]+$/, "", $1);
    if ($1 == key) {
        print $2;
        exit;
    }
}' HDD_base.csv)

# 預設 fallback
[[ -z "$base_iops" ]] && base_iops="N/A"

# 只保留數字與小數點
base_iops=$(echo "$base_iops" | grep -oE '[0-9]+(\.[0-9]+)?')
iops=$(echo "$iops" | grep -oE '[0-9]+(\.[0-9]+)?')

# 計算 Percentage
if [ -n "$base_iops" ] && [ -n "$iops" ] && \
    awk -v b="$base_iops" 'BEGIN { exit !(b > 0) }'; then

    percentage_val=$(awk -v b="$base_iops" -v i="$iops" \
        'BEGIN { printf("%.2f", (b - i) / b * 100) }')
    percentage="${percentage_val}%"

# Pass/Fail 判斷
    if [[ "$iface" == "SATA" ]]; then
        if awk -v p="$percentage_val" 'BEGIN { exit !(p <= 15) }'; then
            passfail="PASS"
        else
            passfail="FAIL"
        fi
    elif [[ "$iface" == "SAS" ]]; then
        if awk -v p="$percentage_val" 'BEGIN { exit !(p <= 10) }'; then
            passfail="PASS"
        else
            passfail="FAIL"
        fi
    else
        passfail="N/A"
    fi
else
    percentage="N/A"
    passfail="N/A"
fi

    echo "$i,$target,$sn,$iface,8,$iops,$base_iops,$percentage,$passfail" >> "$summary_file"

    mv $fiofile $output "RVI_LOG_${timestamp}/"
done

mv "$summary_file" "RVI_LOG_${timestamp}/"
echo "📦 所有結果已匯出至資料夾：RVI_LOG_${timestamp}/"

# 結束動作
if [[ "$mode" == "1" && "$submode" == "a" ]]; then
    if [[ "$shutdown_choice" == "1" ]]; then
        echo "⏳ 測試完成，系統將於 180 秒後自動關機..."
        sleep 180
        shutdown -h now
    else
        echo "✅ 測試完成，系統維持開機狀態"
    fi
fi
