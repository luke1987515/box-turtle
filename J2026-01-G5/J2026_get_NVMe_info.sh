
# Make sure you have run_picocom.sh in the same folder
#
# #!/bin/bash
# #while read ln; do
# #     echo "$ln"
# #     echo "$ln" | picocom -qx 1000 -b 115200 /dev/ttyS6 >> foo.txt
# #done < cmd.txt
#
# echo -ne "\r" | picocom -qx 1000 -b 115200 /dev/ttyS6
# #echo -ne "rev\r" | picocom -qx 1000 -b 115200 /dev/ttyS6 >> /tmp/foo.txt
# #echo -ne "rev\r" | picocom -qx 1000 -b 115200 /dev/ttyS6
# #echo
# echo -ne "pcieportprop\r" | picocom -qx 1000 -b 115200 /dev/ttyS6
# echo
# #echo -ne "pciehostview\r" | picocom -qx 1000 -b 115200 /dev/ttyS6
# #echo

#############################################
# show add on card NVMe device in pcie switch
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-low 128
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-low 129
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-low 137
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-low 138
sleep 1
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-high 128
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-high 129
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-high 137
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-high 138
sleep 1
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-input 128
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-input 129
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-input 137
sshpass -p superuser ssh sysadmin@192.168.1.235 gpiotool --set-dir-input 138
sleep 1


###################################################
# After BMC AC cycle all tmp file restore to default
# copy run_picocom to BMC tmp
sshpass -p superuser scp run_picocom.sh sysadmin@192.168.1.235:/tmp/run_picocom.sh
# make run_picocom execable
sshpass -p superuser ssh sysadmin@192.168.1.235 chmod 777 /tmp/run_picocom.sh
# get PCIe switch info
sshpass -p superuser ssh sysadmin@192.168.1.235 /tmp/run_picocom.sh

#date > log.txt
#sshpass -p superuser ssh sysadmin@192.168.1.235 /tmp/run_picocom.sh >> log.txt
