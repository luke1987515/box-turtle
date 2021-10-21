@echo off

echo.
echo ################
echo TO_ICF
echo ################
echo.

setlocal EnableDelayedExpansion

if exist *.icf del /Q *.icf
if exist *.icf del /Q *.tmp

echo ################
echo Careate icf_info.tmp file
echo ################

:: Careate icf_info_top.tmp
set filename=icf_info_top
::echo ################
::echo Careate !filename!.tmp 
::echo ################
::echo.
echo Version 1.1.0                                                                    >> !filename!.tmp
echo 'TEST SETUP ==================================================================== >> !filename!.tmp
echo 'Test Description                                                                >> !filename!.tmp
echo.                                                                                 >> !filename!.tmp
echo 'Run Time                                                                        >> !filename!.tmp
echo '	hours      minutes    seconds                                                 >> !filename!.tmp
echo 	0          10         0                                                       >> !filename!.tmp
echo 'Ramp Up Time ^(s^)                                                              >> !filename!.tmp
echo 	300                                                                           >> !filename!.tmp
echo 'Default Disk Workers to Spawn                                                   >> !filename!.tmp
echo 	NUMBER_OF_CPUS                                                                >> !filename!.tmp
echo 'Default Network Workers to Spawn                                                >> !filename!.tmp
echo 	0                                                                             >> !filename!.tmp
echo 'Record Results                                                                  >> !filename!.tmp
echo 	ALL                                                                           >> !filename!.tmp
echo 'Worker Cycling                                                                  >> !filename!.tmp
echo '	start      step       step type                                               >> !filename!.tmp
echo 	1          1          LINEAR                                                  >> !filename!.tmp
echo 'Disk Cycling                                                                    >> !filename!.tmp
echo '	start      step       step type                                               >> !filename!.tmp
echo 	1          1          LINEAR                                                  >> !filename!.tmp
echo 'Queue Depth Cycling                                                             >> !filename!.tmp
echo '	start      end        step       step type                                    >> !filename!.tmp
echo 	1          32         2          EXPONENTIAL                                  >> !filename!.tmp
echo 'Test Type                                                                       >> !filename!.tmp
echo 	NORMAL                                                                        >> !filename!.tmp
echo 'END test setup                                                                  >> !filename!.tmp
echo 'RESULTS DISPLAY =============================================================== >> !filename!.tmp
echo 'Record Last Update Results,Update Frequency,Update Type                         >> !filename!.tmp
echo 	DISABLED,1,WHOLE_TEST                                                         >> !filename!.tmp
echo 'Bar chart 1 statistic                                                           >> !filename!.tmp
echo 	Total I/Os per Second                                                         >> !filename!.tmp
echo 'Bar chart 2 statistic                                                           >> !filename!.tmp
echo 	Total MBs per Second (Decimal)                                                >> !filename!.tmp
echo 'Bar chart 3 statistic                                                           >> !filename!.tmp
echo 	Average I/O Response Time (ms)                                                >> !filename!.tmp
echo 'Bar chart 4 statistic                                                           >> !filename!.tmp
echo 	Maximum I/O Response Time (ms)                                                >> !filename!.tmp
echo 'Bar chart 5 statistic                                                           >> !filename!.tmp
echo 	%% CPU Utilization (total)                                                    >> !filename!.tmp
echo 'Bar chart 6 statistic                                                           >> !filename!.tmp
echo 	Total Error Count                                                             >> !filename!.tmp
echo 'END results display                                                             >> !filename!.tmp
echo 'ACCESS SPECIFICATIONS ========================================================= >> !filename!.tmp
echo 'Access specification name,default assignment                                    >> !filename!.tmp
echo 	RVI_SAS_disk,NONE                                                             >> !filename!.tmp
echo 'size,%% of size,%% reads,%% random,delay,burst,align,reply                      >> !filename!.tmp
echo 	2048,100,0,100,0,1,2048,0                                                     >> !filename!.tmp
echo 'END access specifications                                                       >> !filename!.tmp
echo 'MANAGER LIST ================================================================== >> !filename!.tmp
echo 'Manager ID, manager name                                                        >> !filename!.tmp
echo 	1,AIC-RVI                                                                     >> !filename!.tmp
echo 'Manager network address                                                         >> !filename!.tmp
echo.                                                                                 >> !filename!.tmp


:: Careate icf_Worker_info_top.tmp
set filename=icf_Worker_info_top
::echo ################
::echo Careate !filename!.tmp 
::echo ################
::echo.
echo 'Worker                                                                          >> !filename!.tmp
::echo     Worker 1                                                                     >> !filename!.tmp

:: Careate icf_Worker_info_mid_top.tmp
set filename=icf_Worker_info_mid_top
::echo ################
::echo Careate !filename!.tmp 
::echo ################
::echo.
echo 'Worker type                                                                     >> !filename!.tmp
echo 	DISK                                                                          >> !filename!.tmp
echo 'Default target settings for worker                                              >> !filename!.tmp
echo 'Number of outstanding IOs,test connection rate,transactions per connection,use fixed seed,fixed seed value >> !filename!.tmp
::echo 	1,DISABLED,1,DISABLED,0                                                       >> !filename!.tmp

