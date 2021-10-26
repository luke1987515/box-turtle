@echo off

echo.
echo ################
echo TO_ICF
echo ################
echo.

setlocal EnableDelayedExpansion

if exist *.icf del /Q *.icf
if exist *.tmp del /Q *.tmp

set ManagerName=ManagerName

:: Get ManagerName
for /f "usebackq skip=1 tokens=*" %%i in (`wmic computersystem get name ^| findstr /r /v "^$" `) do (
	    set ManagerName=%%i )

echo ################
echo Get ManagerName= %ManagerName%
echo ################


echo ################
echo Get os get "SystemDrive"
echo ################

wmic os get "SystemDrive" > SystemDrive.tmp
type SystemDrive.tmp > SystemDrive.txt

for /f "skip=1 tokens=1,2,3,4* " %%i in (SystemDrive.txt) do (
    echo %%i
    set SystemDrive=%%i
)
echo ################
echo Get os get "SystemDrive"="%SystemDrive%"
echo ################

echo ################
echo Get os get "SystemDriveID"
echo ################

wmic logicaldisk where 'DeviceID="%SystemDrive%"' get Access > SystemDriveID.tmp

type SystemDriveID.tmp > SystemDriveID.txt

for /f "skip=1 tokens=1,2,3,4* " %%i in (SystemDriveID.txt) do (
    echo %%i
    set SystemDriveID=%%i
)
echo ################
echo Get os get "SystemDriveID"="%SystemDriveID%"
echo ################

echo ################
echo Get diskdrive get FirmwareRevision, Index, Model
echo ################
::ic diskdrive get              %%i,   %%j,           %%k,   %%l
wmic diskdrive get FirmwareRevision, Index, InterfaceType, Model  > diskdrive.tmp
type diskdrive.tmp > diskdrive.txt

for /f "skip=1 tokens=1,2,3,4,5* " %%i in (diskdrive.txt) do (
    set "formattedValue=%%l %%m %%n"
	set /A a=100+%%j
    if %%j==%SystemDriveID% (
        echo REMOVE %%j !formattedValue:~0,20! %%i -- THIS IS OS DISK
    )else (
		set b=SAS_2K
		if %%k==IDE (
		    set b=SATA_6K
		    ::echo !a:~1! !formattedValue:~0,20! %%i 
		    set "line[!a:~1!]=%%j %%i !b! ^(!formattedValue:~0,20! 
		)else if %%l==ATA (
			set b=SATA_6K
            set "line[!a:~1!]=%%j %%i !b! !formattedValue:~0,20!
        )else (
            set "line[!a:~1!]=%%j %%i !b! !formattedValue:~0,20!
		)	    
    )
)

if exist disksort.txt del /Q disksort.txt

rem Show array elements
for /F "tokens=2 delims==" %%a in ('set line[') do echo %%a
for /F "tokens=2 delims==" %%a in ('set line[') do echo %%a >> disksort.txt

::type disklist.tmp
::sort disklist.tmp > disksort.txt
::type disksort.txt

echo ################
echo Get spic Line -skip 1--------------
echo ################

for /f "tokens=1,2,3,4,5* " %%i in (disksort.txt) do (
    set "formattedValue=%%l %%m %%n"
	set /A a=100+%%j
	set "line[!a:~1!]=%%j %%i !b! !formattedValue:~0,20!
)

for /F "skip=1 tokens=2 delims==" %%a in ('set line[') do (
    echo %%a 
	goto nxetline)
:nxetline

echo ################
echo Get spic Line -skip 3--------------
echo ################

for /f "tokens=1,2,3,4,5* " %%i in (disksort.txt) do (
    set "formattedValue=%%l %%m %%n"
	set /A a=100+%%j
	set "line[!a:~1!]=%%j %%i !b! !formattedValue:~0,20!
)

for /F "skip=3 tokens=2 delims==" %%a in ('set line[') do (
    echo %%a 
	goto nxetline)
:nxetline

echo ################
echo Get spic Line -skip 6--------------
echo ################

for /f "tokens=1,2,3,4,5* " %%i in (disksort.txt) do (
    set "formattedValue=%%l %%m %%n"
	set /A a=100+%%j
	set "line[!a:~1!]=%%j %%i !b! !formattedValue:~0,20!
)

