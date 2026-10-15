@echo off
setlocal
echo =======================================================
echo Building TyreX Tally Sync Enterprise Installer
echo =======================================================

cd /d "%~dp0"

echo [1/3] Compiling background sync daemon (TyrexTallySync.exe)...
pyinstaller --clean TyrexTallySync.spec
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] TyrexTallySync daemon compilation failed.
    pause
    exit /b %ERRORLEVEL%
)

echo [2/3] Compiling Control Center UI (TyrexControlCenter.exe)...
pyinstaller --clean TyrexControlCenter.spec
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] TyrexControlCenter UI compilation failed.
    pause
    exit /b %ERRORLEVEL%
)

echo [3/3] Packaging single-file Setup with Inno Setup...
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "TyrexTallySync_Installer.iss"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Inno Setup packaging failed.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo =======================================================
echo SUCCESS! Enterprise Installer created at:
echo %~dp0..\release\TyrexTallySync_Setup.exe
echo =======================================================
pause
