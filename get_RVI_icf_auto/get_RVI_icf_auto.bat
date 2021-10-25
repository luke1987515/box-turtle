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
echo 	RVI_SAS_disk(2K),NONE >> !TampFileName!.tmp
echo 'size,%% of size,%% reads,%% random,delay,burst,align,reply >> !TampFileName!.tmp
echo 	2048,100,0,100,0,1,2048,0 >> !TampFileName!.tmp
echo 'Access specification name,default assignment >> !TampFileName!.tmp
echo 	RVI_SATA_disk(6K),NONE >> !TampFileName!.tmp
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

:: Careate icf_Worker_info_mid_bot.tmp
set TampFileName=icf_Worker_info_mid_bot
::echo ################
::echo Careate !TampFileName!.tmp 
::echo ################
::echo.
echo 'Disk maximum size,starting sector,Data pattern >> !TampFileName!.tmp
echo 	0,0,0 >> !TampFileName!.tmp
echo 'End default target settings for worker >> !TampFileName!.tmp
echo 'Assigned access specs >> !TampFileName!.tmp
echo 	RVI_SAS_disk(2K) >> !TampFileName!.tmp
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
echo Disk detect...
echo ################

for /f "tokens=2,3" %%a in ('echo list disk ^| diskpart') do ( 
    set DiskNum=%%a )

echo ################
echo Start carte many icf file 
echo ################
echo.

::set DiskNum=26
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
