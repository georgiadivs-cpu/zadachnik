; Inno Setup script for the personal Windows build.
; Build on Windows: .\scripts\release\build-windows.ps1
; The installer is unsigned; SmartScreen may warn. User data is not removed
; on uninstall.

#define MyAppName "Ежедневник"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "Zadachnik"
#define MyAppExeName "zadachnik_client.exe"
#define MyAppId "{{8F1D0A9C-3B7E-4C2A-9D6F-2A1B7C9E4F01}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Zadachnik
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist\windows
OutputBaseFilename=zadachnik-{#MyAppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
SetupLogging=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
; SignTool is intentionally not configured: no paid Windows certificate.
; Add SignTool configuration later if SmartScreen warnings become a problem.

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительно:"; Flags: unchecked

[Files]
Source: "..\..\apps\client\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Удалить {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Запустить {#MyAppName}"; Flags: nowait postinstall skipifsilent

; Пользовательские данные (SQLite, вложения, настройки) не удаляются.
