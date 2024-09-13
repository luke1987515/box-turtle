@echo off
:: Loop ipmitool SDR
:: 作者： luke.chen luke.chen@aicipc.com.tw
:: 2024-05-14T16:2808+08:00

:loop

echo %date% 
echo %time% 
echo =============================================================
ipmitool.exe -I lanplus -H 192.168.11.11 -U admin -P admin123 sdr
ping 127.0.0.1 -n 3 > nul 
echo =============================================================
echo. 

goto loop