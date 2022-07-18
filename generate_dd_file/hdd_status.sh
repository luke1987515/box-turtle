#!/bin/bash
# auther: luke.chen 
# get hdd_status
# apt install smartmontools
# 


lsblk | awk '{print $1}' | grep -v 'loop\|NAME\|├─\|└─' > lsblk.log

while read line
do
 ##echo \[dev-$line\]
 ##echo filename=/dev/$line
 echo /dev/sda
 smartctl -i /dev/$line | grep "Device Model"
 smartctl -H /dev/$line | grep self-assessment 
done < lsblk.log

rm -rf lsblk.log
