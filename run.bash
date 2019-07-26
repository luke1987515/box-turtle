# !/bin/bash
# Log JBOF Nvme SSD number
#
# 2019-07-22 12:00:00 Add 300 loop & Date_Time Info
# 2019-07-22 10:04:59 luke.chen

IP=192.168.0.41

if [ "$1" == "" ]
then
  echo You forget input IP "(use defult 192.168.0.41 )"
else
  IP=192.168.$1
fi

sleep_time=3

Start_DAY=$(date +"%Y-%m-%d_%H%M%S")
echo "" > log_$Start_DAY.txt



###
# Save First Log File(base.txt)
###

file="base.txt"
if [ -f "$file" ]
then
  echo base.txt is EXIST !!! 
else
  # sleep
  sleep $sleep_time
  
  TODAY=$(date +"%H:%M:%S %d/%m/%Y")

  echo NO. 000 $TODAY | tee -a log_$Start_DAY.txt
  ./plink -no-antispoof -l root $IP lspci | grep No | tee -a log_$Start_DAY.txt base.txt
    
  # sleep
  sleep $sleep_time
fi

###
# Loop 300 times
###

for Run_count in $(seq -f "%03g" 1 300)
do
  # sleep
  sleep $sleep_time
    
  ./plink -no-antispoof -l root $IP lspci | grep No > $Run_count.txt
  
  TODAY=$(date +"%H:%M:%S %d/%m/%Y")
  
  DIFF=$(diff base.txt $Run_count.txt)

  if [ "$DIFF" != "" ]
  then
    echo NO. $Run_count "FAIL" $TODAY | tee -a log_$Start_DAY.txt
  else
    echo NO. $Run_count "PASS" $TODAY | tee -a log_$Start_DAY.txt
  fi
  
  cat $Run_count.txt | tee -a log_$Start_DAY.txt
  
  # sleep
  sleep $sleep_time

done

