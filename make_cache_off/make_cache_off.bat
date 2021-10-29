:: 
:: Author      : luke1987515@hotmail.com
:: Time        : 2021-10-29T13:56:00
:: Description : Change method to get disk list
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

echo ################
echo Get System get BootPartition="TRUE" Disk number
echo ################

if exist SystemDriveID.tmp del /Q SystemDriveID.tmp

wmic partition where 'BootPartition="TRUE"' get DeviceID,BootPartition > SystemDrive.tmp

type SystemDrive.tmp > SystemDrive_ID.tmp

if exist SystemDriveID.tmp del /Q SystemDriveID.tmp

for /f "skip=1 tokens=1,2,3,4* " %%i in (SystemDrive_ID.tmp) do (
    echo i="%%i" j="%%j" k="%%k" l="%%l"
    echo BootableDriveID=%%k
    set "SystemDriveID=%%k"
    echo !SystemDriveID:~1,1! >> SystemDriveID.tmp
)

echo ################
echo Get System get BootPartition="TRUE" Disk number
echo ################
type SystemDriveID.tmp
echo ################
echo.
echo ################
echo Show diskdrive get Index, InterfaceType remove USB
echo ################

if exist disk_list.tmp del /Q disk_list.tmp

wmic diskdrive get Index, InterfaceType > disk_drive.tmp
type disk_drive.tmp > diskdrive.tmp

for /f "skip=1 tokens=1,2" %%i in (diskdrive.tmp) do (
    ::echo i="%%i",j="%%j",
	if "%%j"=="USB" (
	    echo REMOVE %%i -- THIS IS USB DISK
	)else (
	    echo %%i
	    echo %%i >> disk_list.tmp
	)
)

echo ################
echo Show diskdrive get Index, InterfaceType remove USB
echo ################
echo.
echo ################
type disk_list.tmp
echo ################


echo ################
echo Remove OS Disk
echo ################


copy SystemDriveID.tmp SystemDriveID_tmp.tmp
copy disk_list.tmp disksort_os_tmp.tmp

:get_ID

set "ID="

for /f "tokens=1" %%z in (SystemDriveID_tmp.tmp) do (
    echo "z"="%%z"
    set ID=%%z
    goto nextline
)
:nextline

if "%ID%"=="" (
    echo No remove bootable disk ID
)else (
    findstr /v "%ID%" < SystemDriveID_tmp.tmp > cat.txt
    echo ========
    type cat.txt
    echo ========
)

echo "ID"="%ID%"

if "%ID%"=="" (
    echo Finish remove bootable disk
)else (
    for /f "tokens=1,* " %%i in (disksort_os_tmp.tmp) do (
        if "%%i"=="%ID%" (
            echo REMOVE %%i --- THIS IS OS_bootable DISK
        )else (
            echo i="%%i" j="%%j"
            echo %%i %%j >> dog.txt
        )
    )
    move cat.txt SystemDriveID_tmp.tmp
    move dog.txt disksort_os_tmp.tmp 
    goto get_ID
)

echo ========
echo SystemDriveID_tmp.tmp
echo ========
type SystemDriveID_tmp.tmp
echo ========
echo.
echo ========
echo disksort_os_tmp.tmp
echo ========
type disksort_os_tmp.tmp
echo ========
move disksort_os_tmp.tmp disksort.tmp

echo ################
echo ################
type disksort.tmp
echo ################
echo ################

echo ################
echo Get disksort.tmp file line-------------
echo ################
set file=disksort.tmp
set /a cnt=0
for /f %%a in ('type "%file%"^|find "" /v /c') do set /a cnt=%%a
echo %file% has %cnt% lines

set DiskNum=%cnt%

::echo ################
::echo ################
::echo Careate diskpart_conf.tmp FILE
::echo ################
::echo ################
::
::
::if exist diskpart_conf.tmp del /Q diskpart_conf.tmp
::
::for /f "tokens=1" %%i in (disksort.tmp) do (
::  echo select disk %%i                      >> diskpart_conf.tmp
::  echo offline disk noerr                   >> diskpart_conf.tmp
::  echo attributes disk clear readonly noerr >> diskpart_conf.tmp
::  echo select disk %%i                      >> diskpart_conf.tmp
::  echo online disk noerr                    >> diskpart_conf.tmp
::  echo convert mbr noerr                    >> diskpart_conf.tmp
::)
::
::echo ################
::echo ################
::type diskpart_conf.tmp
::echo ################
::echo ################

::diskpart /s diskpart_conf.tmp

::del /Q diskpart_conf.tmp

:: Run IOmeter
:: iometer.exe /c "HDD_test.icf" /r "results_YYYY-MM-DD.csv"

echo.
echo #######################
echo %file% has %DiskNum% lines
echo #######################
echo.
echo #######################
echo Total %DiskNum% Disk Online!
echo #######################
echo.

for /f "tokens=1" %%a in (disksort.tmp) do (
   echo.
   echo #######################
   echo PHYSICALDRIVE%%a
   dskcache.exe -w PHYSICALDRIVE%%a
   echo PHYSICALDRIVE%%a
   echo #######################
   echo.
)

echo.
echo #######################
echo Total %DiskNum% Disk cache off!
echo #######################
echo.

del /Q *.tmp

PAUSE