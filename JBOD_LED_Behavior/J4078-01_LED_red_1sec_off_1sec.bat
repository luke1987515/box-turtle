:: For J4078-01
:: Test JBOD LED Behavior
::
:: 2020-08-04T13:39:55

@echo off

set enclosure_ID=SCSI3:6,16,0
set list=3:5:1

:loop

for %%a in (%list%) do (

:: Set LED status on
::
    for /l %%x in (1, 1, 9) do (
        echo sg_ses.exe --descriptor=Disk00%%x --set=%%a %enclosure_ID%
        sg_ses.exe --descriptor=Disk00%%x --set=%%a %enclosure_ID%
    )
    for /l %%x in (10, 1, 78) do (
        echo sg_ses.exe --descriptor=Disk0%%x --set=%%a %enclosure_ID%
        sg_ses.exe --descriptor=Disk0%%x --set=%%a %enclosure_ID% 
    )
:: Sleep 1 sec
    ping 127.0.0.1 -n 1 > nul

:: Set LED status off
::
    for /l %%x in (1, 1, 9) do (
         echo sg_ses.exe --descriptor=Disk00%%x --clear=%%a %enclosure_ID%
         sg_ses.exe --descriptor=Disk00%%x --clear=%%a %enclosure_ID%
    )
    for /l %%x in (10, 1, 78) do (
        echo sg_ses.exe --descriptor=Disk0%%x --clear=%%a %enclosure_ID%
        sg_ses.exe --descriptor=Disk0%%x --clear=%%a %enclosure_ID%
    )

:: Sleep 1 sec
    ping 127.0.0.1 -n 1 > nul
)

goto loop

:: Array Device Slot control element
:: set list=1:7:1 1:6:1 1:5:1 1:4:1 1:3:1 1:2:1 1:1:1 1:0:1 2:7:1 2:6:1 2:4:1 2:3:1 2:2:1 2:1:1 3:5:1 3:4:1

:: set list=1:7:1 (RQST OK)
:: set list=1:6:1 (RQST RSVD DEVICE)
:: set list=1:5:1 (RQST HOT SPARE)
:: set list=1:4:1 (RQST CONS CHECK)
:: set list=1:3:1 (RQST IN CRIT ARRAY)
:: set list=1:2:1 (RQST IN FAILED ARRAY)
:: set list=1:1:1 (RQST REBULD/REMAP)
:: set list=1:0:1 (RQST R/R ABORT)
:: set list=2:7:1 (RQST ACTIVE)
:: set list=2:6:1 (DO NOT REMOVE)
:: set list=2:4:1 (RQST MISSING)
:: set list=2:3:1 (RQST INSERT)
:: set list=2:2:1 (RQST REMOVE)
:: set list=2:1:1 (RQST IDENT)
:: set list=3:5:1 (RQST FAULT)
:: set list=3:4:1 (DEVICE OFF)