@echo off
setlocal enabledelayedexpansion

:: �ˬd user.txt �O�_�s�b
if not exist user.txt (
    echo �䤣�� user.txt�A�нT�{�ɮצs�b�I
    pause
    exit /b
)

:: Ū�� user.txt ���ܼƨíp���`�H��
set count=0
for /f "delims=" %%A in (user.txt) do (
    set /a count+=1
    set "users[!count!]=%%A"
)

:: �T�{�H��
echo Ū���� %count% �H

:: �]�w�C������H�� (�ʺA�p��)
set /a "first_draw = count * 30 / 60"
set /a "second_draw = count * 20 / 60"
set /a "third_draw = count - first_draw - second_draw"

:: �ץ��i�઺�~�t
if %first_draw% lss 1 set first_draw=1
if %second_draw% lss 1 set second_draw=1
if %third_draw% lss 1 set third_draw=1

:: �T�O�`�Ƥ��W�L count
set /a "total_draw = first_draw + second_draw + third_draw"
if %total_draw% gtr %count% (
    set /a "third_draw = count - first_draw - second_draw"
)

:: �}�l���
set index=1
for %%N in (%first_draw% %second_draw% %third_draw%) do (
    echo ======= �� !index! ����� (�� %%N �H) =======
    set /a "remaining=%count%"
    
    for /l %%I in (1,1,%%N) do (
        if !remaining! gtr 0 (
            set /a "rand=!random! %% remaining + 1"
            
            set "selected=!users[%rand%]!"
            echo !selected!
            
            rem �����ӦW��
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