for /F "skip=6 tokens=2 delims==" %%a in ('set line[') do (
    echo %%a > temp.tmp
	goto nxetline)
:nxetline


echo ################
echo Get spic Line ---------------
echo ################

echo ################
echo Careate icf_info.tmp file
echo ################

:: Careate icf_info_top.tmp
set TampFileName=icf_info_top
::echo ################
::echo Careate !TampFileName!.tmp 
::echo ################
::echo.
echo Version 1.1.0 >> !TampFileName!.tmp
echo 'TEST SETUP ==================================================================== >> !TampFileName!.tmp
echo 'Test Description >> !TampFileName!.tmp
echo. >> !TampFileName!.tmp
echo 'Run Time >> !TampFileName!.tmp
echo '	hours      minutes    seconds >> !TampFileName!.tmp
echo 	0          10         0 >> !TampFileName!.tmp
echo 'Ramp Up Time ^(s^) >> !TampFileName!.tmp
echo 	300 >> !TampFileName!.tmp
echo 'Default Disk Workers to Spawn >> !TampFileName!.tmp
echo 	NUMBER_OF_CPUS >> !TampFileName!.tmp
echo 'Default Network Workers to Spawn >> !TampFileName!.tmp
echo 	0 >> !TampFileName!.tmp
echo 'Record Results >> !TampFileName!.tmp
echo 	ALL >> !TampFileName!.tmp
echo 'Worker Cycling >> !TampFileName!.tmp
echo '	start      step       step type >> !TampFileName!.tmp
echo 	1          1          LINEAR >> !TampFileName!.tmp
echo 'Disk Cycling >> !TampFileName!.tmp
echo '	start      step       step type >> !TampFileName!.tmp
echo 	1          1          LINEAR >> !TampFileName!.tmp
echo 'Queue Depth Cycling >> !TampFileName!.tmp
echo '	start      end        step       step type >> !TampFileName!.tmp
echo 	1          32         2          EXPONENTIAL >> !TampFileName!.tmp
echo 'Test Type >> !TampFileName!.tmp
echo 	NORMAL >> !TampFileName!.tmp
echo 'END test setup >> !TampFileName!.tmp
echo 'RESULTS DISPLAY =============================================================== >> !TampFileName!.tmp
echo 'Record Last Update Results,Update Frequency,Update Type >> !TampFileName!.tmp
echo 	DISABLED,1,WHOLE_TEST >> !TampFileName!.tmp
echo 'Bar chart 1 statistic >> !TampFileName!.tmp
echo 	Total I/Os per Second >> !TampFileName!.tmp
echo 'Bar chart 2 statistic >> !TampFileName!.tmp
echo 	Total MBs per Second (Decimal) >> !TampFileName!.tmp
echo 'Bar chart 3 statistic >> !TampFileName!.tmp
echo 	Average I/O Response Time (ms) >> !TampFileName!.tmp
echo 'Bar chart 4 statistic >> !TampFileName!.tmp
echo 	Maximum I/O Response Time (ms) >> !TampFileName!.tmp
echo 'Bar chart 5 statistic >> !TampFileName!.tmp
echo 	%% CPU Utilization (total) >> !TampFileName!.tmp
echo 'Bar chart 6 statistic >> !TampFileName!.tmp
echo 	Total Error Count >> !TampFileName!.tmp
echo 'END results display >> !TampFileName!.tmp
echo 'ACCESS SPECIFICATIONS ========================================================= >> !TampFileName!.tmp
echo 'Access specification name,default assignment >> !TampFileName!.tmp
echo 	SAS_2K,NONE >> !TampFileName!.tmp
echo 'size,%% of size,%% reads,%% random,delay,burst,align,reply >> !TampFileName!.tmp
echo 	2048,100,0,100,0,1,2048,0 >> !TampFileName!.tmp
echo 'Access specification name,default assignment >> !TampFileName!.tmp
echo 	SATA_6K,NONE >> !TampFileName!.tmp
echo 'size,%% of size,%% reads,%% random,delay,burst,align,reply >> !TampFileName!.tmp
echo 	6144,100,0,100,0,1,6144,0 >> !TampFileName!.tmp
echo 'END access specifications >> !TampFileName!.tmp
echo 'MANAGER LIST ================================================================== >> !TampFileName!.tmp
echo 'Manager ID, manager name >> !TampFileName!.tmp
echo 	1, >> !TampFileName!.tmp
echo 'Manager network address >> !TampFileName!.tmp
echo. >> !TampFileName!.tmp


