#!/bin/bash

if [ $(whoami) = "root" ]; then
    echo "當前使用者是 root 使用者"
else
    echo "當前使用者不是 root 使用者"
fi


# ./g4Xdiagnostics.x86_64 --list | grep 500 | cut -d ":"  -f 1 | rev | cut -c -8 | rev


# ./g4Xdiagnostics.x86_64 --list | grep 50015b | cut -c 26-42

SASaddr=($(./g4Xdiagnostics.x86_64 --list | grep 50015b | cut -c 26-42))

for addr in "${SASaddr[@]}"
do
    echo "$addr"
    WWID=$(echo "$addr" | sed 's/://g')
    ./g4Xdiagnostics.x86_64 -wwid $WWID show
    ./g4Xdiagnostics.x86_64 -wwid $WWID cli counters reset
    ./g4Xdiagnostics.x86_64 -wwid $WWID cli counters | tee counters_$WWID.log

done
