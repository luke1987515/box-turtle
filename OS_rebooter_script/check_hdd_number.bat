echo off
:: Author:  Luke.Chen <luke1987515@gmail.com>
:: Date:    2017-11-27 10:51
:: Purpose: �ˬd HDD �ƶq
:: Step:
:: 1. �ƻs check_hdd_number.bat & diskpart_script.txt �� PC
:: 2. �}�� "OS rebooter" �u��A�N�� check_hdd_number.bat ���|��m Appliction ��
:: 3. ���� "OS rebooter" 
:: 4. ������ check_hdd_number.bat ���|�h�X result �ɮ�
:: 5. �ˬd���G 

cls
echo #####################################################
echo ### �ˬd HDD �ƶq���u�� V1.0.0
echo #####################################################
echo.

:: �P�_ gold_hdd_list.txt �O�_�s�b
IF EXIST gold_hdd_list.txt (
echo.
echo !!!! �w�s�b gold_hdd_list.txt !!!!
echo #####################################################
type gold_hdd_list.txt
echo.
echo #####################################################
echo !!!! �w�s�b gold_hdd_list.txt !!!!
echo.
echo ### �p�G�o���O�A�n�� gold_hdd_list.txt �ɮ� ###
echo ### ���U  Y/y   �R�� gold_hdd_list.txt �ɮ� ###
echo ###     5 sec ��O�d�~��...                 ### 

choice /C YN /T 5 /D N /M "Would you like to clear 'gold_hdd_list.txt' ??" 
if errorlevel 2 goto normalc
if errorlevel 1 goto clearc

:clearc
del gold_hdd_list.txt
echo ###  �R���� gold_hdd_list.txt �ɮ� ###
echo.
echo !!!! �нT�{ HDD �ƶq���T !!!!
echo #####################################################
diskpart /s diskpart_script.txt
echo.
echo #####################################################
echo !!!! �нT�{ HDD �ƶq���T !!!!
diskpart /s diskpart_script.conf > gold_hdd_list.txt
goto end_choice1

:normalc
echo ###  �O�d�� gold_hdd_list.txt �ɮ� ###
goto end_choice1

) ELSE (
echo.
echo ###  ���s�b gold_hdd_list.txt �ɮ� ###
echo ###  �إ�   gold_hdd_list.txt �ɮ� ###
echo.
echo !!!! �нT�{ HDD �ƶq���T !!!!
echo #####################################################
diskpart /s diskpart_script.conf
echo.
echo #####################################################
echo !!!! �нT�{ HDD �ƶq���T !!!!
diskpart /s diskpart_script.conf > gold_hdd_list.txt
)

:end_choice1
echo.
echo ###  ���� gold_hdd_list.txt �]�m ###
timeout /t 3 /nobreak

:: count ���榸��
IF NOT EXIST count.txt (
echo.
echo ### ���s�b count.txt   �ɮ� ###
set /a "number=0"
echo 0 > count.txt
echo ### �إ�   count.txt   �ɮ� ###

) ELSE (
echo.
echo !!!! �w�s�b count.txt !!!!
echo Count number�G
echo #####################################################
type count.txt
echo #####################################################
echo ### �p�G�o���O�A�n�� count ���� ###
echo ### ���U  Y/y   �k�s count ���� ###
echo ###     5 sec ���~��p��...     ### 

choice /C YN /T 5 /D N /M "Would you like to clear 'count.txt' ??" 
if errorlevel 2 goto normalc_count
if errorlevel 1 goto clearc_count

:clearc_count
del count.txt
echo ### �R���� count.txt    �ɮ� ###
echo ### �k�s   count number ���� ###
set /a "number=0"
echo 0 > count.txt
goto end_choice2

:normalc_count
echo ### �O�d�� count.txt    �ɮ� ###
type count.txt
echo ### �ϱo   count number �[ 1 ###
FOR /F "eol= " %%i in (count.txt) do (set /a "number=%%i%+1")
echo %number%
echo %number% > count.txt
goto end_choice2
)

:end_choice2
echo.
echo ### ����   count.txt   �]�m ###
echo.
FOR /F "eol=" %%i in (count.txt) do (echo �{�b�O�� %%i% ��)
timeout /t 3 /nobreak


:: �]�w(����)�ɶ�
set hh=%time:~0,2%
if "%time:~0,1%"==" " set hh=0%hh:~1,1%
set dt=%date:~0,4%-%date:~5,2%-%date:~8,2%_%hh%_%time:~3,2%_%time:~6,2%

:: �p�G Count number �k�s�A�M�� result.log �ɮ�  
if "%number%"=="0" (echo %dt% > result.log)

echo ### �}�l�P��l���(gold_hdd_list.txt)��� ###
diskpart /s diskpart_script.conf
diskpart /s diskpart_script.conf > hdd_list_%number%.txt

echo.
echo ### ��ﵲ�G ###
FC gold_hdd_list.txt hdd_list_%number%.txt
FC gold_hdd_list.txt hdd_list_%number%.txt >> result.log