@echo off
::sg_scan -s to Show the device for AIC Expander Controller 

set /p Set=Input (1:Enable 2:Disable):

if "%Set%"=="1" goto A
if "%Set%"=="2" goto B

::Enable JBOD SamrtFAN
:A
echo Enable JBOD SamrtFAN
for /F %%i IN ('sg_scan -s ^| find "AIC"') DO set expaddress=%%i
set exp=%expaddress:~0,17%
sg_ses --descriptor=CoolingElement00 --clear=1:7:1 %exp%

ehco sg_ses --descriptor=CoolingElement00 --get=1:7:1 %exp%
sg_ses --descriptor=CoolingElement00 --get=1:7:1 %exp%
echo GET 0 is Enable Auto FAN - Seccess
echo GET 1 is Disable Auto FAN - Seccess
pause
exit

::Disable JBOD SamrtFAN
:B
echo Disable JBOD SamrtFAN
for /F %%i IN ('sg_scan -s ^| find "AIC"') DO set expaddress=%%i
set exp=%expaddress:~0,17%
sg_ses --descriptor=CoolingElement00 --set=1:7:1 %exp%
pause
exit 

pause
