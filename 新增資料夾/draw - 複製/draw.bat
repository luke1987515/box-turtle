@echo off
setlocal enabledelayedexpansion

set "userfile=user.txt"
set "winnerfile=winner.txt"
set "remainingfile=remaining.txt"

REM Ū���W��H��
set count=0
for /f "delims=" %%a in (%userfile%) do (
  set /a count+=1
)

echo �`�H�ơG%count%

REM �H������@�H
set /a winnerindex=(%random% %% %count%) + 1

echo %winnerindex%

set index=0
for /f "delims=" %%a in (%userfile%) do (
	echo %%a
    set /a index+=1
   echo !index!
  if !index! == !winnerindex! (
    set "winner=%%a"
    echo �����̡G!winner!
    echo !winner! >> %winnerfile%
  ) else (
    echo %%a >> %remainingfile%
  )

)

echo �����W��w�ץX�� %winnerfile%
echo �ʯŦW��w�ץX�� %remainingfile%

endlocal
pause