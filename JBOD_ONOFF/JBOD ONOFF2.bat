@echo off

if exist error.log del /Q error.log

set /p var=Test cycle (300):
set /p IP_PRI=IP_PRI addr(192.168.11.50):
set /p IP_SEC=IP_SEC addr(192.168.11.51):
set /p timeout_First=Set First Sleep time(43200sec):
set /p timeout_ON=Set AC ON time(120sec):
set /p timeout_OFF=Set AC OFF time(60sec):

if "%var%"=="" set var=300
if "%IP_PRI%"=="" set IP_PRI=192.168.11.50
if "%IP_SEC%"=="" set IP_SEC=192.168.11.51
if "%timeout_First%"=="" set timeout=43200
if "%timeout_ON%"=="" set timeout_ON=120
if "%timeout_OFF%"=="" set timeout_OFF=60

echo.
echo =============
echo Test cycle : %var%
echo IP_PRI addr: %IP_PRI%
echo IP_SEC addr: %IP_SEC%
echo Set First Sleep time: %timeout_First% sec
echo Set AC ON time : %timeout_ON% sec
echo Set AC OFF time :%timeout_OFF% sec
echo =============

ping 127.0.0.1 -n 5 -w 1000 > nul

set count=0
:: ===== First Log =====
:: ===== AC_ON =====
call "C:\Users\Administrator\Desktop\JBOD ONOFF\LCUS-1_CH340T_USB_powered_relay\on.bat"
ping 127.0.0.1 -n 2 -w 1000 > nul
call "C:\Users\Administrator\Desktop\JBOD ONOFF\LCUS-1_CH340T_USB_powered_relay\on.bat"
ping 127.0.0.1 -n 2 -w 1000 > nul
:: ===== AC_ON =====

:: ===== Wait 120sec =====
cls
echo Testing cycle %count% / %var%
echo Power ON ing....
echo Wait 120 sec to do AC ON then get First Log(logfile_PRI_0.txt,logfile_SEC_0.txt)
timeout /t 120
:: ===== Get First Log(logfile0.txt) =====
::diskpart /s HDD.txt > logfile0.txt

"C:\Users\Administrator\Desktop\JBOD ONOFF\putty\PLINK.EXE" -batch -ssh %IP_PRI% -l administrator -pw `1q "echo list disk > list_disk.txt && diskpart /s list_disk.txt && del list_disk.txt" > logfile_PRI_0.txt
ping 127.0.0.1 -n 2 -w 1000 > nul
"C:\Users\Administrator\Desktop\JBOD ONOFF\putty\PLINK.EXE" -batch -ssh %IP_SEC% -l administrator -pw `1q "echo list disk > list_disk.txt && diskpart /s list_disk.txt && del list_disk.txt" > logfile_SEC_0.txt
ping 127.0.0.1 -n 2 -w 1000 > nul
:: ===== AC_OFF =====
call "C:\Users\Administrator\Desktop\JBOD ONOFF\LCUS-1_CH340T_USB_powered_relay\off.bat"
ping 127.0.0.1 -n 2 -w 1000 > nul
call "C:\Users\Administrator\Desktop\JBOD ONOFF\LCUS-1_CH340T_USB_powered_relay\off.bat"
ping 127.0.0.1 -n 2 -w 1000 > nul
:: ===== AC_OFF =====

:: ===== Wait 60sec =====
cls
echo Testing cycle %count% / %var%
echo Power OFF ing....
echo Wait 60 sec to do AC OFF after get First Log(logfile_PRI_0.txt,logfile_SEC_0.txt)
timeout /t 120

:: ===== AC_OFF sleep 12Hr =====
cls
echo Testing cycle %count%
echo AC_OFF sleep %timeout_First% sec 
set count=0
echo Wait 43200 sec to do AC on/off test
timeout /t %timeout_First%

:Again
set /a count=count+1
echo Testing cycle %count% / %var%
echo Wait 120 sec to Recording
call "C:\Users\Administrator\Desktop\JBOD ONOFF\LCUS-1_CH340T_USB_powered_relay\on.bat"
ping 127.0.0.1 -n 2 -w 1000 > nul
call "C:\Users\Administrator\Desktop\JBOD ONOFF\LCUS-1_CH340T_USB_powered_relay\on.bat"
ping 127.0.0.1 -n 2 -w 1000 > nul
cls
echo Testing cycle %count% / %var%
echo Power ON ing....
echo Wait 120 sec to Recording
timeout /t %timeout_ON%

echo Get %IP_PRI% logfile_PRI_%count%
::start "" /min "Reading BMC.bat"
::diskpart /s HDD.txt > logfile%count%.txt
"C:\Users\Administrator\Desktop\JBOD ONOFF\putty\PLINK.EXE" -batch -ssh %IP_PRI% -l administrator -pw `1q "echo list disk > list_disk.txt && diskpart /s list_disk.txt && del list_disk.txt" > logfile_PRI_%count%.txt
ping 127.0.0.1 -n 3 -w 1000 > nul

echo Get %IP_SEC% logfile_SEC_%count%
"C:\Users\Administrator\Desktop\JBOD ONOFF\putty\PLINK.EXE" -batch -ssh %IP_SEC% -l administrator -pw `1q "echo list disk > list_disk.txt && diskpart /s list_disk.txt && del list_disk.txt" > logfile_SEC_%count%.txt
ping 127.0.0.1 -n 3 -w 1000 > nul

fc logfile_PRI_0.txt logfile_PRI_%count%.txt > nul
if errorlevel 1 goto error

ping 127.0.0.1 -n 2 -w 1000 > nul

fc logfile_SEC_0.txt logfile_SEC_%count%.txt > nul
if errorlevel 1 goto error

echo Power cycle "PASS"

echo Wait 60 Sec to Power off
echo Wait 60 Sec to Power cycling 
call "C:\Users\Administrator\Desktop\JBOD ONOFF\LCUS-1_CH340T_USB_powered_relay\off.bat"
ping 127.0.0.1 -n 2 -w 1000 > nul
call "C:\Users\Administrator\Desktop\JBOD ONOFF\LCUS-1_CH340T_USB_powered_relay\off.bat"
cls
echo.
echo ################
echo ################
echo Testing cycle %count% / %var%
echo Power cycle "PASS"
echo ################
echo Wait 60 sec Power OFF ing....
echo %count% / %var%
echo ################
echo.
timeout /t %timeout_OFF%
if not "%count%"=="%var%" goto Again

goto end

:error
echo Power cycle failed , Pls check
echo I get Error in %count%
echo I get Error in %count% > error.log
goto Again

:end
echo.
echo ################
echo ################
echo Test Finish
echo ################
echo ################
echo.
pause
