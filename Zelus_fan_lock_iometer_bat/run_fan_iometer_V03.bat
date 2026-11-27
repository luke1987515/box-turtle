@echo off
setlocal enabledelayedexpansion
chcp 437 >nul

echo ========================================================
echo    SERVER FAN SPEED LOCK AND IOMETER AUTO TEST (V03)
echo ========================================================
echo.

set /p bmc_ip="Enter BMC IP (e.g. 192.168.15.114): "
set /p bmc_user="Enter BMC Username (default admin): "
set /p bmc_pass="Enter BMC Password: "

:: ========================================================
:: PSU fan OEM raw command parameters (BMC RD, 2026-11-26)
::   command: raw 0x3A 0x6A 0x0 <psu_bus> 0x1 <addr> 0x2 0x90
::   psu_bus / addr are SYSTEM-SPECIFIC (Zelus/Sophos values below).
::   For other systems, adjust these per BMC RD.
:: ========================================================
set "psu_bus=0x7"
set "psu1_addr=0xB0"
set "psu2_addr=0xB2"

set "log_file=Fan_Speed_Log.txt"
echo ======================================================== > "%log_file%"
echo Test Start Time: %date% %time% >> "%log_file%"
echo BMC IP: %bmc_ip% >> "%log_file%"
echo ======================================================== >> "%log_file%"

echo.
echo [INFO] Starting automated test sequence...
echo [INFO] Fan RPM logs will be saved to: %log_file%
echo --------------------------------------------------------

:: Run each PWM stage: lock fan speed + 4K rand write + 256K seq write
call :RunTest 20 0x14
call :RunTest 40 0x28
call :RunTest 60 0x3C
call :RunTest 64 0x40
call :RunTest 68 0x44
call :RunTest 72 0x48
call :RunTest 76 0x4C
call :RunTest 80 0x50
call :RunTest 84 0x54
call :RunTest 88 0x58
call :RunTest 92 0x5C
call :RunTest 96 0x60
call :RunTest 100 0x64

:: Restore fan speed to 60%% after all stages
echo.
echo [INFO] Restoring fan speed to 60%%...
ipmitool -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% raw 0x36 0xFA 0x00 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C 0x3C >nul 2>&1

echo ======================================================== >> "%log_file%"
echo Test End Time: %date% %time% >> "%log_file%"
echo ======================================================== >> "%log_file%"

echo.
echo ========================================================
echo ALL TESTS COMPLETED! Check %log_file% for RPM records.
echo ========================================================
pause
exit /b

:: ========================================================
:: RunTest: lock fan to PWM %1, run 4K + 256K iometer tests
:: ========================================================
:RunTest
set "pwm=%1"
set "hex=%2"

echo.
echo ========================================================
echo [STAGE] Target Fan PWM: %pwm%%% (%hex%)
echo ========================================================

:: 1. Create fan locker daemon (set fan PWM + 10s interval)
echo @echo off > _fan_locker.bat
echo :loop >> _fan_locker.bat
echo ipmitool -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% raw 0x36 0xFA 0x00 %hex% %hex% %hex% %hex% %hex% %hex% %hex% %hex% %hex% %hex% %hex% %hex% %hex% %hex% %hex% %hex% ^>nul 2^>^&1 >> _fan_locker.bat
echo timeout /t 3 /nobreak ^>nul >> _fan_locker.bat
echo goto loop >> _fan_locker.bat

:: 2. Start locker daemon
start "FAN_LOCKER_DAEMON" /min cmd /c _fan_locker.bat

:: 3. Wait 10s for fan speed to stabilize
echo [INFO] Waiting 20 seconds for fan RPM to stabilize...
timeout /t 10 /nobreak >nul

