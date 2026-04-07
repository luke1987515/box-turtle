#!/bin/bash
rm -rf fio.cfg
rm -rf HD_list.dat
echo '[global]' >>fio.cfg
echo 'ioengine=psync' >>fio.cfg

#---------------------------------
echo 'direct=1' >>fio.cfg
echo 'io buffer off'
#---------------------------------

#---------------------------------
echo 'numjobs=4' >>fio.cfg
echo '測試執行緒=4'
#---------------------------------

#---------------------------------
echo 'iodepth=4' >>fio.cfg
echo 'IO深度=4'
#---------------------------------

#---------------------------------
echo -e "\033[32m測試模式?  \033[0m"
select var in "write" "read" "randwrite" "randread"; do

break

done

echo "rw=$var" >>fio.cfg
echo -e "\033[32m模式 $var \033[0m"
echo "-------------------------------------"
#---------------------------------

#---------------------------------
echo -e "\033[32mIO大小(參考 w:128k r:128k rw:4k rr:4k) \033[0m"

read io

echo "bs=$io" >>fio.cfg
echo -e "\033[32mIO大小 $io \033[0m"
echo "-------------------------------------"
#---------------------------------

#---------------------------------
echo -e "\033[32m運行時間(單位h,m,s) \033[0m"

read t

echo "runtime=$t" >>fio.cfg
echo 'time_based=1' >>fio.cfg
echo -e "\033[32m運行時間$t \033[0m"
echo "-------------------------------------"
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
echo "_____________________________________"
echo "====================================="
lsblk |grep disk |sed -e "1d"
echo "====================================="
echo "-------------------------------------"
echo "確認硬碟是否有正確判讀?硬碟數量:$HD"
confirm(){
  echo -n "Are your sure[yes/no]: "
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
