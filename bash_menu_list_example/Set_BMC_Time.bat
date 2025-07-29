::[Bat To Exe Converter]
::
::YAwzoRdxOk+EWAnk
::fBw5plQjdG8=
::YAwzuBVtJxjWCl3EqQJgSA==
::ZR4luwNxJguZRRnk
::Yhs/ulQjdF+5
::cxAkpRVqdFKZSDk=
::cBs/ulQjdF+5
::ZR41oxFsdFKZSDk=
::eBoioBt6dFKZSDk=
::cRo6pxp7LAbNWATEpCI=
::egkzugNsPRvcWATEpCI=
::dAsiuh18IRvcCxnZtBJQ
::cRYluBh/LU+EWAnk
::YxY4rhs+aU+JeA==
::cxY6rQJ7JhzQF1fEqQJQ
::ZQ05rAF9IBncCkqN+0xwdVs0
::ZQ05rAF9IAHYFVzEqQJQ
::eg0/rx1wNQPfEVWB+kM9LVsJDGQ=
::fBEirQZwNQPfEVWB+kM9LVsJDGQ=
::cRolqwZ3JBvQF1fEqQJQ
::dhA7uBVwLU+EWDk=
::YQ03rBFzNR3SWATElA==
::dhAmsQZ3MwfNWATElA==
::ZQ0/vhVqMQ3MEVWAtB9wSA==
::Zg8zqx1/OA3MEVWAtB9wSA==
::dhA7pRFwIByZRRnk
::Zh4grVQjdCyDJGyX8VAjFDpQQQ2MNXiuFLQI5/rHy++UqVkSRN4ZTLDv36eaH/MQ+Ez0YYUR+m9Rnfc/CQ9nXD+IUTs9pGt+hWGRCOWxkDDVQ0WMqE4oHgU=
::YB416Ek+ZG8=
::
::
::978f952a14a936cc963da21a135fa983
@echo off
setlocal enabledelayedexpansion

rem Set BMC information
set BMC_IP=192.168.11.11
set BMC_USER=admin
set BMC_PASS=admin123

rem Check if ipmitool is installed
where ipmitool >nul 2>nul
if %errorlevel% neq 0 (
    echo ERROR: ipmitool not found. Please install it first!
    exit /b 1
)

rem Get current time from BMC
echo Retrieving current BMC time...
ipmitool.exe -I lanplus -H %BMC_IP% -U %BMC_USER% -P %BMC_PASS% sel time get > bmc_time.txt 2>nul

rem Read BMC time from file
set /p BMC_TIME=<bmc_time.txt
del bmc_time.txt

rem Display BMC time
echo Current BMC time: %BMC_TIME%

rem Get accurate UTC time using PowerShell
for /f "delims=" %%I in ('powershell -command "$date = Get-Date; $date.ToUniversalTime().ToString('MM\/dd\/yyyy HH:mm:ss')"') do set current_datetime=%%I

echo Current UTC date and time: %current_datetime%

rem Extract BMC date and time components
for /f "tokens=1,2,3 delims=/ " %%a in ("%BMC_TIME%") do (
    set BMC_MM=%%a
    set BMC_DD=%%b
    set BMC_YYYY=%%c
)
for /f "tokens=1,2,3 delims=: " %%a in ("%BMC_TIME%") do (
    set BMC_HH=%%a
    set BMC_MIN=%%b
    set BMC_SEC=%%c
)

rem Extract UTC date and time components
for /f "tokens=1,2,3 delims=/ " %%a in ("%current_datetime%") do (
    set UTC_MM=%%a
    set UTC_DD=%%b
    set UTC_YYYY=%%c
)
for /f "tokens=1,2,3 delims=: " %%a in ("%current_datetime%") do (
    set UTC_HH=%%a
    set UTC_MIN=%%b
    set UTC_SEC=%%c
)

rem Convert BMC and UTC time to total seconds
set /a BMC_TOTAL_SEC=(BMC_YYYY * 31536000) + (BMC_MM * 2592000) + (BMC_DD * 86400) + (BMC_HH * 3600) + (BMC_MIN * 60) + BMC_SEC
set /a UTC_TOTAL_SEC=(UTC_YYYY * 31536000) + (UTC_MM * 2592000) + (UTC_DD * 86400) + (UTC_HH * 3600) + (UTC_MIN * 60) + UTC_SEC
set /a TIME_DIFF=%UTC_TOTAL_SEC% - %BMC_TOTAL_SEC%

rem Display time difference
if %TIME_DIFF% equ 0 (
    echo BMC time is synchronized with UTC.
) else (
    echo Time difference between BMC and UTC: %TIME_DIFF% seconds.
)

rem Ask the user if they want to update BMC time (with 5-second timeout)
echo Do you want to update BMC time? (Y/N) Default: No
choice /C YN /T 5 /D N /N
set USER_RESPONSE=%ERRORLEVEL%

rem Process user choice
if %USER_RESPONSE% equ 1 (
    echo Updating BMC time...
    ipmitool.exe -I lanplus -H %BMC_IP% -U %BMC_USER% -P %BMC_PASS% sel time set "%current_datetime%"

    rem Check execution result
    if %errorlevel% equ 0 (
        echo BMC time set successfully!
    ) else (
        echo Failed to set BMC time!
        exit /b 1
    )
) else (
    echo BMC time update canceled. Exiting...
    exit /b 0
)
