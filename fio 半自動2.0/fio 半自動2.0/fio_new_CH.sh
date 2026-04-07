#!/bin/bash
rm -rf fio.cfg
rm -rf HD_list.dat
echo '[global]' >>fio.cfg
echo 'ioengine=psync' >>fio.cfg
#sync psync vsync libaio posixaio solarisaio windowsaio mmap splice syslet-rw null net netsplice cpuio guasi rdma external
#---------------------------------
echo 'direct=1' >>fio.cfg
echo 'io buffer off'
#---------------------------------

#---------------------------------
echo 'numjobs=4' >>fio.cfg
echo '測試執行緒=4'
#---------------------------------

#---------------------------------
echo 'iodepth=1' >>fio.cfg
echo 'IO深度=1'
#---------------------------------

#---------------------------------
echo -e "\033[32m測試模式?[1-7]  \033[0m"
select var in "write" "read" "randwrite" "randread" "rw" "readwrite" "randrw" ; do

break

done

echo "rw=$var" >>fio.cfg
echo -e "\033[32m模式 $var \033[0m"
echo "-------------------------------------"
#---------------------------------

#---------------------------------
echo -e "\033[32mIO大小(參考輸入 寫:128k 讀:128k 隨機寫:4k 隨機讀:4k)[4k-128k] \033[0m"

read io

echo "bs=$io" >>fio.cfg
echo -e "\033[32mIO大小 $io \033[0m"
echo "-------------------------------------"
#---------------------------------

#---------------------------------
echo -e "\033[32m運行時間(記得打單位h,m,s)[1s-1234m] \033[0m"

read t

echo "runtime=$t" >>fio.cfg
echo 'time_based=1' >>fio.cfg
echo -e "\033[32m運行時間$t \033[0m"
echo "-------------------------------------"
#---------------------------------

#---------------------------------
#echo -e "\033[32m請輸入系統碟的代號(測試中將會取消選取系統碟)[sda-sdg] \033[0m"
#
#read osname
#
#delname=`lsblk |grep disk |grep -n $osname |cut -d : -f 1`
#
##lsblk |grep disk |sed -e "${delname}d" |cut -c 1-7 >> HD_list.dat
## 改用 awk '{print $1}' 擷取 硬碟名稱長度
#lsblk |grep disk |sed -e "${delname}d" |awk '{print $1}' >> HD_list.dat
#
#HD=` lsblk |grep disk |sed -e "1d" |wc -l `
#for ((i=1; i<=${HD} ;i++))
#do
#	a=` cat HD_list.dat |sed -n "$i"p `
#	echo "[dev/$a]" >>fio.cfg
#	echo "filename=/dev/$a" >>fio.cfg
##done
##---------------------------------

#---------------------------------
echo -e "\033[32m請輸入要排除的磁碟代號 (例如: sda|sdb) \033[0m"
read osname

# 1. 使用 lsblk 時，利用 -e 參數排除特定的主裝置編號 (7 是 loop 裝置)
# 2. 使用 grep -v 排除光碟機 (sr) 和你指定的系統碟 (osname)
# 3. awk '{print $1}' 抓取第一欄名稱
lsblk -dnio NAME -e 7 | grep -vE "sr|$osname" > HD_list.dat

# 重新計算硬碟數量
HD=$(wc -l < HD_list.dat)

# 寫入 fio.cfg
while read -r a; do
    echo "[dev/$a]" >> fio.cfg
    echo "filename=/dev/$a" >> fio.cfg
done < HD_list.dat
#---------------------------------



#---------------------------------
echo "_____________________________________"
echo "====================================="
#lsblk |grep disk |sed -e "${delname}d"
cat HD_list.dat
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
#Author:SDD Harry Chang
#
#
#fio /root/Desktop/test/fio.cfg
