; Inno Setup 6 - installateur AgriERP Desktop
; Compile par build_windows.bat (ISCC /DAppVersion=x.y.z[-demo] /DAppVersionNum=x.y.z
; /DAppEnv=dev|recette|production /DNomInstallateur=... installer\agrierp.iss).
;
; La base locale (Drift/SQLite) vit dans le profil Windows de l'utilisateur
; (path_provider : %APPDATA%\bj.olouwachegoun\agrierp, CompanyName et
; ProductName de Runner.rc), JAMAIS dans le dossier d'installation : une MISE A
; JOUR ne touche pas aux ventes et fiches non synchronisees.
;
; Ticket DES-1 (decision du client du 27/10/2026) : la DESINSTALLATION supprime
; aussi la base locale et ses journaux ([UninstallDelete] + [Code]). Les saisies
; faites hors ligne et pas encore envoyees sont PERDUES : le desinstallateur le
; dit et demande confirmation (InitializeUninstall) avant de retirer quoi que ce
; soit. Le coffre du systeme (PIN, mots de passe en attente : Gestionnaire
; d'identification Windows) n'est pas touche ; un PIN orphelin est sans effet.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
; Ticket S-T8 : partie numerique x.y.z (VersionInfoVersion n'accepte pas -demo),
; environnement de compilation et nom de l'installateur, passes par build_windows.bat.
#ifndef AppVersionNum
  #define AppVersionNum AppVersion
#endif
#ifndef AppEnv
  #define AppEnv "production"
#endif
#ifndef NomInstallateur
  #define NomInstallateur "AgriERP-Setup-" + AppVersion
#endif

; Ticket S-T8 : une version demo (suffixe -demo) n'est JAMAIS construite pour la
; production, meme par un appel direct a ISCC qui contournerait build_windows.bat.
#if (Pos("-demo", LowerCase(AppVersion)) > 0) && (AppEnv == "production")
  #error Version demo : construction refusee pour la production (voir build_windows.bat --env).
#endif

#if AppEnv == "production"
  #define LibelleEnv ""
#else
  #define LibelleEnv " (" + AppEnv + ")"
#endif

[Setup]
; Meme AppId pour tous les environnements : un seul AgriERP par poste Windows.
AppId={{69B3D13F-4283-4B8E-ABD1-456845FC5182}
AppName=AgriERP
AppVersion={#AppVersion}
AppVerName=AgriERP {#AppVersion}{#LibelleEnv}
VersionInfoVersion={#AppVersionNum}
AppPublisher=Dr MASSENON Rhodes - Ferme Ecole OLOUWACHEGOUN
AppPublisherURL=https://agrierp.fermeolouwachegoun.com
DefaultDirName={autopf}\AgriERP
DefaultGroupName=AgriERP
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename={#NomInstallateur}
; Ticket ENV1 : l'icone est le logo de la ferme (outils\generer_icone.py). Assistant d'installation, programme
; desinstallable (Parametres Windows) et raccourcis la montrent ; agrierp.exe la porte aussi (Runner.rc).
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
Name: "{group}\AgriERP"; Filename: "{app}\agrierp.exe"; IconFilename: "{app}\agrierp.exe"
Name: "{group}\{cm:UninstallProgram,AgriERP}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\AgriERP"; Filename: "{app}\agrierp.exe"; IconFilename: "{app}\agrierp.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\agrierp.exe"; Description: "{cm:LaunchProgram,AgriERP}"; Flags: nowait postinstall skipifsilent

; Ticket DES-1 : la base locale, demarrage.log et les justificatifs copies en local partent avec le programme.
[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\bj.olouwachegoun\agrierp"
Type: dirifempty; Name: "{userappdata}\bj.olouwachegoun"

[Code]
// Ticket DES-1 : la desinstallation supprime la base locale ; ce qui n'est pas parti au serveur est perdu.
// L'utilisateur le lit et confirme ; « Non » annule la desinstallation entiere.
function InitializeUninstall(): Boolean;
begin
  Result := MsgBox(
    'La desinstallation d''AgriERP supprime aussi la base locale de ce poste' + #13#10 +
    '(' + ExpandConstant('{userappdata}\bj.olouwachegoun\agrierp') + ').' + #13#10#13#10 +
    'Les ventes, fiches, depenses et autres saisies faites HORS LIGNE et pas encore' + #13#10 +
    'synchronisees seront PERDUES. Synchronisez le poste avant de continuer.' + #13#10#13#10 +
    'Desinstaller AgriERP et supprimer ses donnees locales ?',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
end;