:: Careate icf_Worker_info_top.tmp
set TampFileName=icf_Worker_info_top
::echo ################
::echo Careate !TampFileName!.tmp 
::echo ################
::echo.
echo 'Worker >> !TampFileName!.tmp
::echo     Worker 1 >> !TampFileName!.tmp

:: Careate icf_Worker_info_mid_top.tmp
set TampFileName=icf_Worker_info_mid_top
::echo ################
::echo Careate !TampFileName!.tmp 
::echo ################
::echo.
echo 'Worker type >> !TampFileName!.tmp
echo 	DISK >> !TampFileName!.tmp
echo 'Default target settings for worker >> !TampFileName!.tmp
echo 'Number of outstanding IOs,test connection rate,transactions per connection,use fixed seed,fixed seed value >> !TampFileName!.tmp
::echo 	1,DISABLED,1,DISABLED,0 >> !TampFileName!.tmp

:: Careate icf_Worker_info_mid_mid.tmp
set TampFileName=icf_Worker_info_mid_mid
::echo ################
::echo Careate !TampFileName!.tmp 
::echo ################
::echo.
echo 'Disk maximum size,starting sector,Data pattern >> !TampFileName!.tmp
echo 	0,0,0 >> !TampFileName!.tmp
echo 'End default target settings for worker >> !TampFileName!.tmp
echo 'Assigned access specs >> !TampFileName!.tmp
::echo 	SAS_2K >> !TampFileName!.tmp

:: Careate icf_Worker_info_mid_bot.tmp
set TampFileName=icf_Worker_info_mid_bot
echo 'End assigned access specs >> !TampFileName!.tmp
echo 'Target assignments >> !TampFileName!.tmp
echo 'Target >> !TampFileName!.tmp
::echo     1: "" >> !TampFileName!.tmp

:: Careate icf_Worker_info_bot.tmp
set TampFileName=icf_Worker_info_bot
::echo ################
::echo Careate !TampFileName!.tmp 
::echo ################
::echo.
echo 'Target type >> !TampFileName!.tmp
echo 	DISK >> !TampFileName!.tmp
echo 'End target >> !TampFileName!.tmp
echo 'End target assignments >> !TampFileName!.tmp
echo 'End worker >> !TampFileName!.tmp

:: Careate icf_info_bot.tmp
set TampFileName=icf_info_bot
::echo ################
::echo Careate !TampFileName!.tmp 
::echo ################
::echo.
echo 'End manager >> !TampFileName!.tmp
echo 'END manager list >> !TampFileName!.tmp
echo Version 1.1.0 >> !TampFileName!.tmp

echo ################
echo Start carte many icf file 
echo ################
echo.

set file=disksort.txt
set /a cnt=0
for /f %%a in ('type "%file%"^|find "" /v /c') do set /a cnt=%%a
echo %file% has %cnt% lines

set DiskNum=%cnt%

set /a count=1

::LOOP
::if %count% LEQ %DiskNum% (
::    set "formattedValue=000000%count%"
::    set FileName=!formattedValue:~-2!
::    echo !FileName!.icf
::    for /f "tokens=1,2,3,4* " %%i in (disksort.txt) do (
::        echo %%i %%j %%k )
::    set /a count +=1
::    goto LOOP
::)

echo ################
echo Get spic Line -skip 3-------------
echo ################

set SKIP=5
for /f "tokens=1,2,3,4,5* " %%i in (disksort.txt) do (
    set "formattedValue=%%l %%m %%n"
	set /A a=100+%%j
	set "line[!a:~1!]=%%i %%j !b! !formattedValue:~0,20!
)

for /F "skip=%SKIP% tokens=2 delims==" %%a in ('set line[') do (
    echo %%a > temp.tmp
	goto nxetline)
