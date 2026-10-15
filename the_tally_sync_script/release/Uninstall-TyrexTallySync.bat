@echo off
cd /d "%~dp0"
>> "%cd%\install_sync.log" echo clicked Uninstall %date% %time%
if /I not "%~1"=="--inner" (
    start "Tyrex Tally Sync Uninstall" cmd /k ""%~f0" --inner"
    exit /b
)

setlocal EnableExtensions
cd /d "%~dp0"
title Tyrex Tally Sync - Uninstall
set "TASK=TyrexTallySync"
set "LOG=%cd%\install_sync.log"

echo ============================================
echo Tyrex Tally Sync - Uninstall
echo ============================================
echo.
>> "%LOG%" echo ===== Uninstall %date% %time% =====

taskkill /IM TyrexTallySync.exe /F >> "%LOG%" 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v TyrexTallySync /f >> "%LOG%" 2>&1
del /f /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\TyrexTallySync.lnk" >> "%LOG%" 2>&1
schtasks /End /TN "%TASK%" >> "%LOG%" 2>&1
schtasks /Delete /TN "%TASK%" /F >> "%LOG%" 2>&1
echo Startup registration removed.

echo Uninstalled. The exe and logs are still in this folder.
echo.
echo This window will stay open. Close it after you read the message.
echo.
pause
exit /b 0
