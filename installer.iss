[Setup]
AppName=TyreX
AppVersion=1.0.0
DefaultDirName={autopf}\TyreX
DefaultGroupName=TyreX
OutputDir=d:\TyreX\build\windows\x64\installer
OutputBaseFilename=TyreX_Setup
SetupIconFile=d:\TyreX\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "d:\TyreX\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\TyreX"; Filename: "{app}\autofix_app.exe"
Name: "{autodesktop}\TyreX"; Filename: "{app}\autofix_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\autofix_app.exe"; Description: "{cm:LaunchProgram,TyreX}"; Flags: nowait postinstall skipifsilent
