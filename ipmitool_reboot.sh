#!/bin/bash

i=0
while [ "($i)"=="($i)" ]
do

i=$(($i+1))

echo -e "ipmitool_reboot_&_info Number ($i)"

echo -e "<======== ipmitool mc info =============>"
ipmitool -H 192.168.19.212 -U root -P root -I lanplus mc info
echo -e "</======= ipmitool mc info =============>\n"
sleep 1

echo -e "<======== ipmitool fru  ================>"
ipmitool -H 192.168.19.212 -U root -P root -I lanplus fru
echo -e "</======= ipmitool fru  ================>\n"
sleep 1

echo -e "<======== ipmitool sel list ============>"
ipmitool -H 192.168.19.212 -U root -P root -I lanplus sel list
echo -e "</======= ipmitool sel list ============>\n"
sleep 1

echo -e "<======== ipmitool power status ========>"
ipmitool -H 192.168.19.212 -U root -P root -I lanplus power status
echo -e "</======= ipmitool power status ========>\n"
sleep 1

echo -e "<======== ipmitool power reset =========>"
ipmitool -H 192.168.19.212 -U root -P root -I lanplus power reset
echo -e "Sleep 180sec"
echo -e "</======= ipmitool power reset =========>\n"
sleep 1

echo -e "ipmitool_reboot_&_info Number ($i)"
sleep 180

done
