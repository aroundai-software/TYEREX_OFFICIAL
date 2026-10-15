@echo off
cd /d "%~dp0"
>> "%cd%\install_sync.log" echo clicked Install %date% %time%
REM Open a window that cannot close by itself.
if /I not "%~1"=="--inner" (
    start "Tyrex Tally Sync Install" cmd /k ""%~f0" --inner"
    exit /b
)

setlocal EnableExtensions
cd /d "%~dp0"
title Tyrex Tally Sync - Install
set "EXE=%cd%\TyrexTallySync.exe"
set "ENVFILE=%cd%\tally_sync.env"
set "LOG=%cd%\install_sync.log"
set "TASK=TyrexTallySync"

echo ============================================
echo Tyrex Tally Sync - Install
echo Folder: %cd%
echo ============================================
echo.
> "%LOG%" echo ===== Install %date% %time% =====
>> "%LOG%" echo Folder: %cd%
>> "%LOG%" echo User: %USERNAME%
dir /b >> "%LOG%" 2>&1

if not exist "%EXE%" (
    echo ERROR: TyrexTallySync.exe is not in this folder.
    echo Copy exe, tally_sync.env, and this bat into the same folder.
    >> "%LOG%" echo ERROR: exe missing
    goto DONE
)

set "SINCE=2026-09-26"
set "UNTIL=2027-09-26"
for /f %%I in ('powershell -NoProfile -Command "(Get-Date).ToString('yyyy-MM-dd')" 2^>nul') do set "SINCE=%%I"
for /f %%I in ('powershell -NoProfile -Command "(Get-Date).AddYears(1).ToString('yyyy-MM-dd')" 2^>nul') do set "UNTIL=%%I"
>> "%LOG%" echo SINCE=%SINCE% UNTIL=%UNTIL%
echo Sync window: %SINCE% to %UNTIL%

if not exist "%ENVFILE%" (
    echo TALLY_HOST=localhost> "%ENVFILE%"
    echo TALLY_PORT=9000>> "%ENVFILE%"
    echo TALLY_TIMEOUT=30>> "%ENVFILE%"
    >> "%LOG%" echo created tally_sync.env
)

echo SYNC_SINCE=%SINCE%>> "%ENVFILE%"
echo SYNC_UNTIL=%UNTIL%>> "%ENVFILE%"
echo SYNC_INTERVAL_SECONDS=60>> "%ENVFILE%"
>> "%LOG%" echo updated env dates

echo Registering sync to start at Windows logon...
set "OK=0"
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v TyrexTallySync /t REG_SZ /d "\"%EXE%\" --watch" /f >> "%LOG%" 2>&1
if not errorlevel 1 (
    echo   Startup registry key added.
    set "OK=1"
) else (
    echo   Registry startup key failed. See install_sync.log
)

set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "LNK=%STARTUP%\TyrexTallySync.lnk"
if not exist "%STARTUP%" mkdir "%STARTUP%" >> "%LOG%" 2>&1
> "%TEMP%\tyrex_lnk.vbs" echo Set o = CreateObject("WScript.Shell")
>> "%TEMP%\tyrex_lnk.vbs" echo Set s = o.CreateShortcut("%LNK:\=\\%")
>> "%TEMP%\tyrex_lnk.vbs" echo s.TargetPath = "%EXE:\=\\%"
>> "%TEMP%\tyrex_lnk.vbs" echo s.Arguments = "--watch"
>> "%TEMP%\tyrex_lnk.vbs" echo s.WorkingDirectory = "%cd:\=\\%"
>> "%TEMP%\tyrex_lnk.vbs" echo s.WindowStyle = 7
>> "%TEMP%\tyrex_lnk.vbs" echo s.Save
cscript //nologo "%TEMP%\tyrex_lnk.vbs" >> "%LOG%" 2>&1
if exist "%LNK%" (
    echo   Startup shortcut added.
    set "OK=1"
) else (
    echo   Startup shortcut failed. See install_sync.log
)

if "%OK%"=="0" (
    echo ERROR: could not register startup. Sync will run now, but not after restart.
) else (
    echo Startup registered. Sync will start after login / restart.
)

echo Stopping any existing TyrexTallySync process...
taskkill /F /IM TyrexTallySync.exe >nul 2>&1
timeout /t 1 /nobreak >nul

echo Starting watcher now...
start "" /D "%cd%" "%EXE%" --watch
>> "%LOG%" echo started exe --watch

echo.
echo Installed Tyrex Tally Sync.
echo   Starts at Windows logon / after restart
echo   Syncs only while Tally is open with a company
echo   Waits 1 minute between syncs
echo   Job cards from %SINCE% through %UNTIL%
echo   Log: %cd%\tally_sync.log
echo   Install log: %LOG%
echo.
echo Keep tally_sync.env in this folder. Tally ODBC/HTTP port: TALLY_PORT=9000

:DONE
echo.
echo This window will stay open. Close it after you read the message.
echo.
pause
exit /b 0
