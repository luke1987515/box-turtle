#!/bin/bash
# Program:
#       This program do JBOD AC Cycle with CH340 USB
# History:
# 2022/12/23 luke.chen  First release

echo "################"
echo JBOD AC Cycle Tool
echo "################"
echo

function get_ttyUSB () {
  for sysdevpath in $(find /sys/bus/usb/devices/usb*/ -name dev); do
      (
          syspath="${sysdevpath%/dev}"
          devname="$(udevadm info -q name -p $syspath)"
          [[ "$devname" == "bus/"* ]] && exit
          eval "$(udevadm info -q property --export -p $syspath)"
          #[[ -z "$ID_USB_DRIVER" ]] && exit
          [[ "$ID_USB_DRIVER" != "pl2303" ]] && exit
          echo "/dev/$devname"
      )
  done
}



COUNTER=1

while true
do
    echo "Power ON"
    # CH340 USB to ON
    sudo /bin/sh -c "echo -n -e '\xA0\x01\x00\xA1' > $(get_ttyUSB)" # COM-NO

    if [ $COUNTER -lt "3" ]; then
        if sudo sg_scan -i | grep -q "SAMo" ; then
            echo JBOD is ON
            echo "Wait 90 sec to record UUT information"
            sleep 1
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
        echo "Power OFF"
        #echo "Wait 60 sec to Power ON"

        # CH340 USB to OFF
        sudo /bin/sh -c "echo -n -e '\xA0\x01\x01\xA2' > $(get_ttyUSB)" # COM-NC
        sleep 1
    else
        echo "COUNTER=$COUNTER"
        echo "END LOOP"
        break
    fi
done
