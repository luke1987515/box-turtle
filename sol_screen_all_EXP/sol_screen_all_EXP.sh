#!/bin/bash
#
# Auther: luke.chen@aicipc.com.tw
# Progream: Read J4078-01 EXP console info over BMC_SOL
# Progream: Read J4078-02-04X EXP console info over BMC_SOL
# Lincese: CC0
# History: 2021-05-13 
# note: init
# History: 2021-05-14 
# note: add delay time between ipmi command.
# History: 2024-03-27 
# note: Change 0x36 0x54 to 0x3C 0x40 for J4078-02-04X


LogFileName=zone.txt
#BMC_Passwd=admin
BMC_Passwd=admin123
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
#ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x36 0x54 0x01
ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x3C 0x40 0x00
sleep ${CmdDelayTime}

# ### Choose BMC_SOL connent number to EXP—Hub, Edge-0, Edge-1, Edge-2, Edge-3 
for num in 0 1 2 3 4
do

# Deactivate old sol session.
ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} sol deactivate
sleep ${CmdDelayTime}

# Set ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x36 0x54 0x0${num}
echo ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x3C 0x40 0x0${num}
ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x3C 0x40 0x0${num}
sleep ${CmdDelayTime}

# Read BMC_SOL current stauts(number) on witch EXP_hub.
#ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x36 0x54 0x00
echo ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x3C 0x40
ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x3C 0x40
sleep ${CmdDelayTime}

# Open screen window to show EXP_hub console over BMC_SOL.
gnome-terminal -- bash -c "screen -m -S sol -L -Logfile ${LogFileName} ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} sol activate"
sleep ${CmdDelayTime}

# Choose BMC_SOL connent number to EXP—Hub, Edge-0, Edge-1, Edge-2, Edge-3 
#for num in 0 1 2 3 4
#do


## Init BMC_SOL to show "cmd >" on screen
  sleep $((${ExpDelayTime} + 1)) 
  screen -S sol -X stuff ""
  sleep ${ExpDelayTime}
  screen -S sol -X eval "stuff \015"
  sleep ${ExpDelayTime}
  screen -S sol -X eval "stuff \015"
  sleep ${ExpDelayTime}

## read EXP consol info (rev, showmfg,...)
  for var in sensor rev showmfg enclosure_addr sasaddr phyinfo zonecount show_role edfb sensor
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
#done

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
  ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} sol deactivate
  sleep ${CmdDelayTime}

# ### loop Choose BMC_SOL
done

# Set BMC_SOL to EXP_hub.
#ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x36 0x54 0x01
ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x3C 0x40 0x00
sleep ${CmdDelayTime}

# Read BMC_SOL current stauts(number) on witch EXP_hub.
#ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x36 0x54 0x00
ipmitool -I lanplus -H 192.168.11.11 -U admin -P ${BMC_Passwd} raw 0x3C 0x40
sleep ${CmdDelayTime}

# End log file
echo "" >>  ${LogFileName}

# show log 
cat ${LogFileName}

