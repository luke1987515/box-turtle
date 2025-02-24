@echo off
setlocal enabledelayedexpansion

set "userfile=user.txt"
set "winnerfile=winner.txt"
set "remainingfile=remaining.txt"

REM 讀取名單人數
set count=0
for /f "delims=" %%a in (%userfile%) do (
  set /a count+=1
)

echo 總人數：%count%

REM 隨機抽取一人
set /a winnerindex=(%random% %% %count%) + 1

echo %winnerindex%

set index=0
for /f "delims=" %%a in (%userfile%) do (
	echo %%a
    set /a index+=1
   echo !index!
  if !index! == !winnerindex! (
    set "winner=%%a"
    echo 中獎者：!winner!
    echo !winner! >> %winnerfile%
  ) else (
    echo %%a >> %remainingfile%
  )

)

echo 中獎名單已匯出至 %winnerfile%
echo 晉級名單已匯出至 %remainingfile%

endlocal
pause