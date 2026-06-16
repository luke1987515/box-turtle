@ECHO OFF
setlocal EnableDelayedExpansion
cls

:: ============================================================================
:: Check Tools
:: ============================================================================
if not exist IOmeter.exe (
    echo ################
    echo ERROR: IOmeter.exe not found.
    echo Please put IOmeter.exe in this folder and try again.
    echo ################
    PAUSE
    EXIT /B
)

:: ============================================================================
:: Detect 3-Digit ICF Files Count
:: ============================================================================
set /a cnt_3digit=0
:loop_detect
set /a cnt_3digit+=1
set "formattedValue=000000%cnt_3digit%"
set FileName=!formattedValue:~-3!
if exist !FileName!.icf ( goto loop_detect ) else ( set /a cnt_3digit-=1 )

:: ============================================================================
:: Main Menu
:: ============================================================================
:MAIN_MENU
cls
echo ============================================================
echo   HDD RVI Test Batch Script (IOmeter Automation 3-Digit Only)
echo ============================================================
echo  [Detection Result]

if "%cnt_3digit%"=="0" goto DISPLAY_NO_FILE
echo  - 3-digit xxx.icf (001.icf ~): %cnt_3digit% file(s) found.
goto DISPLAY_MENU_OPTIONS

:DISPLAY_NO_FILE
echo  WARNING: No 3-digit .icf files detected in this folder.

:DISPLAY_MENU_OPTIONS
echo ============================================================
echo  Select an option to run test:
echo.

if "%cnt_3digit%"=="0" goto WAIT_QUIT_ONLY

echo   [1] Run ALL 3-digit ICF files (001 ~ %cnt_3digit%)
echo   [2] Run SINGLE 3-digit ICF file (e.g. 003)
echo   [3] Run RANGE of 3-digit ICF files (e.g. 039 to 076)
echo   [Q] Quit
============================================================
echo.

set "choice="
set /p choice="Enter your choice (1/2/3/Q): "

if /I "%choice%"=="1" goto RUN_ALL
if /I "%choice%"=="2" goto RUN_SINGLE
if /I "%choice%"=="3" goto RUN_RANGE
if /I "%choice%"=="Q" goto DO_QUIT

echo INVALID option, please try again.
timeout /t 2 >nul
goto MAIN_MENU

:WAIT_QUIT_ONLY
echo   [Q] Quit
echo ============================================================
echo.
set "choice="
set /p choice="Enter Q to quit: "
if /I "%choice%"=="Q" goto DO_QUIT
goto MAIN_MENU

:DO_QUIT
echo Goodbye...
timeout /t 2 >nul
exit /B

:: ============================================================================
:: Execution Blocks
:: ============================================================================

:RUN_ALL
echo.
echo Starting all %cnt_3digit% 3-digit tests...
for /L %%i in (1, 1, %cnt_3digit%) do (
    set "formattedValue=000000%%i"
    set FileName=!formattedValue:~-3!
    echo Running !FileName!.icf ...
    IOmeter.exe !FileName!.icf !FileName!.csv
)
goto TEST_FINISH

:RUN_SINGLE
echo.
set "single_num="
set /p single_num="Enter 3-digit file number (e.g. 1 or 003): "

:: Remove leading zeros for safe evaluation, then format back to 3-digits
for /f "tokens=* delims=0" %%a in ("%single_num%") do set "clean_num=%%a"
if "%clean_num%"=="" set "clean_num=0"

set "formattedValue=000000%clean_num%"
set FileName=!formattedValue:~-3!

if exist !FileName!.icf (
    echo Running single file !FileName!.icf ...
    IOmeter.exe !FileName!.icf !FileName!.csv
) else (
    echo ERROR: !FileName!.icf not found.
)
goto TEST_FINISH

:RUN_RANGE
echo.
set "start_num="
set "end_num="
set /p start_num="Enter START 3-digit number (e.g. 039): "
set /p end_num="Enter END 3-digit number (e.g. 076): "

:: 【核心修正】利用 for /f 去除前導零，避免 039 與 076 被當成錯誤的八進位
for /f "tokens=* delims=0" %%a in ("%start_num%") do set "clean_start=%%a"
if "%clean_start%"=="" set "clean_start=0"

for /f "tokens=* delims=0" %%a in ("%end_num%") do set "clean_end=%%a"
if "%clean_end%"=="" set "clean_end=0"

echo.
echo Starting 3-digit range test (%start_num% to %end_num%)...

:: 這裡使用去零後的純整數變數進行安全迴圈
for /L %%i in (%clean_start%, 1, %clean_end%) do (
    set "formattedValue=000000%%i"
    set FileName=!formattedValue:~-3!
    if exist !FileName!.icf (
        echo Running !FileName!.icf ...
        IOmeter.exe !FileName!.icf !FileName!.csv
    ) else (
        echo Skip: !FileName!.icf not found.
    )
)
goto TEST_FINISH

:: ============================================================================
:: End of Test
:: ============================================================================
:TEST_FINISH
echo ################
echo  Test process finished.
echo ################
PAUSE
goto MAIN_MENU