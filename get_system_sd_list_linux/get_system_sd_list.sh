#!/bin/bash

# 定義 ANSI 轉義碼來設置顏色
RED='\033[0;31m'
NC='\033[0m' # 恢復顏色為預設值

# get OS disk
echo
echo \# find OS disk
echo "lsblk | grep boot | cut -d \" \" -f 1 | cut -c 7- | rev | cut -c 2- | rev"

OS_disk=$(lsblk | grep boot | cut -d " " -f 1 | cut -c 7- | rev | cut -c 2- | rev)

echo
echo Your OS disk is \: $OS_disk

echo -e "${RED}$OS_disk${NC}"


# list avail disk in system without OS disk
echo
echo \# List disk in system without OS disk
echo "lsblk | cut -d \" \" -f 1 | grep sd | grep -v ^$OS_disk$ | grep -v $OS_disk[0-9]"

lsblk | cut -d " " -f 1 | grep sd | grep -v ^$OS_disk$ | grep -v $OS_disk[0-9]

## dd disk
# echo
# echo dd list disk \( DO NOT DO IT \)
# arry=($(lsblk | cut -d " " -f 1 | grep sd | grep -v ^$OS_disk$ | grep -v $OS_disk[0-9] | xargs))
#
#for disk in "${arry[@]}"
#do
#    echo "$disk"
#    #dd if=/dev/zero of=/dev/$disk bs=4k count=40k status=progress
#done
