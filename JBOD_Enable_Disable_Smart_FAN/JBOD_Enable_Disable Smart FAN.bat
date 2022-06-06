@echo off
::sg_scan -s to Show the device for AIC Expander Controller 

setlocal EnableDelayedExpansion

set /p Set=Input (1:Enable 2:Disable):

::Enable JBOD SamrtFAN, clear 1:7:1
if "%Set%"=="1" set "operator=clear"
::Disable JBOD SamrtFAN, set 1:7:1
if "%Set%"=="2" set "operator=set"
:: Wrong Input
if not "%Set%"=="1" if not "%Set%"=="2" goto :END 

echo ====================
echo Enable JBOD SamrtFAN
echo ====================
echo.
for /F %%i in ('sg_scan -s ^| find "AIC"') do (
  echo ====================
  echo Enclosure : "%%i"
  echo --------------------
  sg_ses --descriptor=CoolingElement00 --%operator%=1:7:1 %%i
  echo sg_ses --descriptor=CoolingElement00 --%operator%=1:7:1 %%i
  echo sg_ses --descriptor=CoolingElement00 --get=1:7:1 %%i
  :: sg_ses --descriptor=CoolingElement00 --get=1:7:1 %%i
  sg_ses --descriptor=CoolingElement00 --get=1:7:1 %%i > info_A.tmp
  echo --------------------
  for /f %%a in (info_A.tmp) do (
  set "var=%%a"
    if "%Set%"=="1" if "!var!"=="0" echo GET 0 : Enable JBOD SamrtFAN - Seccess
    if "%Set%"=="1" if "!var!"=="1" echo GET 1 : Enable JBOD SamrtFAN - FAILED
	if "%Set%"=="2" if "!var!"=="0" echo GET 0 : Disable JBOD SamrtFAN - FAILED
    if "%Set%"=="2" if "!var!"=="1" echo GET 1 : Disable JBOD SamrtFAN - Seccess
  )
  echo ====================
  echo.
)

if exist *.tmp del /Q *.tmp

pause
exit

:END
echo NOT 1 or 2 , Wrong Input 

pause