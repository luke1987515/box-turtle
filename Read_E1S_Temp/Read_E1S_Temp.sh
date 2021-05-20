#!/bin/bash
#
# Program: Read E1S temperature from BMC sensor information.
# Author: luke.chen@aicipc.com.tw
# License: CC0
# History: 2021-05-20
#   Note: First release.

# Environmental variables
IP=192.168.11.11
UserName=admin
PassWord=admin

Sensor_ID=Temp_PSU1

TempFileName=temp.log
ShortFileName=Summary.log
FullFileName=All_sensor.log

SleepTime=5

# Clear old tmp file
if [ -f "${TempFileName}" ] ; then
    rm "${TempFileName}"
fi

# Clear old tmp file
if [ -f "${ShortFileName}" ] ; then
    mv "${ShortFileName}" "${ShortFileName}".bak
fi

# Clear old tmp file
if [ -f "${FullFileName}" ] ; then
    mv "${FullFileName}" "${FullFileName}".bak
fi

# Main function

i=0
# Endless while loop
while true
do
  # Title info
  DateTime=$(date '+%Y-%m-%d_%H:%M:%S')
  Title="("${i}") "${DateTime}
  # Get sensor info
  ipmitool -I lanplus -H ${IP} -U ${UserName} -P ${PassWord} sensor > "${TempFileName}"

  # Get sdr get Seneor_ID
  #ipmitool -I lanplus -H ${IP} -U ${UserName} -P ${PassWord} sdr get ${Seneor_ID}

  # if $4 is "ok" show "PASS" else show "FAIL" & sensor info
  if [[ $(awk -F '|' '$0 ~ /'${Sensor_ID}'/{print $4}' ${TempFileName}) == " ok    " ]]
  then
    echo ${Title} : PASS | tee -a "${ShortFileName}" "${FullFileName}"
    awk -F '|' '$0 ~ /'${Sensor_ID}'/{print $1 "|" $2 "|" $3 "|" $4 "|" $9}' ${TempFileName} \
    | tee -a "${ShortFileName}"
    echo "" | tee -a "${ShortFileName}" "${FullFileName}"
  else
    echo ${Title} : FAIL | tee -a "${ShortFileName}" "${FullFileName}"
    # Reformat TempFile
    awk -F '|' '$0 ~ /'${Sensor_ID}'/{print $1 "|" $2 "|" $3 "|" $4 "|" $9}' ${TempFileName} \
    | tee -a "${ShortFileName}"
    echo "" | tee -a "${ShortFileName}"
  fi

  # End this cycle, dump temp  in All_xxx.log
  cat "${TempFileName}" >> "${FullFileName}"
  echo "" >> "${FullFileName}"

  # i++
  i=$(($i+1))

  # sleep
  sleep ${SleepTime}
done
