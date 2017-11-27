echo off
:: Author:  Luke.Chen <luke1987515@gmail.com>
:: Date:    2017-11-27 10:51
:: Purpose: 檢查 HDD 數量
:: Step:
:: 1. 複製 check_hdd_number.bat & diskpart_script.txt 到 PC
:: 2. 開啟 "OS rebooter" 工具，將此 check_hdd_number.bat 路徑放置 Appliction 中
:: 3. 執行 "OS rebooter" 
:: 4. 結束後 check_hdd_number.bat 路徑多出 result 檔案
:: 5. 檢查結果 

cls
echo #####################################################
echo ### 檢查 HDD 數量的工具 V1.0.0
echo #####################################################
echo.

:: 判斷 gold_hdd_list.txt 是否存在
IF EXIST gold_hdd_list.txt (
echo.
echo !!!! 已存在 gold_hdd_list.txt !!!!
echo #####################################################
type gold_hdd_list.txt
echo.
echo #####################################################
echo !!!! 已存在 gold_hdd_list.txt !!!!
echo.
echo ### 如果這不是你要的 gold_hdd_list.txt 檔案 ###
echo ### 按下  Y/y   刪除 gold_hdd_list.txt 檔案 ###
echo ###     5 sec 後保留繼續...                 ### 

choice /C YN /T 5 /D N /M "Would you like to clear 'gold_hdd_list.txt' ??" 
if errorlevel 2 goto normalc
if errorlevel 1 goto clearc

:clearc
del gold_hdd_list.txt
echo ###  刪除舊 gold_hdd_list.txt 檔案 ###
echo.
echo !!!! 請確認 HDD 數量正確 !!!!
echo #####################################################
diskpart /s diskpart_script.txt
echo.
echo #####################################################
echo !!!! 請確認 HDD 數量正確 !!!!
diskpart /s diskpart_script.conf > gold_hdd_list.txt
goto end_choice1

:normalc
echo ###  保留舊 gold_hdd_list.txt 檔案 ###
goto end_choice1

) ELSE (
echo.
echo ###  不存在 gold_hdd_list.txt 檔案 ###
echo ###  建立   gold_hdd_list.txt 檔案 ###
echo.
echo !!!! 請確認 HDD 數量正確 !!!!
echo #####################################################
diskpart /s diskpart_script.conf
echo.
echo #####################################################
echo !!!! 請確認 HDD 數量正確 !!!!
diskpart /s diskpart_script.conf > gold_hdd_list.txt
)

:end_choice1
echo.
echo ###  完成 gold_hdd_list.txt 設置 ###
timeout /t 3 /nobreak

:: count 執行次數
IF NOT EXIST count.txt (
echo.
echo ### 不存在 count.txt   檔案 ###
set /a "number=0"
echo 0 > count.txt
echo ### 建立   count.txt   檔案 ###

) ELSE (
echo.
echo !!!! 已存在 count.txt !!!!
echo Count number：
echo #####################################################
type count.txt
echo #####################################################
echo ### 如果這不是你要的 count 次數 ###
echo ### 按下  Y/y   歸零 count 次數 ###
echo ###     5 sec 後繼續計數...     ### 

choice /C YN /T 5 /D N /M "Would you like to clear 'count.txt' ??" 
if errorlevel 2 goto normalc_count
if errorlevel 1 goto clearc_count

:clearc_count
del count.txt
echo ### 刪除舊 count.txt    檔案 ###
echo ### 歸零   count number 次數 ###
set /a "number=0"
echo 0 > count.txt
goto end_choice2

:normalc_count
echo ### 保留舊 count.txt    檔案 ###
type count.txt
echo ### 使得   count number 加 1 ###
FOR /F "eol= " %%i in (count.txt) do (set /a "number=%%i%+1")
echo %number%
echo %number% > count.txt
goto end_choice2
)

:end_choice2
echo.
echo ### 完成   count.txt   設置 ###
echo.
FOR /F "eol=" %%i in (count.txt) do (echo 現在是第 %%i% 次)
timeout /t 3 /nobreak


:: 設定(紀錄)時間
set hh=%time:~0,2%
if "%time:~0,1%"==" " set hh=0%hh:~1,1%
set dt=%date:~0,4%-%date:~5,2%-%date:~8,2%_%hh%_%time:~3,2%_%time:~6,2%

:: 如果 Count number 歸零，清空 result.log 檔案  
if "%number%"=="0" (echo %dt% > result.log)

echo ### 開始與原始資料(gold_hdd_list.txt)比對 ###
diskpart /s diskpart_script.conf
diskpart /s diskpart_script.conf > hdd_list_%number%.txt

echo.
echo ### 比對結果 ###
FC gold_hdd_list.txt hdd_list_%number%.txt
FC gold_hdd_list.txt hdd_list_%number%.txt >> result.log