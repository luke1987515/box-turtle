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
echo 'iodepth=4'
#---------------------------------

#---------------------------------
echo 'Test mode?'
select var in "write" "read" "randwrite" "randread"; do

break

done

echo "rw=$var" >>fio.cfg
echo "mode $var"
#---------------------------------

#---------------------------------
echo 'IO size?(Reference w:128k r:128k rw:4k rr:4k)'

read io

echo "bs=$io" >>fio.cfg
echo "IO size = $io"
#---------------------------------

#---------------------------------
echo 'runtime(Unit:h,m,s)'

read t

echo "runtime=$t" >>fio.cfg
echo 'time_based=1' >>fio.cfg
echo "runtime=$t"
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

echo "Check if the hard disk is correctly read"
echo "Number of hard drives: $HD"
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
