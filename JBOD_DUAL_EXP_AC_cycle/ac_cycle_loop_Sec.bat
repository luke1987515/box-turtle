@echo off

setlocal EnableDelayedExpansion

echo ################
echo JBOD AC Cycle Tool
echo ################
echo.

set /a count=1

:while
echo Power ON
call on.bat > nul
 
if %count% lss 301 (
    :scan 
     sg_scan.exe -s > sg_scan_info.txt
    findstr /C:"AIC" sg_scan_info.txt > AIC_info.txt
    for /f %%i in ("AIC_info.txt") do set size=%%~zi
    if !size! gtr 0 (
        echo JBOD is ON
       echo Wait 90 sec to record UUT information
        timeout /t 90
        echo count=%count%
        echo ======count_%count%======= >>log.txt
        diskpart /s list_disk.txt >>log.txt
        
    ) else ( 
        echo Wait Expander Power on
        timeout /t 1
        goto :scan
    ) 
set /a count+=1
echo Power OFF
echo Wait 60 sec to Power on
call off.bat > nul
timeout /t 60
goto :while
)