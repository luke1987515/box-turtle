@echo off
setlocal enabledelayedexpansion

:: 檢查 user.txt 是否存在
if not exist user.txt (
    echo 找不到 user.txt，請確認檔案存在！
    pause
    exit /b
)

:: 讀取 user.txt 到變數
set count=0
for /f "delims=" %%A in (user.txt) do (
    set /a count+=1
    set "users[!count!]=%%A"
)

:: 確認人數正確
if %count% lss 60 (
    echo 人數不足 60，請確認 user.txt！
    pause
    exit /b
)

:: 定義抽獎次數與每輪人數
set rounds=3
set numbers=30 20 10
set index=1

:: 開始抽獎
for %%N in (%numbers%) do (
    echo ======= 第 !index! 次抽獎 (抽 %%N 人) =======
    set /a "remaining=%count%"
    
    for /l %%I in (1,1,%%N) do (
        if !remaining! gtr 0 (
            set /a "rand=!random! %% remaining + 1"
            
            set "selected=!users[%rand%]!"
            echo !selected!
            
            rem 移除該名單
            for /l %%J in (!rand!,1,!remaining!) do (
                set /a "next=%%J+1"
                set "users[%%J]=!users[%next%]!"
            )
            set /a "remaining-=1"
            set /a "count-=1"
        )
    )

    echo.
    set /a "index+=1"
)

pause
