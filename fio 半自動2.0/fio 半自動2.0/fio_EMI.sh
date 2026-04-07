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
lsblk |grep disk |grep -v sda |cut -c 1-7 > HD_list.dat
HD=` lsblk |grep disk |grep -v sda |wc -l `
for ((i=1; i<=${HD} ;i++))
do
	a=` cat HD_list.dat |sed -n "$i"p `
	echo "[dev/$a]" >>fio.cfg
	echo "filename=/dev/$a" >>fio.cfg
done
#---------------------------------

#---------------------------------
lsblk |grep disk |grep -v sda
echo "注意:確認硬碟清單內是否有主系統硬碟代號"
echo "有的話請勿執行本程式"
echo "確認硬碟是否有正確判讀?硬碟數量:$HD(不含系統碟)"
confirm(){
  echo -n "確定?[yes/no]: "
    while : ; do
      read input
      input=$(perl -e "print qq/\L${input}\E/")
      case ${input} in
        y|ye|yes)
          fio fio.cfg
          break
          ;;
        n|no)
          echo "operation is cancelled!!!"
          exit 0
          ;;
        *)
          echo -n "invalid choice, choose again!!! [yes|no]: "
          ;;
      esac
    done
}

confirm
#---------------------------------



#fio /root/Desktop/test/fio.cfg
