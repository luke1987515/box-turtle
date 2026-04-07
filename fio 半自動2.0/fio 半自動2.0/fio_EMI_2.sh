#!/bin/bash
rm -rf fio.cfg
rm -rf HD_list.dat
echo '[global]' >>fio.cfg
echo 'ioengine=psync' >>fio.cfg

#---------------------------------
echo 'direct=1' >>fio.cfg
echo 'numjobs=4' >>fio.cfg
echo 'iodepth=4' >>fio.cfg
echo "rw=read" >>fio.cfg
echo "bs=4k" >>fio.cfg
echo "runtime=72h" >>fio.cfg
echo 'time_based=1' >>fio.cfg
#---------------------------------

#---------------------------------
lsblk |grep disk |sed -e "1d" |cut -c 1-7 > HD_list.dat
HD=` lsblk |grep disk |sed -e "1d" |wc -l `
for ((i=1; i<=${HD} ;i++))
do
	a=` cat HD_list.dat |sed -n "$i"p `
	echo "[dev/$a]" >>fio.cfg
	echo "filename=/dev/$a" >>fio.cfg
done
#---------------------------------

#---------------------------------
lsblk |grep disk |sed -e "1d"
echo "注意:確認硬碟清單內是否有主系統硬碟代號"
echo "有的話請勿執行本程式"
echo "確認硬碟是否有正確判讀?硬碟數量:$HD(不含系統碟)"
sleep 5
fio fio.cfg
