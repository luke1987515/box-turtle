::[Bat To Exe Converter]
::
::YAwzoRdxOk+EWAnk
::fBw5plQjdG8=
::YAwzuBVtJxjWCl3EqQJgSA==
::ZR4luwNxJguZRRnk
::Yhs/ulQjdF+5
::cxAkpRVqdFKZSDk=
::cBs/ulQjdF+5
::ZR41oxFsdFKZSDk=
::eBoioBt6dFKZSDk=
::cRo6pxp7LAbNWATEpCI=
::egkzugNsPRvcWATEpCI=
::dAsiuh18IRvcCxnZtBJQ
::cRYluBh/LU+EWAnk
::YxY4rhs+aU+JeA==
::cxY6rQJ7JhzQF1fEqQJQ
::ZQ05rAF9IBncCkqN+0xwdVs0
::ZQ05rAF9IAHYFVzEqQJQ
::eg0/rx1wNQPfEVWB+kM9LVsJDGQ=
::fBEirQZwNQPfEVWB+kM9LVsJDGQ=
::cRolqwZ3JBvQF1fEqQJQ
::dhA7uBVwLU+EWDk=
::YQ03rBFzNR3SWATElA==
::dhAmsQZ3MwfNWATElA==
::ZQ0/vhVqMQ3MEVWAtB9wSA==
::Zg8zqx1/OA3MEVWAtB9wSA==
::dhA7pRFwIByZRRnk
::Zh4grVQjdCyDJGyX8VAjFDpQQQ2MNXiuFLQI5/rHy++UqVkSRN4ZTLDv36eaH/MQ+Ez0YYUR+m9RnfcPBB5bdS2pfAAjumtQiXKAJdSVvAHydkuB40g7JGdmiHTDiTkEdtZ6icoM3TPw+VX6/w==
::YB416Ek+ZG8=
::
::
::978f952a14a936cc963da21a135fa983
@echo off

echo.
echo     ************************************************************
echo     *                                                          *
echo     *                  ( CheckBrowserVersion )                 *
echo     *                                                          *
echo     ************************************************************

:: 檢查 Google Chrome 版本
for /f "tokens=3" %%a in ('reg query "HKCU\Software\Google\Chrome\BLBeacon" /v version') do set chrome_version=%%a
echo.
echo Chrome Version: %chrome_version%

:: 檢查 Mozilla Firefox 版本
for /f "tokens=2 delims==" %%a in ('wmic datafile where "name='C:\\Program Files\\Mozilla Firefox\\firefox.exe'" get version /value ^| find "Version="') do set firefox_version=%%a
echo.
echo Firefox Version: %firefox_version%

:: 檢查 Microsoft Edge 版本
for /f "tokens=3" %%a in ('reg query "HKCU\Software\Microsoft\Edge\BLBeacon" /v version') do set edge_version=%%a
echo.
echo Edge Version: %edge_version%

:: 檢查 Internet Explorer 版本
for /f "tokens=3" %%a in ('reg query "HKLM\Software\Microsoft\Internet Explorer" /v svcVersion') do set ie_version=%%a
echo.
echo Internet Explorer Version: %ie_version%

echo.

