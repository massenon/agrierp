; Inno Setup 6 - installateur AgriERP Desktop
; Compile par build_windows.bat (ISCC /DAppVersion=x.y.z installer\agrierp.iss).
;
; La base locale (Drift/SQLite) vit dans le profil Windows de l'utilisateur
; (path_provider), JAMAIS dans le dossier d'installation : desinstaller ou
; mettre a jour l'application ne touche pas aux ventes et fiches non
; synchronisees.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{69B3D13F-4283-4B8E-ABD1-456845FC5182}
AppName=AgriERP
AppVersion={#AppVersion}
AppVerName=AgriERP {#AppVersion}
AppPublisher=Dr MASSENON Rhodes - Ferme Ecole OLOUWACHEGOUN
AppPublisherURL=https://agrierp.fermeolouwachegoun.com
DefaultDirName={autopf}\AgriERP
DefaultGroupName=AgriERP
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=AgriERP-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\agrierp.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\AgriERP"; Filename: "{app}\agrierp.exe"
Name: "{group}\{cm:UninstallProgram,AgriERP}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\AgriERP"; Filename: "{app}\agrierp.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\agrierp.exe"; Description: "{cm:LaunchProgram,AgriERP}"; Flags: nowait postinstall skipifsilent
