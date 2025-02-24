@echo off
setlocal enabledelayedexpansion

:: 檢查 user.txt 是否存在
if not exist user.txt (
    echo 找不到 user.txt，請確認檔案存在！
    pause
    exit /b
)

:: 讀取 user.txt 到變數並計算總人數
set count=0
for /f "delims=" %%A in (user.txt) do (
    set /a count+=1
    set "users[!count!]=%%A"
)

:: 確認人數
echo 讀取到 %count% 人

:: 設定每輪抽獎人數 (動態計算)
set /a "first_draw = count * 30 / 60"
set /a "second_draw = count * 20 / 60"
set /a "third_draw = count - first_draw - second_draw"

:: 修正可能的誤差
if %first_draw% lss 1 set first_draw=1
if %second_draw% lss 1 set second_draw=1
if %third_draw% lss 1 set third_draw=1

:: 確保總數不超過 count
set /a "total_draw = first_draw + second_draw + third_draw"
if %total_draw% gtr %count% (
    set /a "third_draw = count - first_draw - second_draw"
)

:: 開始抽獎
set index=1
for %%N in (%first_draw% %second_draw% %third_draw%) do (
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
