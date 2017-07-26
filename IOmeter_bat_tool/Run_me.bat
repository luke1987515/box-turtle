@echo off
:: Authoe: Luke.Chen <>
:: Date:   2017-07-26 14:17
:: Run_me.bat �O���F�妸���� "iometer_HBA CARD.icf" �� "HDD Compatibility.icf"

:: �]�w(����)�ɶ�
set hh=%time:~0,2%
if "%time:~0,1%"==" " set hh=0%hh:~1,1%
set dt=%date:~0,4%-%date:~5,2%-%date:~8,2%_%hh%_%time:~3,2%_%time:~6,2%

:: �T�{�w��s .icf �ɮ�
echo.
echo !!! �нT�{�w�g��s .icf �ɮ� !!!
echo �Y�L
echo 1. �}�� "iometer_HBA CARD.icf", "HDD Compatibility.icf"
echo 2. ��� �n Run �� Disk
echo 3. ���U Save �л\��l�ɮ�
echo.
pause

:: �߰� Project_name
:: set /p var=PleaseEnterVar:
echo.
echo �w�]��X�ɦW�� "results_AIC_HBA_CARD_�ɶ�.csv"
echo                "results_AIC_HDD_Comp_�ɶ�.csv"
echo.
set project_name=AIC
set /p project_name=�п�J Project Name �ܧ� "AIC" �r�� (�� Enter ������):

:: Main function
echo.
echo �N���� "iometer_HBA CARD.icf" �� "HDD Compatibility.icf" 

echo.
echo ���b���� "iometer_HBA CARD.icf"
iometer.exe /c "iometer_HBA CARD.icf"  /r "results_%project_name%_HBA_CARD_%dt%.csv"

echo.
echo ���b���� "HDD Compatibility.icf" 
iometer.exe /c "HDD Compatibility.icf" /r "results_%project_name%_HDD_Comp_%dt%.csv"

echo.
echo �ɦW�� "results_%project_name%_HBA_CARD_%dt%.csv"
echo �ɦW�� "results_%project_name%_HDD_Comp_%dt%.csv"
echo.
echo Finish IOmeter Test on %date% %time%
pause