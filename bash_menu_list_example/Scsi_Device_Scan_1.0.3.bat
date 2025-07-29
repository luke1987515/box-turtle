@echo off
setlocal EnableDelayedExpansion

:: Set global delay time (in seconds)
set DELAY_TIME=1

:: Define status parameters to test
set STATUS_LIST=1:7:1 1:6:1 1:5:1 1:4:1 1:3:1 1:2:1 1:1:1 1:0:1 2:7:1 2:6:1 2:4:1 2:3:1 2:2:1 2:1:1 3:5:1 0:6:1

:: Define parameters to skip Step 1 initial value check
set SKIP_INIT_VERIFY_LIST=2:3:1 3:5:1

:: Define parameters to skip Step 3 verification (status check after setting)
set SKIP_VERIFY_LIST=2:7:1 2:4:1

:: Define parameters to skip Step 5 final value check
set SKIP_FINAL_VERIFY_LIST=1:1:1 2:3:1

:: Check if sg_scan.exe exists
where sg_scan.exe >nul 2>nul
if %errorlevel% neq 0 (
    echo Error: sg_scan.exe not found. Please install sg3_utils or ensure sg_scan.exe is in the PATH environment variable.
    exit /b 1
)

:: Check if sg_ses.exe exists
where sg_ses.exe >nul 2>nul
if %errorlevel% neq 0 (
    echo Error: sg_ses.exe not found. Please install sg3_utils or ensure sg_ses.exe is in the PATH environment variable.
    exit /b 1
)

:: Scan for SCSI devices and find the one containing "AIC"
for /f "tokens=1 delims= " %%A in ('sg_scan.exe -ss ^| findstr "AIC"') do (
    echo Found SCSI device: %%A

    sg_ses.exe %%A > temp_output.txt
    findstr /C:"Element Descriptor (SES) [ed] [0x7]" temp_output.txt >nul
    if !errorlevel! equ 0 (
        echo "Element Descriptor page found. Executing sg_ses.exe %%A --page=0x7"
        sg_ses.exe %%A --page=0x7 > element_output.txt

        set /a DiskCount=0
        del disk_list.txt 2>nul
        for /f "tokens=4" %%D in ('findstr /R "^.*Disk[0-9][0-9][0-9]$" element_output.txt') do (
            echo %%D >> disk_list.txt
            set /a DiskCount+=1
        )

        echo Total Disks found: !DiskCount!

        for %%S in (%STATUS_LIST%) do (
            echo ------------------------------------------------------------
            echo Testing STATUS_PARAM: %%S
            echo ------------------------------------------------------------

            :: Step 1
            echo Checking if STATUS_PARAM %%S needs initial status verification...
            echo %SKIP_INIT_VERIFY_LIST% | findstr /C:"%%S" >nul
            if !errorlevel! equ 0 (
                echo Skipping Step 1 initial status check for STATUS_PARAM: %%S
            ) else (
                for /f %%D in (disk_list.txt) do (
                    set "OutputValue="
                    echo Checking initial status for %%D with %%S...
                    for /f %%O in ('sg_ses.exe %%A --descriptor=%%D --get=%%S 2^>nul') do (
                        set "OutputValue=%%O"
                    )
                    echo Initial status for %%D: !OutputValue!
                    if not "!OutputValue!"=="0" (
                        echo Error: Unexpected initial value "!OutputValue!" for %%D. Stopping execution.
                        exit /b 1
                    )
                )
            )

            :: Step 2
            for /f %%D in (disk_list.txt) do (
                echo Setting status for %%D with %%S...
                sg_ses.exe %%A --descriptor=%%D --set=%%S
                timeout /t %DELAY_TIME% > nul
            )

            :: Step 3
            echo Checking if STATUS_PARAM %%S needs status verification after setting...
            echo %SKIP_VERIFY_LIST% | findstr /C:"%%S" >nul
            if !errorlevel! equ 0 (
                echo Skipping Step 3 verification for STATUS_PARAM: %%S
            ) else (
                for /f %%D in (disk_list.txt) do (
                    set "OutputValue="
                    echo Checking status after setting for %%D with %%S...
                    for /f %%O in ('sg_ses.exe %%A --descriptor=%%D --get=%%S 2^>nul') do (
                        set "OutputValue=%%O"
                    )
                    echo Retrieved status for %%D: !OutputValue!
                    if not "!OutputValue!"=="1" (
                        echo Error: Unexpected value "!OutputValue!" for %%D after setting. Stopping execution.
                        exit /b 1
                    )
                )
            )

            :: Step 4
            for /f %%D in (disk_list.txt) do (
                echo Clearing status for %%D with %%S...
                sg_ses.exe %%A --descriptor=%%D --clear=%%S
                timeout /t %DELAY_TIME% > nul
            )

            :: Step 5
            echo Checking if STATUS_PARAM %%S needs final status verification...
            echo %SKIP_FINAL_VERIFY_LIST% | findstr /C:"%%S" >nul
            if !errorlevel! equ 0 (
                echo Skipping Step 5 final status check for STATUS_PARAM: %%S
            ) else (
                for /f %%D in (disk_list.txt) do (
                    set "OutputValue="
                    echo Checking final status for %%D with %%S...
                    for /f %%O in ('sg_ses.exe %%A --descriptor=%%D --get=%%S 2^>nul') do (
                        set "OutputValue=%%O"
                    )
                    echo Final status for %%D: !OutputValue!
                    if not "!OutputValue!"=="0" (
                        echo Error: Unexpected value "!OutputValue!" for %%D after clearing. Stopping execution.
                        exit /b 1
                    )
                )
            )
        )

        del element_output.txt
        del disk_list.txt
    ) else (
        echo "Element Descriptor page [0x7] not found, skipping."
    )

    del temp_output.txt
)

endlocal