:: Careate icf_Worker_info_mid_bot.tmp
set filename=icf_Worker_info_mid_bot
::echo ################
::echo Careate !filename!.tmp 
::echo ################
::echo.
echo 'Disk maximum size,starting sector,Data pattern                                  >> !filename!.tmp
echo 	0,0,0                                                                         >> !filename!.tmp
echo 'End default target settings for worker                                          >> !filename!.tmp
echo 'Assigned access specs                                                           >> !filename!.tmp
echo 	RVI_SAS_disk                                                                  >> !filename!.tmp
echo 'End assigned access specs                                                       >> !filename!.tmp
echo 'Target assignments                                                              >> !filename!.tmp
echo 'Target                                                                          >> !filename!.tmp
::echo     1: ""                                                                      >> !filename!.tmp

:: Careate icf_Worker_info_bot.tmp
set filename=icf_Worker_info_bot
::echo ################
::echo Careate !filename!.tmp 
::echo ################
::echo.
echo 'Target type                                                                     >> !filename!.tmp
echo 	DISK                                                                          >> !filename!.tmp
echo 'End target                                                                      >> !filename!.tmp
echo 'End target assignments                                                          >> !filename!.tmp
echo 'End worker                                                                      >> !filename!.tmp

:: Careate icf_info_bot.tmp
set filename=icf_info_bot
::echo ################
::echo Careate !filename!.tmp 
::echo ################
::echo.
echo 'End manager                                                                     >> !filename!.tmp
echo 'END manager list                                                                >> !filename!.tmp
echo Version 1.1.0                                                                    >> !filename!.tmp

echo ################
echo Disk detect...
echo ################

for /f "tokens=2,3" %%a in ('echo list disk ^| diskpart') do ( 
    set DiskNum=%%a )

echo ################
echo Start carte many icf file 
echo ################
echo.

::set DiskNum=4

for /L %%i in (1, 1, %DiskNum%) do (
    set "formattedValue=000000%%i"
    echo !formattedValue:~-3!.icf
	:: imput icf_info_top
	type icf_info_top.tmp                                                                 >> !formattedValue:~-3!.icf
	    :: imput icf_Worker_info_top(outstanding=8)
	    type icf_Worker_info_top.tmp                                                          >> !formattedValue:~-3!.icf
        echo     Worker 1                                                                     >> !formattedValue:~-3!.icf
	    :: imput icf_Worker_mid_top	 
	    type icf_Worker_info_mid_top.tmp                                                      >> !formattedValue:~-3!.icf
	    echo 	8,DISABLED,1,DISABLED,0                                                       >> !formattedValue:~-3!.icf
	    :: imput icf_Worker_info_mid_bot
	    type icf_Worker_info_mid_bot.tmp                                                      >> !formattedValue:~-3!.icf
	    echo     %%i: ""                                                                      >> !formattedValue:~-3!.icf
	    :: imput icf_Worker_info_bot
	    type icf_Worker_info_bot.tmp                                                          >> !formattedValue:~-3!.icf
	:: imput Other Worker info(outstanding=1)
	for /L %%j in (2, 1, %DiskNum%) do (
	    if %%i==%%j (
		    :: imput icf_Worker_info_top
	        type icf_Worker_info_top.tmp                                                      >> !formattedValue:~-3!.icf
            echo     Worker %%j                                                               >> !formattedValue:~-3!.icf
	        :: imput icf_Worker_mid_top	 
	        type icf_Worker_info_mid_top.tmp                                                  >> !formattedValue:~-3!.icf
	        echo 	1,DISABLED,1,DISABLED,0                                                   >> !formattedValue:~-3!.icf
	        :: imput icf_Worker_info_mid_bot
	        type icf_Worker_info_mid_bot.tmp                                                  >> !formattedValue:~-3!.icf
	        echo     1: ""                                                                    >> !formattedValue:~-3!.icf
		    :: imput icf_Worker_info_bot
	        type icf_Worker_info_bot.tmp                                                      >> !formattedValue:~-3!.icf
	    )else (
		    :: imput icf_Worker_info_top
	        type icf_Worker_info_top.tmp                                                      >> !formattedValue:~-3!.icf
            echo     Worker %%j                                                               >> !formattedValue:~-3!.icf
	        :: imput icf_Worker_mid_top	 
	        type icf_Worker_info_mid_top.tmp                                                  >> !formattedValue:~-3!.icf
	        echo 	1,DISABLED,1,DISABLED,0                                                   >> !formattedValue:~-3!.icf
	        :: imput icf_Worker_info_mid_bot
	        type icf_Worker_info_mid_bot.tmp                                                  >> !formattedValue:~-3!.icf
	        echo     %%j: ""                                                                  >> !formattedValue:~-3!.icf
	        :: imput icf_Worker_info_bot
	        type icf_Worker_info_bot.tmp                                                      >> !formattedValue:~-3!.icf     
	    )
	)
	 type icf_info_bot.tmp                                                                >> !formattedValue:~-3!.icf
)

echo.
echo ################
echo Complete carte many icf file 
echo ################
echo.

del /Q *.tmp