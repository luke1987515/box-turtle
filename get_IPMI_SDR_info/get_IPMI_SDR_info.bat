:: get_IPMI_SDR_info.bat
:: get_IPMI_SDR_info
:: 
:: Auther: luke.chen@aicipc.com.tw
:: Progream: get_IPMI_SDR_info every 10 sec
:: Lincese: CC0
:: History: 2021-07-20T13:34:04 
:: note: init

@ECHO OFF

:: Get Date & Time 
set hh=%time:~0,2%
if "%time:~0,1%"==" " set hh=0%hh:~1,1%
set day=%date:~10,4%-%date:~4,2%-%date:~7,2%
set dayHM=%day%_%hh%%time:~3,2%

:: Remove old log
:: del /Q log_*.txt

:: Set parameter
set ipaddr=192.168.11.11
set sleeptime=3
set /a count=0

:: Get user parameter 
if not "%1" == "" set ipaddr=%1
if not "%2" == "" set sleeptime=%2

:: Set log file name
set logname=log_%ipaddr%_%dayHM%.txt

:: Create log
echo. > %logname%

:loop

    :: count add one
    set /a count+=1

    :: Get Date & Time 
    set hh=%time:~0,2%
    if "%time:~0,1%"==" " set hh=0%hh:~1,1%
    set day=%date:~10,4%-%date:~4,2%-%date:~7,2%
    set dayHMS=%day%_%hh%:%time:~3,2%:%time:~6,2%

    :: Show and log: ipaddr & count
    echo ==== %ipaddr% (%count%) ==== 
    echo ==== %ipaddr% (%count%) ==== >> %logname%

    :: Show and log: date & time
    echo %dayHMS%
    echo.
    echo %dayHMS% >> %logname%
    echo. >> %logname%

    :: Get BMC SDR 
    :: echo ipmitool -I lanplus -H %ipaddr% -U admin -P admin sdr
    ipmitool -I lanplus -H %ipaddr% -U admin -P admin sdr
    ipmitool -I lanplus -H %ipaddr% -U admin -P admin sdr >> %logname%
 
    ::
    echo.
    echo. >> %logname%

    :: Sleep %sleeptime% sec (default: 3 sec)
    ping 127.0.0.1 -w 1000 -n %sleeptime% > nul

goto loop