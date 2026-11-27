@echo off
setlocal enabledelayedexpansion
:: Scratch test: exercise only the V03 PSU fan subroutines (read-only)
:: Uses FULL ipmitool path so cwd doesn't matter.
set "it=C:\Users\Administrator\Desktop\Pegatron 2MS\ipmitool.exe"
set "bmc_ip=192.168.15.57"
set "bmc_user=admin"
set "bmc_pass=***"
set "psu_bus=0x7"
set "psu1_addr=0xB0"
set "psu2_addr=0xB2"
set "log_file=psu_fan_test_log.txt"
echo test start: %date% %time% > "%log_file%"

echo === direct raw output (diagnostic) ===
"%it%" -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% raw 0x3A 0x6A 0x0 %psu_bus% 0x1 %psu1_addr% 0x2 0x90

call :LogPSUFans

echo.
echo ===== test log content =====
type "%log_file%"
del /f /q "%log_file%"
exit /b

:LogPSUFans
echo [PSU FAN RPM]:
call :ReadPSUFan %psu1_addr% 1
call :ReadPSUFan %psu2_addr% 2
goto :eof

:ReadPSUFan
set "psu_lo="
set "psu_hi="
for /f "tokens=1,2" %%a in ('"%it%" -I lanplus -H %bmc_ip% -U %bmc_user% -P %bmc_pass% raw 0x3A 0x6A 0x0 %psu_bus% 0x1 %1 0x2 0x90 2^>nul') do (
    set "psu_lo=%%a"
    set "psu_hi=%%b"
)
if not defined psu_lo (
    echo PSU%2 Fan1: N/A (read failed^)
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
goto :eof
