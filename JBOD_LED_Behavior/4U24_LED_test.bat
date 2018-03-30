:: For 4U24
:: Test JBOD LED Behavior
::
:: 2018-03-30 13:13:55

@echo off

set enclosure_ID=SCSI2:1,31,0
set list=1:7:1 1:6:1 1:5:1 1:4:1 1:3:1 1:2:1 1:1:1 1:0:1 2:7:1 2:6:1 2:4:1 2:3:1 2:2:1 2:1:1 3:5:1 3:4:1

for %%a in (%list%) do (
   echo %%a
for /l %%x in (1, 1, 9) do (
    echo sg_ses.exe --descriptor=Disk00%%x --set=%%a %enclosure_ID%
    sg_ses.exe --descriptor=Disk00%%x --set=%%a SCSI2:1,31,0

    :: Sleep 1 sec
    ping 127.0.0.1 -n 2 > nul
)
for /l %%x in (10, 1, 24) do (
    :: echo %%x
    echo sg_ses.exe --descriptor=Disk0%%x --set=%%a %enclosure_ID%
    sg_ses.exe --descriptor=Disk0%%x --set=%%a SCSI2:1,31,0
    
    :: Sleep 1 sec
    ping 127.0.0.1 -n 2 > nul
)
for /l %%x in (1, 1, 9) do (
    echo sg_ses.exe --descriptor=Disk00%%x --clear=%%a %enclosure_ID%
    sg_ses.exe --descriptor=Disk00%%x --clear=%%a SCSI2:1,31,0

    :: Sleep 1 sec
    ping 127.0.0.1 -n 2 > nul
)
for /l %%x in (10, 1, 24) do (
    :: echo %%x
    echo sg_ses.exe --descriptor=Disk0%%x --clear=%%a %enclosure_ID%
    sg_ses.exe --descriptor=Disk0%%x --clear=%%a SCSI2:1,31,0
    
    :: Sleep 1 sec
    ping 127.0.0.1 -n 2 > nul
)
)

