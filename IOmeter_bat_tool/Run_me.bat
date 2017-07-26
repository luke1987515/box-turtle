@echo off
:: Authoe: Luke.Chen <>
:: Date:   2017-07-26 14:17
:: Run_me.bat 是為了批次執行 "iometer_HBA CARD.icf" 及 "HDD Compatibility.icf"

:: 設定(紀錄)時間
set hh=%time:~0,2%
if "%time:~0,1%"==" " set hh=0%hh:~1,1%
set dt=%date:~0,4%-%date:~5,2%-%date:~8,2%_%hh%_%time:~3,2%_%time:~6,2%

:: 確認已更新 .icf 檔案
echo.
echo !!! 請確認已經更新 .icf 檔案 !!!
echo 若無
echo 1. 開啟 "iometer_HBA CARD.icf", "HDD Compatibility.icf"
echo 2. 選取 要 Run 的 Disk
echo 3. 按下 Save 覆蓋原始檔案
echo.
pause

:: 詢問 Project_name
:: set /p var=PleaseEnterVar:
echo.
echo 預設輸出檔名為 "results_AIC_HBA_CARD_時間.csv"
echo                "results_AIC_HDD_Comp_時間.csv"
echo.
set project_name=AIC
set /p project_name=請輸入 Project Name 變更 "AIC" 字串 (或 Enter 不改變):

:: Main function
echo.
echo 將執行 "iometer_HBA CARD.icf" 及 "HDD Compatibility.icf" 

echo.
echo 正在執行 "iometer_HBA CARD.icf"
iometer.exe /c "iometer_HBA CARD.icf"  /r "results_%project_name%_HBA_CARD_%dt%.csv"

echo.
echo 正在執行 "HDD Compatibility.icf" 
iometer.exe /c "HDD Compatibility.icf" /r "results_%project_name%_HDD_Comp_%dt%.csv"

echo.
echo 檔名為 "results_%project_name%_HBA_CARD_%dt%.csv"
echo 檔名為 "results_%project_name%_HDD_Comp_%dt%.csv"
echo.
echo Finish IOmeter Test on %date% %time%
pause