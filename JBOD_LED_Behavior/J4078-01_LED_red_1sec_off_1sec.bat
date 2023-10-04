:: For J4078-01
:: Test JBOD LED Behavior
::
:: 2020-08-04T13:39:55

@echo off

set enclosure_ID=SCSI3:6,16,0
:: set enclosure_ID=SCSI3:6,16,0
set list=3:5:1

:loop

for %%a in (%list%) do (

:: Set LED status on
::
    for /l %%x in (1, 1, 9) do (
        echo sg_ses.exe --descriptor=Disk00%%x --set=%%a %enclosure_ID%
        sg_ses.exe --descriptor=Disk00%%x --set=%%a %enclosure_ID%
		ping 127.0.0.1 -n 3 > nul
		sg_ses.exe %enclosure_ID% --descriptor=Disk0%%x
    )
    for /l %%x in (10, 1, 78) do (
        echo sg_ses.exe --descriptor=Disk0%%x --set=%%a %enclosure_ID%
        sg_ses.exe --descriptor=Disk0%%x --set=%%a %enclosure_ID%
		ping 127.0.0.1 -n 3 > nul
		sg_ses.exe %enclosure_ID% --descriptor=Disk0%%x
    )
:: Sleep 1 sec
    ping 127.0.0.1 -n 3 > nul

:: Set LED status off
::
    for /l %%x in (1, 1, 9) do (
        echo sg_ses.exe --descriptor=Disk00%%x --clear=%%a %enclosure_ID%
        sg_ses.exe --descriptor=Disk00%%x --clear=%%a %enclosure_ID%
		ping 127.0.0.1 -n 3 > nul
		sg_ses.exe %enclosure_ID% --descriptor=Disk0%%x
    )
    for /l %%x in (10, 1, 78) do (
        echo sg_ses.exe --descriptor=Disk0%%x --clear=%%a %enclosure_ID%
        sg_ses.exe --descriptor=Disk0%%x --clear=%%a %enclosure_ID%
		ping 127.0.0.1 -n 3 > nul
		sg_ses.exe %enclosure_ID% --descriptor=Disk0%%x
    )

:: Sleep 1 sec
    ping 127.0.0.1 -n 3 > nul
)

goto loop

:: Array Device Slot control element
:: set list=1:7:1 1:6:1 1:5:1 1:4:1 1:3:1 1:2:1 1:1:1 1:0:1 2:7:1 2:6:1 2:4:1 2:3:1 2:2:1 2:1:1 3:5:1 3:4:1 0:6:1

:: set list=1:7:1 (RQST OK)               Blue LED: Activity      Red LED: OFF
:: set list=1:6:1 (RQST RSVD DEVICE)      Blue LED: Activity      Red LED: OFF
:: set list=1:5:1 (RQST HOT SPARE)        Blue LED: Activity      Red LED: OFF
:: set list=1:4:1 (RQST CONS CHECK)       Blue LED: Activity      Red LED: Fast Blink
:: set list=1:3:1 (RQST IN CRIT ARRAY)    Blue LED: Activity      Red LED: Slow Blink
:: set list=1:2:1 (RQST IN FAILED ARRAY)  Blue LED: Activity      Red LED: Slow Blink
:: set list=1:1:1 (RQST REBULD/REMAP)     Blue LED: Activity      Red LED: Fast Blink
:: set list=1:0:1 (RQST R/R ABORT)        Blue LED: Activity      Red LED: Slow Blink
:: set list=2:7:1 (RQST ACTIVE)           Blue LED: Activity      Red LED: OFF
:: set list=2:6:1 (DO NOT REMOVE)         Blue LED: Activity      Red LED: OFF
:: set list=2:4:1 (RQST MISSING)          Blue LED: ON            Red LED: ON
:: set list=2:3:1 (RQST INSERT)           Blue LED: Activity      Red LED: Slow Blink
:: set list=2:2:1 (RQST REMOVE)           Blue LED: Activity      Red LED: Slow Blink
:: set list=2:1:1 (RQST IDENT)            Blue LED: Slow Blink    Red LED: OFF
:: set list=3:5:1 (RQST FAULT)            Blue LED: ON            Red LED: ON 
:: set list=3:4:1 (DEVICE OFF)            Blue LED: OFF           Red LED: OFF
:: set list=0:6:1 (PRDFAIL)               Blue LED: Activity      Red LED: Slow Blink
