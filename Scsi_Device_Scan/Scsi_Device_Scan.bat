@echo off
setlocal EnableDelayedExpansion

:: Set global delay time (in seconds)
set DELAY_TIME=1

:: Define status parameters to test
set STATUS_LIST=1:7:1 1:6:1 1:5:1 1:4:1 1:3:1 1:2:1 1:1:1 1:0:1 2:7:1 2:6:1 2:4:1 2:3:1 2:2:1 2:1:1 3:5:1 3:4:1

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

    :: Execute sg_ses.exe and capture output
    sg_ses.exe %%A > temp_output.txt

    :: Check if "Element Descriptor (SES) [ed] [0x7]" exists in output
    findstr /C:"Element Descriptor (SES) [ed] [0x7]" temp_output.txt >nul
    if %errorlevel% equ 0 (
        echo "Element Descriptor page found. Executing sg_ses.exe %%A --page=0x7"
        sg_ses.exe %%A --page=0x7 > element_output.txt

        :: Initialize DiskCount
        set /a DiskCount=0

        :: Collect all DiskXXX names into a temporary list file
        del disk_list.txt 2>nul
        for /f "tokens=4" %%D in ('findstr /R "Disk" element_output.txt') do (
            echo %%D >> disk_list.txt
            set /a DiskCount+=1
        )

        :: Display total disk count
        echo Total Disks found: !DiskCount!

        :: Iterate over each STATUS_PARAM
        for %%S in (%STATUS_LIST%) do (
            echo Testing STATUS_PARAM: %%S

            :: Step 1: Check initial status (must be 0)
            for /f %%D in (disk_list.txt) do (
                set OutputValue=
                echo Checking initial status for %%D with %%S...
                for /f %%O in ('sg_ses.exe %%A --descriptor=%%D --get=%%S') do set OutputValue=%%O
                echo !OutputValue!
                if not "!OutputValue!"=="0" (
                    echo Error: Unexpected value for %%D. Stopping execution.
                    exit /b 1
                )
            )

            :: Step 2: Set status to 1
            for /f %%D in (disk_list.txt) do (
                echo Setting status for %%D with %%S...
                sg_ses.exe %%A --descriptor=%%D --set=%%S
                :: Wait for device processing
                timeout /t %DELAY_TIME% > nul  
            )

            :: Step 3: Verify status is now 1
            for /f %%D in (disk_list.txt) do (
                set OutputValue=
                echo Checking status after setting for %%D with %%S...
                for /f %%O in ('sg_ses.exe %%A --descriptor=%%D --get=%%S') do set OutputValue=%%O
                echo !OutputValue!
                if not "!OutputValue!"=="1" (
                    echo Error: Unexpected value for %%D after setting. Stopping execution.
                    exit /b 1
                )
            )

            :: Step 4: Clear status
            for /f %%D in (disk_list.txt) do (
                echo Clearing status for %%D with %%S...
                sg_ses.exe %%A --descriptor=%%D --clear=%%S
                :: Wait for device processing
                timeout /t %DELAY_TIME% > nul  
            )

            :: Step 5: Verify status is reset to 0
            for /f %%D in (disk_list.txt) do (
                set OutputValue=
                echo Checking final status for %%D with %%S...
                for /f %%O in ('sg_ses.exe %%A --descriptor=%%D --get=%%S') do set OutputValue=%%O
                echo !OutputValue!
                if not "!OutputValue!"=="0" (
                    echo Error: Unexpected value for %%D after clearing. Stopping execution.
                    exit /b 1
                )
            )
        )

        :: Clean up temporary files
        del element_output.txt
        del disk_list.txt
    ) else (
        echo "Element Descriptor page [0x7] not found, skipping."
    )

    :: Clean up temporary file
    del temp_output.txt
)

endlocal
