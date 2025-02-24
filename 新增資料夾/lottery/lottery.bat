@echo off
setlocal enabledelayedexpansion

:: 設定檔案名稱
set "input_file=user.txt"
set "winners_file=winners.txt"
set "next_round_file=next_round.txt"

if not exist "%input_file%" (
    echo [錯誤] 找不到 %input_file%
    pause
    exit /b
)

:: 讀取名單並計算人數
set count=0
for /f "tokens=*" %%A in (%input_file%) do (
    set "users[!count!]=%%A"
    set /a count+=1
)

echo 目前名單共有 %count% 人。
set /p draw_count=請輸入要抽出的人數：

if %draw_count% gtr %count% (
    echo [錯誤] 抽出人數不可超過總人數！
    pause
    exit /b
)

:: 產生亂數並抽出中獎者
echo --- 中籤名單 --- > %winners_file%
set "selected_list="

for /L %%I in (1,1,%draw_count%) do (
    :retry
    set /a rand=%random% %% %count%
    echo !selected_list! 
    set "selected_list=!selected_list! !rand!"
    echo !users[%rand%]! >> %winners_file%
)

:: 產生晉級名單
echo --- 晉級名單 --- > %next_round_file%
for /L %%I in (0,1,%count%-1) do (
    echo !selected_list! | findstr /b "!users[%%I]!" >nul || echo !users[%%I]! >> %next_round_file%
)

echo 已完成抽獎！
echo - 中籤名單已存至 %winners_file%
echo - 晉級名單已存至 %next_round_file%
pause
