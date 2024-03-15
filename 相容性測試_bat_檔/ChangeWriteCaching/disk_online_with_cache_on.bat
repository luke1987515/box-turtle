:: 
:: Author      : luke1987515@hotmail.com
:: Time        : 2020-12-28T16:07:24
:: Description : Add disk number detect
:: Description : Remove disk clean to skeep boot disk
:: Time        : 2018-07-10 09:12 
:: Description : Add select disk after clear disk attributes fail
:: Time        : 2018-07-03 09:50 
:: Description : Add offline
:: Time        : 2018-07-02 14:37 
:: Description : Add clean 
:: Time        : 2018-06-08 13:50 
:: Description : Auto disk online tool

@echo off

setlocal EnableDelayedExpansion

echo ################
echo Disk Online Tool
echo ################
echo.
echo Disk detect...

for /f "tokens=2" %%a in ('echo list disk ^| diskpart') do ( 
 set DiskNum=%%a
)

echo. > diskpart_conf.tmp

FOR /L %%i IN (0,1,%DiskNum%) DO (
  echo select disk %%i                      >> diskpart_conf.tmp
  echo offline disk noerr                   >> diskpart_conf.tmp
  echo attributes disk clear readonly noerr >> diskpart_conf.tmp
  echo select disk %%i                      >> diskpart_conf.tmp
  echo online disk noerr                    >> diskpart_conf.tmp
  echo convert mbr noerr                    >> diskpart_conf.tmp
)

diskpart /s diskpart_conf.tmp

del /Q diskpart_conf.tmp

:: Run IOmeter
:: iometer.exe /c "HDD_test.icf" /r "results_YYYY-MM-DD.csv"

echo.
echo #######################
echo Total %DiskNum% Disk Online!
echo #######################
echo.

echo ################
echo Get diskdrive get Index
echo ################
::ic diskdrive get   %%i
wmic diskdrive get Index  > diskdrive.tmp
type diskdrive.tmp > diskdrive.txt

:: Sort diskdrive get Index 
:: I don't know why but IT WORK!!
:: ==============================================
for /f "skip=1 tokens=1" %%i in (diskdrive.txt) do (
	set /A a=1000+%%i
    set "line[!a:~1!]=%%i
)


::Show array elements
::sort diskdrive.txt
for /F "tokens=2 delims==" %%a in ('set line[') do echo %%a >> disksort_index.tmp
type disksort_index.tmp

:: ===============================================

for /f "skip=1" %%a in (disksort_index.tmp) do ( 
 echo PHYSICALDRIVE%%a
 dskcache.exe +w PHYSICALDRIVE%%a
)

echo.
echo #######################
echo Total %DiskNum% Disk cache off!
echo #######################
echo.

for /f "skip=1" %%a in (disksort_index.tmp) do ( 
 echo PHYSICALDRIVE%%a
 dskcache.exe PHYSICALDRIVE%%a | findstr /C:"Write Cache is disabled"
 
 )

if exist diskdrive.tmp del /Q diskdrive.tmp
if exist diskdrive.txt del /Q diskdrive.txt
if exist disksort_index.tmp del /Q disksort_index.tmp

PAUSE
