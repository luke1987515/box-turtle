@echo off
setlocal EnableDelayedExpansion

if exist on.txt del /Q on.txt
if exist off.txt del /Q off.txt
if exist on.bin del /Q on.bin
if exist off.bin del /Q off.bin

:: wmic /format:list strips trailing spaces (at least for path win32_pnpentity)
for /f "tokens=1,2,3* delims==" %%I in ('wmic path win32_pnpentity get caption /format:list ^| find "CH340"') do (
    ::echo "J"="%%J"
    set "CH340_caption=%%J"
    ::echo =="!CH340_caption:~0,-1!"==	
	set "str=!CH340_caption:~0,-1!"
)

echo.
echo ################
echo ################
echo %str%
echo ################
echo ################
echo.

set "num=%str:*(COM=%"
set "num=%num:)=%"
set str=%str:(COM=&rem.%

echo.
echo ################
echo ################
echo %str%^(COM%num%^)
echo ################
echo ################
echo.

echo A00101A2>on.txt
echo A00100A1>off.txt

certutil -decodehex off.txt off.bin
certutil -decodehex on.txt on.bin

MODE COM%num%:9600,n,8,1

ping 127.0.0.1 -n 2 > nul
copy off.bin \\.\com%num% /b
ping 127.0.0.1 -n 2 > nul

if exist on.txt del /Q on.txt
if exist off.txt del /Q off.txt
if exist on.bin del /Q on.bin
if exist off.bin del /Q off.bin

::PAUSE
