@echo off
:: Set JBOD AC Power On or Off with LCUS-1_CH340T_USB_powered_relay 
:: https://github.com/luke1987515/box-turtle/tree/master/LCUS-1_CH340T_USB_powered_relay
:: 作者： luke.chen luke.chen@aicipc.com.tw

:: 整個過程
:: 初始化 
:: 1. JBOD Power ON
:: 2. Set JBOD BMC "Power Restore Policy" is "Always-off" -> "Always-on"
:: 2. Clear SEL elist (sel clear)
:: 3. JBOD Power off
:: 循環節
:: 1. LCUS-1_CH340T_USB_powered_relay : on
:: 2. Wait 120 sec JBOD ready (ping 127.0.0.1 -n 121 > nul) 
:: 3. Get SEL elist (sel elist)
:: 4. Log SEL elist (with time and count)
:: 5. Clear SEL elist (sel clear)
:: 6. LCUS-1_CH340T_USB_powered_relay : off
:: 7. Wait 30 sec JBOD AC off

SETLOCAL ENABLEDELAYEDEXPANSION

:: 設定 IPMI 相關 
set BMC_Password=admin123
set BMC_IP=192.168.11.11

:: 設定 Log 檔名
set Log_File_Name=AC_Log

:: 計數
set _count=0


:: 循環節

:loop

:: 00_設定(紀錄)時間
:: 別問我下面這一段 code 怎麼寫的，我也不知道。XD
:: 來源： https://superuser.com/questions/738908/command-exe-to-obtain-date-in-iso-format
:: 但 It work!
for /F "usebackq tokens=1,2 delims==" %%i in (`wmic os get LocalDateTime /VALUE 2^>NUL`) do if '.%%i.'=='.LocalDateTime.' set ldt=%%j
set ldt=%ldt:~0,4%-%ldt:~4,2%-%ldt:~6,2%T%ldt:~8,2%:%ldt:~10,2%:%ldt:~12,2%
echo Local date is [%ldt%]

:: 1. LCUS-1_CH340T_USB_powered_relay : on
call CH340T_AC_on.bat

:: 2. Wait 120 sec JBOD ready (ping 127.0.0.1 -n 121 > nul) 
echo Wait 120 sec JBOD ready
ping 127.0.0.1 -n 121 > nul

:: 3. Get SEL elist (sel elist)
echo ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% sel elist
ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% sel elist

:: 4. Log SEL elist (with time and count)
echo =====================  >> %Log_File_Name%.txt
echo %ldt% ___ !_count! >> %Log_File_Name%.txt
echo =====================  >> %Log_File_Name%.txt
echo ----- SEL elist -----  >> %Log_File_Name%.txt
ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% sel elist >> %Log_File_Name%.txt
echo ---------------------  >> %Log_File_Name%.txt

:: 5. Clear SEL elist (sel clear)
echo ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% sel clear
ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% sel clear

:: 6. LCUS-1_CH340T_USB_powered_relay : off
call CH340T_AC_off.bat

:: 7. Wait 30 sec JBOD AC off
ping 127.0.0.1 -n 30 > nul

:: count + 1
set /a _count=!_count!+1

goto loop
