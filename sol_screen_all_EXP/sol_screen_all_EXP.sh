#!/bin/bash
#
# Auther: luke.chen@aicipc.com.tw
# History: 2021-05-13
# Read J4078-01 EXP console info over BMC_SOL

LogFileName=zone.txt

# rm zone.txt
if [ -f "${LogFileName}" ] ; then
    rm "${LogFileName}"
fi

# clear terminal
clear

# Set BMC_SOL to EXP_hub.
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin raw 0x36 0x54 0x01

# Deactivate old sol session.
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin sol deactivate

# Open screen window to show EXP_hub console over BMC_SOL.
gnome-terminal -- bash -c "screen -m -S sol -L -Logfile ${LogFileName} ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin sol activate"

# Choose BMC_SOL connent number to EXP—Hub, Edge-0, Edge-1 ,Edge-2 
for num in 1 2 3 4
do
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin raw 0x36 0x54 0x0${num}

## Init BMC_SOL to show "cmd >" on screen
  screen -S sol -X stuff ""
  sleep 1
  screen -S sol -X eval "stuff \015"
  sleep 1
  screen -S sol -X eval "stuff \015"
  sleep 1

## read EXP consol info (rev, showmfg,...)
  for var in sensor rev showmfg sasaddr phyinfo sensor
  do
    # read rev
    screen -S sol -X eval "stuff \015"
    sleep 1
    screen -S sol -X stuff "${var}" 
    sleep 1
    screen -S sol -X eval "stuff \015"
    screen -S sol -X eval "stuff \015"
    sleep 3
  done
done

# exit sol (use ~.)
screen -S sol -X stuff ""
sleep 1
screen -S sol -X eval "stuff \015"
sleep 1
screen -S sol -X stuff "~."
sleep 1
screen -d sol
sleep 1
screen -X -S sol quit

# show log 
cat ${LogFileName}

