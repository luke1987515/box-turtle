:: 
:: Author      : luke1987515@hotmail.com
:: Time        : 2020-09-25 15:49 
:: Description : Add create partition after convert mbr
:: Time        : 2018-07-10 09:12 
:: Description : Add select disk after clear disk attributes fail
:: Time        : 2018-07-03 09:50 
:: Description : Add offline
:: Time        : 2018-07-02 14:37 
:: Description : Add clean 
:: Time        : 2018-06-08 13:50 
:: Description : Auto disk online tool

@echo off

echo. > diskpart_conf.tmp

FOR /L %%i IN (1,1,24) DO (
  echo select disk %%i                      >> diskpart_conf.tmp
  echo offline disk noerr                   >> diskpart_conf.tmp
  echo attributes disk clear readonly noerr >> diskpart_conf.tmp
  echo select disk %%i                      >> diskpart_conf.tmp
  echo online disk noerr                    >> diskpart_conf.tmp
  echo clean                                >> diskpart_conf.tmp
  echo convert mbr noerr                    >> diskpart_conf.tmp
  echo create partition primary noerr       >> diskpart_conf.tmp
  echo create volume simple noerr           >> diskpart_conf.tmp
)

diskpart /s diskpart_conf.tmp

del /Q diskpart_conf.tmp

:: Run IOmeter
:: iometer.exe /c "60HDD_test.icf" /r "results_2018-06-08.csv"
