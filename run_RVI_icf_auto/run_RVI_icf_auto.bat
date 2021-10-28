::echo ################
::echo Test Script --- You can remove it
::echo ################

@ECHO OFF

setlocal EnableDelayedExpansion

:GetRAND
SET /A RAND=%RANDOM%
::ECHO %RAND%
ECHO.

SET /A RAND=%RAND%%%10
::ECHO %RAND%
ECHO.

set DiskNum=%RAND%

::echo DiskNum="%DiskNum%"

::if exist *.icf del /Q *.icf

if "%DiskNum%"=="0" (
    ::echo get DiskNum=0 %DiskNum%
	goto GetRAND
)else (
    ::echo get DiskNum not 0 is "%DiskNum%"
	for /L %%i in (1, 1, %DiskNum%) do (
        set "formattedValue=000000%%i"
	    set FileName=!formattedValue:~-2!
	    ::set FileName=!formattedValue:~-3!
		::echo not create icf file
		echo.
	    ::echo !FileName!.icf
		echo.
	    ::echo %%i %%i > !FileName!.icf
		echo.
    )
)
::echo ################
::echo Test Script --- You can remove it
::echo ################

echo ################
echo RUN ICF FILE
echo ################

@ECHO OFF

setlocal EnableDelayedExpansion

cls
echo ################
echo RUN ICF FILE
echo ################
echo. 
echo ################
echo Read executable ICF file
echo ################

set /a cnt=0

:loop

set /a cnt+=1
set "formattedValue=000000%cnt%"
set FileName=!formattedValue:~-2!

if exist !FileName!.icf (
    echo !FileName!.icf
	::type !FileName!.icf
	goto loop
)else (
    break
)


::echo ################
::echo Read execute xxx ICF file
::echo ################

set /a cnt_2=0

:loop_2

set /a cnt_2+=1
set "formattedValue=000000%cnt_2%"
set FileName=!formattedValue:~-3!

if exist !FileName!.icf (
    echo !FileName!.icf
	::type !FileName!.icf
	goto loop_2
)else (
    break
)

echo.
echo ################
echo How many icf in this folder   
echo ################

set /a cnt-=1
set /a cnt_2-=1

::echo "cnt"="%cnt%"
::echo "cnt_2"="%cnt_2%"

if "%cnt_2%"=="0" if "%cnt%"=="0" (
        echo Ooops here not exist xx.icf and xxx.icf FILE
    	echo ################
		echo STOP - Do Noting
		echo ################ 
    )else (
		echo Here has Total "%cnt%" icf FILE
		echo ################
		echo OK - That do it 
		echo ################
		if exist iometer (		
		    for /L %%i in (1, 1, %cnt%) do (
		        set "formattedValue=000000%%i"
	            set FileName=!formattedValue:~-2!
                echo !FileName!.icf running...
			    ::type !FileName!.icf
			    iometer !FileName!.icf !FileName!.csv
			)
			echo ################
			echo Finish 01~!FileName!.icf
			echo ################
		)else (
			echo ################
			echo No IOmeter tool
			echo Please put IOmeter in this folder, Thanks.
			echo ################
		    echo STOP - Do Noting
		    echo ################ 
		)
)else if "%cnt%"=="0" (
        echo Here has Total "%cnt_2%" icf FILE
		echo ################
		echo OK - That do it  
		echo ################
		if exist iometer (		
		    for /L %%i in (1, 1, %cnt2%) do (
		        set "formattedValue=000000%%i"
	            set FileName=!formattedValue:~-3!
                echo !FileName!.icf running...
			    ::type !FileName!.icf
			    iometer !FileName!.icf !FileName!.csv
			)
			echo ################
			echo Finish 001~!FileName!.icf
			echo ################
		)else (
			echo ################
			echo No IOmeter tool
			echo Please put IOmeter in this folder, Thanks.
			echo ################
		    echo STOP - Do Noting
		    echo ################ 
		)
    )else (
		echo Here hava "%cnt%" xx.icf and "%cnt_2%" xxx.icf FILE that is strangeness.
    	echo ################
		echo STOP - Do Noting
		echo ################ 
)

PAUSE
