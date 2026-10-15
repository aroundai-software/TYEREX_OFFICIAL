; Script generated for TyreX Tally Sync Enterprise Installer
#define MyAppName "Tyrex Tally Sync"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "TyreX"
#define MyDaemonExe "TyrexTallySync.exe"
#define MyGuiExe "TyrexControlCenter.exe"

[Setup]
; App Identity
AppId={{C82F2C58-0D2E-4D78-9B2F-9C1D9E74A251}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={userappdata}\TyrexTallySync
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

; Output Configuration
OutputDir=..\release
OutputBaseFilename=TyrexTallySync_Setup
Compression=lzma2/ultra64
SolidCompression=yes
SetupIconFile=app_icon.ico

; User-level install: No UAC / Admin rights required
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "autostart"; Description: "Automatically start background sync engine when Windows logs on"; GroupDescription: "Startup Options:"
Name: "desktopicon"; Description: "Create a desktop shortcut for TyreX Control Center"; GroupDescription: "Additional Shortcuts:"

[Files]
Source: "dist\{#MyDaemonExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\{#MyGuiExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "tally_sync.env"; DestDir: "{app}"; Flags: ignoreversion
Source: "app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\TyreX Control Center"; Filename: "{app}\{#MyGuiExe}"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\View Sync Log"; Filename: "{app}\tally_sync.log"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\TyreX Control Center"; Filename: "{app}\{#MyGuiExe}"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon

[Registry]
; Auto-start background daemon with Windows in --watch mode
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "TyrexTallySync"; ValueData: """{app}\{#MyDaemonExe}"" --watch"; Tasks: autostart; Flags: uninsdeletevalue

[Run]
; Launch background sync daemon immediately after installation
Filename: "{app}\{#MyDaemonExe}"; Parameters: "--watch"; Flags: nowait runhidden
; Open Control Center for initial config review
Filename: "{app}\{#MyGuiExe}"; Description: "Open TyreX Control Center"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Gracefully terminate running instances on uninstall
Filename: "taskkill.exe"; Parameters: "/F /IM {#MyDaemonExe}"; Flags: runhidden
Filename: "taskkill.exe"; Parameters: "/F /IM {#MyGuiExe}"; Flags: runhidden