:nxetline

echo ################
echo get spic disk info 
echo ################

set NULL=

for /f "tokens=1,2,3,4,5* " %%i in (temp.tmp) do (
    set TargetID=%%i
	set TargetFW=%%j
    if "%%n"=="" if "%%m"=="" (
	    set TargetName=%%l
	)else if "%%n"=="" (
	    set TargetName=%%l %%m
	)else (
	    set TargetName=%%l %%m %%n
	)
	set AssignedName=%%k
)
echo ################
echo NULL="%NULL%" 
echo ################

echo ################
echo TargetName="%TargetName%" 
echo ################


echo %AssignedName% %TargetID% %TargetName% %TargetFW%

echo ################
echo Start carte many icf file 
echo ################
echo.

set DiskNum=2
set FileName=00

for /L %%i in (1, 1, %DiskNum%) do (
    set "formattedValue=000000%%i"
	set FileName=!formattedValue:~-2!
    echo !FileName!.icf
	:: imput icf_info_top
	type icf_info_top.tmp                               >> !FileName!.icf
	    :: imput icf_Worker_info_top(outstanding=8)
	    type icf_Worker_info_top.tmp                    >> !FileName!.icf
        echo     Worker 1 >> !FileName!.icf
	    :: imput icf_Worker_mid_top	 
	    type icf_Worker_info_mid_top.tmp                >> !FileName!.icf
	    echo 	8,DISABLED,1,DISABLED,0 >> !FileName!.icf
	    :: imput icf_Worker_info_mid_mid
	    type icf_Worker_info_mid_mid.tmp                >> !FileName!.icf
		echo 	SAS_2K >> !FileName!.icf
	    :: imput icf_Worker_info_mid_bot
	    type icf_Worker_info_mid_bot.tmp                >> !FileName!.icf
	    echo     %%i: "">> !FileName!.icf
	    :: imput icf_Worker_info_bot
	    type icf_Worker_info_bot.tmp                    >> !FileName!.icf
	:: imput Other Worker info(outstanding=1)
	for /L %%j in (2, 1, %DiskNum%) do (
	    if %%i==%%j (
		    :: imput icf_Worker_info_top
	        type icf_Worker_info_top.tmp                >> !FileName!.icf
            echo     Worker %%j >> !FileName!.icf
	        :: imput icf_Worker_mid_top	 
	        type icf_Worker_info_mid_top.tmp            >> !FileName!.icf
	        echo 	1,DISABLED,1,DISABLED,0 >> !FileName!.icf
	        :: imput icf_Worker_info_mid_mid
	        type icf_Worker_info_mid_mid.tmp                >> !FileName!.icf
		    echo 	SAS_2K >> !FileName!.icf
			:: imput icf_Worker_info_mid_bot
	        type icf_Worker_info_mid_bot.tmp            >> !FileName!.icf
	        echo     1: "" >> !FileName!.icf
		    :: imput icf_Worker_info_bot
	        type icf_Worker_info_bot.tmp                >> !FileName!.icf
	    )else (
		    :: imput icf_Worker_info_top
	        type icf_Worker_info_top.tmp                >> !FileName!.icf
            echo     Worker %%j >> !FileName!.icf
	        :: imput icf_Worker_mid_top	 
	        type icf_Worker_info_mid_top.tmp            >> !FileName!.icf
	        echo 	1,DISABLED,1,DISABLED,0 >> !FileName!.icf
	        :: imput icf_Worker_info_mid_mid
	        type icf_Worker_info_mid_mid.tmp                >> !FileName!.icf
		    echo 	SAS_2K >> !FileName!.icf
			:: imput icf_Worker_info_mid_bot
	        type icf_Worker_info_mid_bot.tmp            >> !FileName!.icf
	        echo     %%j: "" >> !FileName!.icf
	        :: imput icf_Worker_info_bot
	        type icf_Worker_info_bot.tmp                >> !FileName!.icf     
	    )
	)
	 type icf_info_bot.tmp                              >> !FileName!.icf
)

echo.
echo ################
echo Complete carte many icf file 
echo ################
echo.

if exist *.tmp del /Q *.tmp

PAUSE