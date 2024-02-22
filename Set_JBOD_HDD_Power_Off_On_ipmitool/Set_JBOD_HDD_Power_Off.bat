@echo off
:: for Set JBOD HDD Power Off form ipmitool
:: raw 0x3c 0x32 slot_num  action(0:off, 1:on)
:: 作者： luke.chen luke.chen@aicipc.com.tw


set BMC_Password=admin123
set BMC_IP=192.168.11.11
set slot_num=12

:: 取得 JBOD 的 slot 數
:: 參考 BMC Release Note (ReleaseNote_JBOD_4U60_BMC.pdf)
:: 1.2. IPMI OEM Command
:: 1.2.1. Get HDD Status (NetFn: 0x3C, Command: 0x31)
echo ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% raw 0x3C 0x31 

ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% raw 0x3C 0x31 > HDD_status.txt 

echo Show HDD status ( raw 0x3C 0x31 ^)
echo ------------------------------------------------
type HDD_status.txt
echo ------------------------------------------------

:: 別問我下面這一段 code 怎麼寫的，我也不知道。XD
:: 來源： https://superuser.com/questions/939838/how-do-i-count-all-occurrences-of-a-particular-string-in-a-file-using-a-batch-fi
:: 但 It work!
:: 是為了計算 (raw 0x3C 0x31) 中顯示幾個 01

:: setlocal
SETLOCAL ENABLEDELAYEDEXPANSION
set _count=0
set _match=01
set _file=HDD_status.txt

for /f "tokens=*" %%i in (%_file%) do (
  set _line=%%i
  call :match
  )
 goto :done
  
:match
  for /f "tokens=1,*" %%a in ("%_line%") do (
    set _word=%%a
    set _line=%%b
  )
  if /i "%_word%"=="%_match%" set /a _count=!_count!+1
  if "%_line%"=="" goto :eof
goto :match

:done
echo."01" was found !_count! times.

:: endlocal

:: 神奇的 code 結束了。XP

set slot_num=!_count!

echo %slot_num%

if "%slot_num%"=="0" (echo "No Power ON slot, Do notting"

:: 如果想覆蓋透過 (raw 0x3C 0x31) 取得的數量
:: 直接改下面的數字就可以了，
:: 這樣就可以連續執行 1 ~ 你所設定的數量。
REM set slot_num=60

REM echo %slot_num%

set BMC_Password=admin123
set BMC_IP=192.168.11.11

:: 
:: Set JBOD HDD Power action
:: raw 0x3c 0x32 slot_num  action(0:off, 1:on)
:: ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% raw 0x3C 0x32 1 0

:: 使用迴圈關閉所有 HDD Power
for /L %%i in (1 1 %slot_num%) do (

    echo =================================
	echo %%i / %slot_num% --- Power off slot %%i HDD
	echo =================================
	echo ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% raw 0x3C 0x32 %%i 0
	ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% raw 0x3C 0x32 %%i 0
    echo wait 3 sec...
	ping 127.0.0.1 -n 4 > nul

	echo.
	echo Show HDD status ( raw 0x3C 0x31 ^)
	echo ------------------------------------------------
	ipmitool.exe -I lanplus -H %BMC_IP% -U admin -P %BMC_Password% raw 0x3C 0x31
	echo ------------------------------------------------
	ping 127.0.0.1 -n 2 > nul
	echo.
	echo.
)

del /f HDD_status.txt
