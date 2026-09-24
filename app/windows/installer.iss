; Windows installer for the Flutter build. The release workflow runs:
;   iscc /DAppVersion=2.<run> /DBuildDir=<Release folder> app\windows\installer.iss
; Installs per user (no administrator prompt). A silent run (the in-app update) closes the
; running app, replaces it and starts the new version.

#ifndef AppVersion
  #define AppVersion "2.0"
#endif
#ifndef BuildDir
  #define BuildDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6F3D2A8E-5C1B-4E7A-9D42-8B1F0C6E3A57}
AppName=매매 시그널 알림
AppVersion={#AppVersion}
AppPublisher=Inho
DefaultDirName={localappdata}\Programs\OscAlert
DefaultGroupName=매매 시그널 알림
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=osc-alert-setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\oscalert.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 바로가기 만들기"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\매매 시그널 알림"; Filename: "{app}\oscalert.exe"
Name: "{autodesktop}\매매 시그널 알림"; Filename: "{app}\oscalert.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\oscalert.exe"; Description: "매매 시그널 알림 실행"; Flags: nowait postinstall
