; Inno Setup 6 - installateur AgriERP Desktop
; Compile par build_windows.bat (ISCC /DAppVersion=x.y.z[-demo] /DAppVersionNum=x.y.z
; /DAppEnv=dev|recette|production /DNomInstallateur=... installer\agrierp.iss).
;
; La base locale (Drift/SQLite) vit dans le profil Windows de l'utilisateur
; (%APPDATA%\OLOUWACHEGOUN\donnees, DossierDonnees ; CompanyName et
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
AppName=LogiAgriERP
AppVersion={#AppVersion}
AppVerName=LogiAgriERP {#AppVersion}{#LibelleEnv}
VersionInfoVersion={#AppVersionNum}
AppPublisher=Dr MASSENON Rhodes - Ferme Ecole OLOUWACHEGOUN
AppPublisherURL=https://agrierp.fermeolouwachegoun.com
DefaultDirName={autopf}\AgriERP
DefaultGroupName=LogiAgriERP
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
Name: "{group}\LogiAgriERP"; Filename: "{app}\agrierp.exe"; IconFilename: "{app}\agrierp.exe"
Name: "{group}\{cm:UninstallProgram,LogiAgriERP}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\LogiAgriERP"; Filename: "{app}\agrierp.exe"; IconFilename: "{app}\agrierp.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\agrierp.exe"; Description: "{cm:LaunchProgram,LogiAgriERP}"; Flags: nowait postinstall skipifsilent

; Tickets DES-1 / DES-2 : la desinstallation retire TOUT ce que le poste a pose hors du dossier d'installation :
; la base locale, demarrage.log, le logo, les sauvegardes (dossier des donnees), les archives et exports PDF/Excel
; (Documents\AgriERP) et les justificatifs copies (Documents\agrierp_justificatifs). Une SAUVEGARDE AUTOMATIQUE est proposee avant
; (Documents\AgriERP-Sauvegarde-AAAA-MM-JJ_HHMM, jamais supprimee par la desinstallation).
[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\OLOUWACHEGOUN\donnees"
Type: dirifempty; Name: "{userappdata}\OLOUWACHEGOUN"
Type: filesandordirs; Name: "{userdocs}\AgriERP"
Type: filesandordirs; Name: "{userdocs}\agrierp_justificatifs"

[Code]
// Copie un dossier (sous-dossiers compris) ; un dossier source absent n'est pas une erreur (rien a sauvegarder).
function CopierDossier(Source, Cible: String): Boolean;
var
  Code: Integer;
begin
  if not DirExists(Source) then
  begin
    Result := True;
    Exit;
  end;
  Result := Exec(ExpandConstant('{cmd}'),
    '/C xcopy "' + Source + '" "' + Cible + '\" /E /I /H /Y /Q', '', SW_HIDE, ewWaitUntilTerminated, Code)
    and (Code = 0);
end;

// Sauvegarde automatique : donnees du poste, archives/exports et justificatifs, dans un dossier horodate de Documents.
function SauvegarderAvantSuppression(var Dossier: String): Boolean;
var
  Code: Integer;
begin
  // Le poste est ferme d'abord : une base ouverte ne se copie pas de facon coherente.
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM agrierp.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);

  Dossier := ExpandConstant('{userdocs}\AgriERP-Sauvegarde-') + GetDateTimeString('yyyy/mm/dd_hhnn', '-', #0);
  Result := ForceDirectories(Dossier)
    and CopierDossier(ExpandConstant('{userappdata}\OLOUWACHEGOUN\donnees'), Dossier + '\donnees-du-poste')
    and CopierDossier(ExpandConstant('{userdocs}\AgriERP'), Dossier + '\archives-et-exports')
    and CopierDossier(ExpandConstant('{userdocs}\agrierp_justificatifs'), Dossier + '\justificatifs');
end;

// Avertissement, choix Oui / Non, puis sauvegarde automatique si l'utilisateur la veut. « Non » annule la desinstallation.
function InitializeUninstall(): Boolean;
var
  Dossier: String;
begin
  Result := MsgBox(
    'ATTENTION - la desinstallation d''LogiAgriERP supprime DEFINITIVEMENT, sur ce poste :' + #13#10#13#10 +
    '  - la base locale et les journaux (' + ExpandConstant('{userappdata}\OLOUWACHEGOUN\donnees') + ')' + #13#10 +
    '  - les archives et documents exportes (' + ExpandConstant('{userdocs}\AgriERP') + ')' + #13#10 +
    '  - les justificatifs et recus (' + ExpandConstant('{userdocs}\agrierp_justificatifs') + ')' + #13#10#13#10 +
    'Les ventes, fiches, depenses et autres saisies faites HORS LIGNE et pas encore' + #13#10 +
    'synchronisees seront PERDUES. Synchronisez le poste avant de continuer.' + #13#10#13#10 +
    'Continuer la desinstallation ?',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  if not Result then
    Exit;

  if MsgBox(
    'Voulez-vous faire une SAUVEGARDE AUTOMATIQUE avant la suppression ?' + #13#10#13#10 +
    'Elle sera enregistree dans votre dossier Documents (AgriERP-Sauvegarde-...) et ne sera pas supprimee.',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON1) = IDYES then
  begin
    if SauvegarderAvantSuppression(Dossier) then
      MsgBox('Sauvegarde terminee :' + #13#10 + Dossier, mbInformation, MB_OK)
    else
      Result := MsgBox(
        'La sauvegarde a echoue (espace disque ou acces refuse).' + #13#10#13#10 +
        'Desinstaller QUAND MEME et supprimer les donnees de ce poste ?',
        mbError, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  end;
end;
