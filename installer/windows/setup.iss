; LifeOS TV - Inno Setup script. The release workflow compiles it with the
; version from pubspec.yaml:
;   iscc /DAppVersion=1.2.3 installer\windows\setup.iss
; and gets build\installer\LifeOS-TV-<version>-Windows-x64-Setup.exe.

#define MyAppName "LifeOS TV"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define MyAppPublisher "LifeOS"
#define MyAppURL "https://lifeos.com.tr/iptv"
#define MyAppExeName "lifeostv.exe"

[Setup]
AppId={{6F3C2A1E-8B7D-4C59-9E1A-2D4F6B8C0A13}
AppName={#MyAppName}
AppVersion={#AppVersion}
VersionInfoVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes
OutputDir=..\..\build\installer
OutputBaseFilename=LifeOS-TV-{#AppVersion}-Windows-x64-Setup
Compression=lzma2/ultra64
SolidCompression=yes
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Device-to-device sync listens on TCP 48741 and UDP 48742. Windows marks new
; Wi-Fi networks "Public" and its first-run prompt only allows "Private", so
; peers often could not reach this PC. An all-users (admin) install allows the app
; from the local subnet only; a per-user install falls back to that prompt.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#MyAppName} LAN sync"""; Flags: runhidden; Check: IsAdminInstallMode
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#MyAppName} LAN sync"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes remoteip=localsubnet profile=any"; Flags: runhidden; Check: IsAdminInstallMode
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#MyAppName} LAN sync"""; Flags: runhidden; RunOnceId: "LanSyncFirewall"; Check: IsAdminInstallMode
