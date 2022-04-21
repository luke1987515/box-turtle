#!/bin/bash
#for (( i=1; i<=20; i++))
# infinite loops

for (( i=1 ; ; i++ ))
do
    #date -u -Ins
    #date +%s.%N
    #get_time=$(date +%s.%N | sha256sum)
    get_time=$(echo $i | sha512sum)
    #sleep 0.992
    if echo $get_time | cut -c 1-4 | grep -q "0000"
    then
        echo "FOUND $i"
        echo $get_time
        #break
    fi
    #else
        #echo "NOTFOUND $i"
    #fi

done
