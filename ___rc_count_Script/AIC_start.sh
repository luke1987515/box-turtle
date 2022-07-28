#!/bin/sh

sleep 20

count=`cat /root/FILE`

echo $(($count+1)) > /root/FILE

DATE=`date`

#----------------------------------------------------------------------------------------------------
echo "====================================================" >> /root/start.log
echo "$DATE" >> /root/start.log
echo "The --$count-- data" >> /root/start.log
echo "----------------------------------------------------" >> /root/start.log

echo "Memory data" >> /root/start.log
dmidecode 17 |grep "Range Size" >> /root/start.log
echo "----------------------------------------------------" >> /root/start.log

echo "HDD" >> /root/start.log
lsblk >> /root/start.log
echo "----------------------------------------------------" >> /root/start.log

echo "PCIe" >> /root/start.log
lspci -s 43:00.0 >> /root/start.log
lspci -s 43:00.0 -vv | grep LnkCap: >> /root/start.log
lspci -s 43:00.0 -vv | grep LnkSta: >> /root/start.log
echo.
lspci -s 44:00.0 >> /root/start.log
lspci -s 44:00.0 -vv | grep LnkCap: >> /root/start.log
lspci -s 44:00.0 -vv | grep LnkSta: >> /root/start.log
echo.
lspci -s c1:00.0 >> /root/start.log
lspci -s c1:00.0 -vv | grep LnkCap: >> /root/start.log
lspci -s c1:00.0 -vv | grep LnkSta: >> /root/start.log
echo.
lspci -s c2:00.0 >> /root/start.log
lspci -s c2:00.0 -vv | grep LnkCap: >> /root/start.log
lspci -s c2:00.0 -vv | grep LnkSta: >> /root/start.log
echo.
lspci -s 81:00.0 >> /root/start.log
lspci -s 81:00.0 -vv | grep LnkCap: >> /root/start.log
lspci -s 81:00.0 -vv | grep LnkSta: >> /root/start.log
echo.
lspci -s 81:00.1 >> /root/start.log
lspci -s 81:00.1 -vv | grep LnkCap: >> /root/start.log
lspci -s 81:00.1 -vv | grep LnkSta: >> /root/start.log
echo "----------------------------------------------------" >> /root/start.log


echo "SDR" >> /root/start.log
ipmitool sdr >> /root/start.log
echo "----------------------------------------------------" >> /root/start.log

echo "SEL" >> /root/start.log
ipmitool sel elist >> /root/start.log
ipmitool sel clear >> /root/start.log
echo "----------------------------------------------------" >> /root/start.log

echo "Dmesg" >> /root/start.log
dmesg |grep -E "Error|error|Fail|fail" >> /root/start.log
dmesg -C >> /root/start.log
echo "----------------------------------------------------" >> /root/start.log

sync
sync
sync

while :
do 
sleep 30;
##poweroff;
done
