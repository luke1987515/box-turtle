#!/bin/bash

# ==========================================================
# 程式目的：自動掃描當前目錄下的 .md5sum 檔案並驗證完整性
# ==========================================================

# 定義顏色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # 無顏色 (No Color)

# 取得目錄下所有 .md5sum 檔案
shopt -s nullglob
sum_files=(*.md5sum)

if [ ${#sum_files[@]} -eq 0 ]; then
    echo -e "${YELLOW}Warning: No .md5sum files found.${NC}"
    exit 0
fi

for sum_file in "${sum_files[@]}"; do
    # 移除 .md5sum 字尾取得目標檔名
    target_file="${sum_file%.md5sum}"

    # 1. 檢查目標檔案是否存在
    if [ -f "$target_file" ]; then
        
        # 2. 取得預期雜湊值 (讀取第一欄)
        expected_hash=$(awk '{print $1}' "$sum_file")
        
        # 3. 計算實際雜湊值
        # linux 下 md5sum 輸出格式為 "hash  filename"
        actual_hash=$(md5sum "$target_file" | awk '{print $1}')

        # 4. 比對結果
        if [ "$expected_hash" == "$actual_hash" ]; then
            echo -e "Check ${target_file}: [${GREEN}PASS${NC}]"
        else
            echo -e "Check ${target_file}: [${RED}FAIL${NC}]"
            echo "  - Expected: $expected_hash"
            echo "  - Actual:   $actual_hash"
        fi
    else
        echo -e "Check ${sum_file}: [${YELLOW}SKIPPED${NC}] (Target file '${target_file}' not found)"
    fi
done
