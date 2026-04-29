#!/bash/bin

# 1. 檢查是否為 root 權限
if [ "$EUID" -ne 0 ]; then 
  echo "請使用 root 權限執行此腳本 (sudo)。"
  exit 1
fi

# 2. 掃描 mpath 裝置
echo "正在掃描系統中的 Multipath 裝置..."
MPATH_DEVICES=$(multipath -ll | grep "dm-" | awk '{print $1}')

if [ -z "$MPATH_DEVICES" ]; then
    echo "未發現任何 mpath 裝置，請檢查 multipath -ll 輸出。"
    exit 1
fi

# 計算數量
# 使用 grep -c 或 wc -l，這裡確保即使沒裝置也不會噴錯
MPATH_COUNT=$(echo "$MPATH_DEVICES" | grep -v '^$' | wc -l)

echo "--------------------------------------"
echo "裝置列表："
echo "$MPATH_DEVICES" | sed 's/^/  [+] /'
echo "偵測結果：共發現 $MPATH_COUNT 個 Multipath 裝置"
echo "--------------------------------------"

# 3. 互動確認 (新增測試時間詢問)
read -p "是否對以上所有裝置進行寫入壓力測試? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "已取消測試。"
    exit 0
fi

# 新增：詢問測試時間
read -p "請輸入測試持續時間 (秒，預設 60): " TEST_TIME
TEST_TIME=${TEST_TIME:-60} # 如果使用者直接按 Enter，則使用預設值 60

# 檢查是否為純數字
if ! [[ "$TEST_TIME" =~ ^[0-9]+$ ]]; then
    echo "錯誤：請輸入有效的數字。"
    exit 1
fi

# 警告訊息
echo "！！！警告：這將會抹除上述裝置上的所有資料！！！"
read -p "輸入 'DESTROY' 以確認執行: " FINAL_CHECK
if [ "$FINAL_CHECK" != "DESTROY" ]; then
    echo "確認失敗，退出腳本。"
    exit 0
fi

# 4. 動態產生 fio.cfg (將 runtime 改為變數)
CFG_FILE="stress_mpath.fio"
echo "正在產生 $CFG_FILE (測試時間: ${TEST_TIME}s)..."

cat << EOF > $CFG_FILE
[global]
ioengine=libaio
direct=1
rw=write
bs=512k
numjobs=1
iodepth=4
runtime=$TEST_TIME
time_based
group_reporting
EOF

# 為每個裝置加入一個 job
for dev in $MPATH_DEVICES; do
    echo "" >> $CFG_FILE
    echo "[$dev]" >> $CFG_FILE
    echo "filename=/dev/mapper/$dev" >> $CFG_FILE
done

echo "設定檔已準備就緒。"

# 5. 執行 fio
echo "開始執行 fio 壓力測試..."
fio $CFG_FILE

echo "--------------------------------------"
echo "測試完成！"
