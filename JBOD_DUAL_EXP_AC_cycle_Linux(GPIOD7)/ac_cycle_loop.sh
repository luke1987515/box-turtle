#!/bin/bash
# Program:
#       This program do JBOD AC Cycle with GPIOD7 (MB)
# History:
# 2022/12/23 luke.chen  First release
# 2023/01/07 luke.chen  Change ctrl GPIOD7 (MB) 

echo "################"
echo JBOD AC Cycle Tool
echo "################"
echo

COUNTER=1

while true
do
    echo "Power ON"
    # GPIOD7 to ON
    #./022.ac_power_on.sh
    ./lxRW_x64 p2a write 0x1e780000 0xfffff8bb > /dev/null 2>&1

    if [ $COUNTER -lt "301" ]; then
        if sudo sg_scan -i | grep -q "WDC" ; then
            echo "JBOD is ON"
            echo "Wait 90 sec to record UUT information"
            sleep 90
            echo COUNTER=$COUNTER
            echo ======count_$COUNTER======= >> log.txt
            lsblk >> log.txt           
        else
            echo "Wait Expander Power on"
            sleep 1
            echo COUNTER=$COUNTER
            continue
        fi
        COUNTER=$[$COUNTER + 1]

        echo "Wait Other Host get EXP info (5sec)"
        sleep 5
        echo "Power OFF (60sec)"
        #echo "Wait 60 sec to Power ON"
        # GPIOD7 to OFF
        #./021.ac_power_off.sh
        ./lxRW_x64 p2a write 0x1e780000 0x7ffff8bb > /dev/null 2>&1
        sleep 60
    else
        echo "COUNTER=$COUNTER"
        echo "END LOOP"
        break
    fi
done
