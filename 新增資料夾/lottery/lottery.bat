@echo off
setlocal enabledelayedexpansion

:: �]�w�ɮצW��
set "input_file=user.txt"
set "winners_file=winners.txt"
set "next_round_file=next_round.txt"

if not exist "%input_file%" (
    echo [���~] �䤣�� %input_file%
    pause
    exit /b
)

:: Ū���W��íp��H��
set count=0
for /f "tokens=*" %%A in (%input_file%) do (
    set "users[!count!]=%%A"
    set /a count+=1
)

echo �ثe�W��@�� %count% �H�C
set /p draw_count=�п�J�n��X���H�ơG

if %draw_count% gtr %count% (
    echo [���~] ��X�H�Ƥ��i�W�L�`�H�ơI
    pause
    exit /b
)

:: ���Ͷüƨé�X������
echo --- ���ҦW�� --- > %winners_file%
set "selected_list="

for /L %%I in (1,1,%draw_count%) do (
    :retry
    set /a rand=%random% %% %count%
    echo !selected_list! 
    set "selected_list=!selected_list! !rand!"
    echo !users[%rand%]! >> %winners_file%
)

:: ���ͮʯŦW��
echo --- �ʯŦW�� --- > %next_round_file%
for /L %%I in (0,1,%count%-1) do (
    echo !selected_list! | findstr /b "!users[%%I]!" >nul || echo !users[%%I]! >> %next_round_file%
)

echo �w��������I
echo - ���ҦW��w�s�� %winners_file%
echo - �ʯŦW��w�s�� %next_round_file%
pause
