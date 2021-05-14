#!/bin/bash
#
# Auther: luke.chen@aicipc.com.tw
# Progream: Read J4078-01 EXP console info over BMC_SOL
# Lincese: CC0
# History: 2021-05-13 
# note: init
# History: 2021-05-14 
# note: add delay time between ipmi command.

LogFileName=zone.txt
CmdDelayTime=1
ExpDelayTime=1

# rm zone.txt
if [ -f "${LogFileName}" ] ; then
    rm "${LogFileName}"
fi

# Create log file
echo "" >  ${LogFileName}

# rm old screen session.
screen -d sol
sleep ${CmdDelayTime}
screen -X -S sol quit
sleep ${CmdDelayTime}

# clear terminal
clear
sleep ${CmdDelayTime}

# Set BMC_SOL to EXP_hub.
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin raw 0x36 0x54 0x01
sleep ${CmdDelayTime}

# Deactivate old sol session.
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin sol deactivate
sleep ${CmdDelayTime}

# Open screen window to show EXP_hub console over BMC_SOL.
gnome-terminal -- bash -c "screen -m -S sol -L -Logfile ${LogFileName} ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin sol activate"
sleep ${CmdDelayTime}

# Choose BMC_SOL connent number to EXP—Hub, Edge-0, Edge-1 ,Edge-2 
for num in 1 2 3 4
do
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin raw 0x36 0x54 0x0${num}

## Init BMC_SOL to show "cmd >" on screen
  sleep $((${ExpDelayTime} + 1)) 
  screen -S sol -X stuff ""
  sleep ${ExpDelayTime}
  screen -S sol -X eval "stuff \015"
  sleep ${ExpDelayTime}
  screen -S sol -X eval "stuff \015"
  sleep ${ExpDelayTime}

## read EXP consol info (rev, showmfg,...)
  for var in sensor rev showmfg sasaddr phyinfo zonecount show_role sensor
  do
    # read rev
    screen -S sol -X eval "stuff \015"
    sleep ${ExpDelayTime}
    screen -S sol -X stuff "${var}" 
    sleep ${ExpDelayTime}
    screen -S sol -X eval "stuff \015"
    sleep ${ExpDelayTime}
    screen -S sol -X eval "stuff \015"
    sleep $((${ExpDelayTime} + 1)) 
  done
done

# exit sol (use ~.)
screen -S sol -X stuff ""
sleep ${CmdDelayTime}
screen -S sol -X eval "stuff \015"
sleep ${CmdDelayTime}
screen -S sol -X stuff "~."
sleep ${CmdDelayTime}
screen -d sol
sleep ${CmdDelayTime}
screen -X -S sol quit
sleep ${CmdDelayTime}

# Deactivate old sol session.
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin sol deactivate
sleep ${CmdDelayTime}

# Set BMC_SOL to EXP_hub.
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin raw 0x36 0x54 0x01
sleep ${CmdDelayTime}

# Read BMC_SOL current stauts(number) on witch EXP_hub.
ipmitool -I lanplus -H 192.168.11.11 -U admin -P admin raw 0x36 0x54 0x00
sleep ${CmdDelayTime}

# End log file
echo "" >>  ${LogFileName}

# show log 
cat ${LogFileName}

