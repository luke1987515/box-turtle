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
echo 'numjobs=4'
#---------------------------------

#---------------------------------
echo 'iodepth=4' >>fio.cfg
echo 'IOdepth=4'
#---------------------------------

#---------------------------------
echo -e "\033[32mTest mode?(Enter header number)  \033[0m"
select var in "write" "read" "randwrite" "randread"; do

break

done

echo "rw=$var" >>fio.cfg
echo -e "\033[32mmode $var \033[0m"
echo "-------------------------------------"
#---------------------------------

#---------------------------------
echo -e "\033[32mIO size(Reference input Write: 128k Read: 128k Random write: 4k Random read: 4k) \033[0m"

read io

echo "bs=$io" >>fio.cfg
echo -e "\033[32mIO size $io \033[0m"
echo "-------------------------------------"
#---------------------------------

#---------------------------------
echo -e "\033[32mtime(Remember to call the unit h,m,s) \033[0m"

read t

echo "runtime=$t" >>fio.cfg
echo 'time_based=1' >>fio.cfg
echo -e "\033[32mtime$t \033[0m"
echo "-------------------------------------"
#---------------------------------

#---------------------------------
echo -e "\033[32mPlease enter the code name of the system disk \033[0m"

read osname

delname=` lsblk |grep disk |grep -n $osname |cut -d : -f 1`

lsblk |grep disk |sed -e "${delname}d" |cut -c 1-7 > HD_list.dat
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
lsblk |grep disk |sed -e "${delname}d"
echo "====================================="
echo "-------------------------------------"
echo "Confirm whether the hard disk is correctly interpreted? Number of hard disks:$HD"
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
