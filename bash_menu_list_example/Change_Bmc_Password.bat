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
::Zh4grVQjdCyDJGyX8VAjFDpQQQ2MNXiuFLQI5/rHy++UqVkSRN4ZTLDv36eaH/MQ+Ez0YYUR+m9RnfcPBBpWeReUbAI3ln5DpXeSONWYjwzpS0aO43QyFmZLl2LDnzw0ctcmn9sGsw==
::YB416Ek+ZG8=
::
::
::978f952a14a936cc963da21a135fa983
@echo off
setlocal

REM Default IP and credentials
set BMC_IP=192.168.11.11
set DEFAULT_USER=admin
set DEFAULT_PASS=admin
set NEW_PASS=admin123

REM Function: Check if BMC is reachable
ping -n 2 -w 1000 %BMC_IP% >nul
if %errorlevel% neq 0 (
    echo Device is not reachable.
    goto end
)

echo Device is reachable. Checking password status...

REM Try default password
ipmitool.exe -I lanplus -H %BMC_IP% -U %DEFAULT_USER% -P %DEFAULT_PASS% mc info >nul 2>&1
if %errorlevel% equ 0 (
    echo Current password is the default admin
    set /p response=Do you want to change it to "admin123"? (y/n)
    if /I "%response%"=="y" (
        ipmitool.exe -I lanplus -H %BMC_IP% -U %DEFAULT_USER% -P %DEFAULT_PASS% user set password 2 %NEW_PASS%
        echo Password has been changed to "admin123".
    ) else (
        echo Password change skipped.
    )
) else (
    REM Try common password admin123
    ipmitool.exe -I lanplus -H %BMC_IP% -U %DEFAULT_USER% -P %NEW_PASS% mc info >nul 2>&1
    if %errorlevel% equ 0 (
        echo Current password is "admin123".
    ) else (
        echo Password is neither "admin" nor "admin123".
    )
)

:end
endlocal

