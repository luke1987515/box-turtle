#!/bin/bash
#
# Program: Read E1S temperature from BMC sensor information.
# Author: luke.chen@aicipc.com.tw
# License: CC0
# History:
#   Date: 2021-05-20
#   Note: First release.
#   Date: 2021-05-21
#   Note: Pop up and run script in new window.


# Open a new gnome-terminal
# gnome-terminal --window --geometry=80x24+1840+24 --

# Environmental variables
IP="192.168.11.11"
UserName="admin"
PassWord="admin"

Sensor_ID="Temp_PSU1"

TempFileName="temp.log"
ShortFileName="Summary.log"
FullFileName="All_sensor.log"

SleepTime=2

i=0 # count from 0

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

read_E1S_temp() {
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
}

endless_loop() {
  # Endless while loop
  while true
  do
    read_E1S_temp
  done
}

# Get xdpinfo form new windows position
screen_width=$(xdpyinfo | awk '/dimensions/{print $2}' | awk -F "x" '{print $1}')
screen_height=$(xdpyinfo | awk '/dimensions/{print $2}' | awk -F "x" '{print $2}')

# Show new window
new_window() { cp $0 $0.tmp; sed -i -e 's/new_window/\#new_window/i' $0.tmp; sed -i -e 's/\#endless_loop/endless_loop/i' $0.tmp;  gnome-terminal --geometry=80x24+$(($screen_width-80)) -- bash -c "$0.tmp"; }

#endless_loop
new_window
