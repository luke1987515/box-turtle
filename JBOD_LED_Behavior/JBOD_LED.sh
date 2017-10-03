#!/bin/bash
# Test JBOD LED Behavior
#
# 2017-08-30 10:45:59 luke.chen

# yum install sg3_utils
# sg_map -i | grep AIC
sg_map -i | grep Edge | awk '{print $1}'| cut -d '/' -f3- > sg_Edge_info.txt

if [$(cat sg_Edge_info.txt) == ""]; then
sg_map -i | grep AIC | awk '{print $1}'| cut -d '/' -f3- > sg_Edge_info.txt
fi

# count Edge number
wc -l < sg_Edge_info.txt > Edge_number.txt
# echo $(cat Edge_number.txt) e.g 3-Edge in JBOD

# show & Log Edge descriptor: Disk0??

for edge_info in $(cat sg_Edge_info.txt)
do
   #echo /dev/$edge_info
   #echo sg_ses --page=0x7 /dev/$edge_info
   sg_ses --page=0x7 /dev/$edge_info | grep Disk0 | cut -d ' ' -f10- > "$edge_info".txt
   echo
done

# light JBOD LED Behavior
ses_page="1:7:1"
for ses_page in $(cat ses_Page_info.txt)
do 
echo  $ses_page

for edge_info in $(cat sg_Edge_info.txt)
do
  for disk_info in $(cat "$edge_info".txt)
  do
    echo sg_ses --descriptor=$disk_info --set=$ses_page /dev/$edge_info
    sg_ses --descriptor=$disk_info --set=$ses_page /dev/$edge_info
    sleep 0.5

  done
done

# pasue 5 sec
read -p "Continuing in 5 Seconds...." -t 5
echo "Continuing ...."

# clear set
for edge_info in $(cat sg_Edge_info.txt)
do
  for disk_info in $(cat "$edge_info".txt)
  do
    echo sg_ses --descriptor=$disk_info --clear=$ses_page /dev/$edge_info
    sg_ses --descriptor=$disk_info --clear=$ses_page /dev/$edge_info
    sleep 0.5

  done
done

# SES_Page done
done
