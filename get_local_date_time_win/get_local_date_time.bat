@echo off


SETLOCAL ENABLEDELAYEDEXPANSION

:loop

:: 別問我下面這一段 code 怎麼寫的，我也不知道。XD
:: 來源： https://superuser.com/questions/738908/command-exe-to-obtain-date-in-iso-format
:: 但 It work!
for /F "usebackq tokens=1,2 delims==" %%i in (`wmic os get LocalDateTime /VALUE 2^>NUL`) do if '.%%i.'=='.LocalDateTime.' set ldt=%%j
set ldt=%ldt:~0,4%-%ldt:~4,2%-%ldt:~6,2% %ldt:~8,2%:%ldt:~10,2%:%ldt:~12,6%
echo Local date is [%ldt%]

ping 127.0.0.1 -n 3 > nul


goto loop

