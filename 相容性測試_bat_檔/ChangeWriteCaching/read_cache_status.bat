@echo off

for /f "skip=1" %%a in ('wmic diskdrive get Index') do ( 
 echo PHYSICALDRIVE%%a
 dskcache.exe PHYSICALDRIVE%%a
)

:: dskcache.exe -w PHYSICALDRIVE%%a

PAUSE