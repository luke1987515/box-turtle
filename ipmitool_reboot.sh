#!/bin/bash

BMC_ipaddress=192.168.19.218
BMC_username=jdroot
BMC_password=5t^Y7u*I

i=0
while [ 0==0 ]
do

i=$(($i+1))

echo -e "ipmitool_reboot_&_info Number ($i)"

echo -e "<======== ipmitool sel time get ========>"
ipmitool -H $BMC_ipaddress -U $BMC_username -P $BMC_password -I lanplus sel time get
echo -e "</======= ipmitool sel time get ========>\n"
sleep 1

echo -e "<======== ipmitool mc info =============>"
ipmitool -H $BMC_ipaddress -U $BMC_username -P $BMC_password -I lanplus mc info
echo -e "</======= ipmitool mc info =============>\n"
sleep 1

echo -e "<======== ipmitool fru  ================>"
ipmitool -H $BMC_ipaddress -U $BMC_username -P $BMC_password -I lanplus fru
echo -e "</======= ipmitool fru  ================>\n"
sleep 1

echo -e "<======== ipmitool sel list ============>"
ipmitool -H $BMC_ipaddress -U $BMC_username -P $BMC_password -I lanplus sel list
echo -e "</======= ipmitool sel list ============>\n"
sleep 1

echo -e "<======== ipmitool power status ========>"
ipmitool -H $BMC_ipaddress -U $BMC_username -P $BMC_password -I lanplus power status
echo -e "</======= ipmitool power status ========>\n"
sleep 1

echo -e "<======== ipmitool power reset =========>"
ipmitool -H $BMC_ipaddress -U $BMC_username -P $BMC_password -I lanplus power reset
echo -e "Sleep 300sec"
echo -e "</======= ipmitool power reset =========>\n"
sleep 1

echo -e "ipmitool_reboot_&_info Number ($i)"
sleep 300

done