:: 4. Log chassis + PSU fans before 4K test
echo. >> "%log_file%"
echo -------------------------------------------------------- >> "%log_file%"
echo [%date% %time%] Stage: %pwm%%% (%hex%) - Before 4K Test >> "%log_file%"
ipmitool -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% sensor 2>nul | findstr /I "FAN_" >> "%log_file%"
call :LogPSUFans

echo [CURRENT FAN RPM - 4K Test]:
ipmitool -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% sensor 2>nul | findstr /I "FAN_"

:: 5. Run 4K Random Writes
echo [RUNNING] Fan: %pwm%%% - 4K Random Writes Test...
iometer.exe /c "4K_Random_Writes.icf" /r "Fan_%pwm%pct_4K_Random_Writes.csv"

:: 6. Log chassis + PSU fans before 256K test
echo [%date% %time%] Stage: %pwm%%% (%hex%) - Before 256K Test >> "%log_file%"
ipmitool -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% sensor 2>nul | findstr /I "FAN_" >> "%log_file%"
call :LogPSUFans

echo [CURRENT FAN RPM - 256K Test]:
ipmitool -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% sensor 2>nul | findstr /I "FAN_"

:: 7. Run 256K Sequential Writes Test
echo [RUNNING] Fan: %pwm%%% - 256K Sequential Writes Test...
iometer.exe /c "256K_Sequential_Writes.icf" /r "Fan_%pwm%pct_256K_Sequential_Writes.csv"

:: 8. Log chassis + PSU fans at stage complete
echo [%date% %time%] Stage: %pwm%%% (%hex%) - Stage Completed >> "%log_file%"
ipmitool -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% sensor 2>nul | findstr /I "FAN_" >> "%log_file%"
call :LogPSUFans

:: 9. Kill locker daemon
taskkill /FI "WINDOWTITLE eq FAN_LOCKER_DAEMON*" /T /F >nul 2>&1
del /f /q _fan_locker.bat >nul 2>&1

goto :eof

:: ========================================================
:: V03 addition: log PSU fan speed via OEM raw command
::   (method provided by BMC RD, 2026-11-26)
::   ipmitool raw 0x3A 0x6A 0x0 <psu_bus> 0x1 <addr> 0x2 0x90
::   addr: psu1_addr / psu2_addr (see top of script)
::   reply: <lo> <hi>  ->  val = hi*256 + lo
::   RPM   = 2^(upper 5 bits of val) * (lower 11 bits)
:: ========================================================
:LogPSUFans
echo [PSU FAN RPM]:
call :ReadPSUFan %psu1_addr% 1
call :ReadPSUFan %psu2_addr% 2
goto :eof

:ReadPSUFan
:: %1 = PSU I2C address (0xB0/0xB2), %2 = PSU slot number
set "psu_lo="
set "psu_hi="
for /f "tokens=1,2" %%a in ('ipmitool -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% raw 0x3A 0x6A 0x0 %psu_bus% 0x1 %1 0x2 0x90 2^>nul') do (
    set "psu_lo=%%a"
    set "psu_hi=%%b"
)
if not defined psu_lo (
    echo PSU%2 Fan1: N/A (read failed^)
    echo PSU%2 Fan1: N/A (read failed^) >> "%log_file%"
    goto :eof
)
set /a psu_lo_v=0x%psu_lo%
set /a psu_hi_v=0x%psu_hi%
set /a psu_val=psu_hi_v*256+psu_lo_v
set /a psu_exp=psu_val/2048
set /a psu_mult=psu_val-psu_exp*2048
set /a psu_pow=1
set /a psu_i=0
:psu_powloop
if !psu_i! lss !psu_exp! (
    set /a psu_pow*=2
    set /a psu_i+=1
    goto psu_powloop
)
set /a psu_rpm=psu_mult*psu_pow
echo PSU%2 Fan1: %psu_rpm% RPM (raw %psu_lo% %psu_hi%)
echo PSU%2 Fan1: %psu_rpm% RPM (raw %psu_lo% %psu_hi%) >> "%log_file%"
goto :eof
