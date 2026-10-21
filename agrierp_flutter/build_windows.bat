@echo off
rem ============================================================================
rem  build_windows.bat - AgriERP Desktop (poste Windows offline-first)
rem
rem  Compile l'application Flutter en mode release puis genere l'installateur
rem  AgriERP-Setup-<version>.exe avec Inno Setup.
rem
rem  Prerequis sur le poste de compilation :
rem    - Flutter SDK (stable, Dart >= 3.12.2) dans le PATH
rem    - Visual Studio 2022 avec la charge "Developpement Desktop en C++"
rem    - Inno Setup 6 (ISCC.exe) : https://jrsoftware.org/isdl.php
rem
rem  Utilisation :
rem    build_windows.bat              chaine complete (analyse + tests + build + installateur)
rem    build_windows.bat --sans-tests saute flutter test (deconseille avant une livraison)
rem    build_windows.bat --sans-installateur  produit seulement le dossier Release
rem                                   (sans ce drapeau, Inno Setup absent = ECHEC)
rem    build_windows.bat --env recette    environnement : dev, recette ou production
rem                                   (defaut : production ; aussi --env=recette)
rem
rem  Ticket S-T8 - ENVIRONNEMENT ET VERSION DEMO
rem    - L'environnement fixe l'adresse du serveur par defaut du poste
rem      (lib/core/config/environnement.dart), passee a la compilation par
rem      --dart-define=AGRIERP_ENV=<env>. Un environnement inconnu est REFUSE.
rem    - Une VERSION DEMO est une version de pubspec.yaml qui porte le suffixe
rem      -demo (1.2.0-demo+3, 1.2.0-demo.2+3). Elle est REFUSEE en production :
rem      un installateur de demonstration remis a la ferme enverrait ses saisies
rem      de demonstration au vrai serveur. Tout autre suffixe est invalide.
rem    - Hors production, le nom de l'installateur porte l'environnement :
rem      AgriERP-Setup-<version>-<env>.exe.
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "SANS_TESTS=0"
set "SANS_INSTALLATEUR=0"
set "ENVIRONNEMENT=production"

rem --- Arguments : shift decale aussi le parametre 0, d ou le cd plus haut ------
:arguments
if "%~1"=="" goto :arguments_lus
if /i "%~1"=="--sans-tests" (
  set "SANS_TESTS=1"
  shift
  goto :arguments
)
if /i "%~1"=="--sans-installateur" (
  set "SANS_INSTALLATEUR=1"
  shift
  goto :arguments
)
rem  cmd coupe aussi sur "=" : --env=recette arrive comme --env puis recette.
if /i "%~1"=="--env" (
  if "%~2"=="" (
    echo [ERREUR] --env attend une valeur : dev, recette ou production.
    exit /b 1
  )
  set "ENVIRONNEMENT=%~2"
  shift
  shift
  goto :arguments
)
echo [ERREUR] Argument inconnu : %~1
echo          Arguments permis : --sans-tests, --sans-installateur, --env dev^|recette^|production
exit /b 1
:arguments_lus

rem --- Environnement : exactement les codes de lib/core/config/environnement.dart
set "ENV_RETENU="
for %%e in (dev recette production) do (
  if /i "!ENVIRONNEMENT!"=="%%e" set "ENV_RETENU=%%e"
)
if not defined ENV_RETENU (
  echo [ERREUR] Environnement "%ENVIRONNEMENT%" inconnu : dev, recette ou production.
  exit /b 1
)
set "ENVIRONNEMENT=%ENV_RETENU%"

rem --- Version lue dans pubspec.yaml (ligne "version: 1.0.0+1") ---------------
set "VERSION="
for /f "tokens=2 delims=: " %%v in ('findstr /b /c:"version:" pubspec.yaml') do set "VERSION=%%v"
if not defined VERSION (
  echo [ERREUR] Version introuvable dans pubspec.yaml.
  exit /b 1
)
for /f "tokens=1 delims=+" %%v in ("%VERSION%") do set "VERSION_COURTE=%%v"

rem  Ticket S-T8 : x.y.z, eventuellement suivi de -demo ou -demo.N (version demo).
set "VERSION_NUM="
set "SUFFIXE="
for /f "tokens=1,* delims=-" %%a in ("%VERSION_COURTE%") do (
  set "VERSION_NUM=%%a"
  set "SUFFIXE=%%b"
)
rem  Ticket A7 / D2 : une version mal formee donnerait un installateur au nom faux.
echo %VERSION_NUM%| findstr /r /x "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" >nul || (
  echo [ERREUR] Version "%VERSION_COURTE%" invalide dans pubspec.yaml : attendu x.y.z+n ou x.y.z-demo+n.
  exit /b 1
)
rem  ATTENTION : aucun tube dans un bloc entre parentheses ici, car le cote gauche d un tube
rem  s execute dans un cmd fils SANS expansion retardee : une variable retardee y resterait telle quelle.
set "DEMO=0"
set "DEBUT="
set "RESTE="
if not defined SUFFIXE goto :suffixe_lu
set "DEBUT=%SUFFIXE:~0,4%"
set "RESTE=%SUFFIXE:~4%"
if /i not "%DEBUT%"=="demo" goto :version_invalide
if not defined RESTE goto :suffixe_demo
echo %RESTE%| findstr /r /x "\.[0-9][0-9]*" >nul || goto :version_invalide
:suffixe_demo
set "DEMO=1"
:suffixe_lu

rem  Ticket S-T8 : JAMAIS de version demo en production.
if "%DEMO%"=="1" if /i "%ENVIRONNEMENT%"=="production" (
  echo [ERREUR] Version demo "%VERSION_COURTE%" : construction refusee pour la production.
  echo          Retirez le suffixe -demo de pubspec.yaml, ou construisez avec --env recette ou --env dev.
  exit /b 1
)

set "NOM_INSTALLATEUR=AgriERP-Setup-%VERSION_COURTE%"
if /i not "%ENVIRONNEMENT%"=="production" set "NOM_INSTALLATEUR=%NOM_INSTALLATEUR%-%ENVIRONNEMENT%"

echo === AgriERP Desktop %VERSION% - environnement %ENVIRONNEMENT% ===

where flutter >nul 2>nul || (echo [ERREUR] Flutter introuvable dans le PATH. & exit /b 1)

rem  Ticket ENV1 : l'icone de l'application (exe, fenetre, barre des taches, raccourcis, installateur) est le logo
rem  de la ferme, dans windows\runner\resources\app_icon.ico (Runner.rc l'embarque dans agrierp.exe, agrierp.iss
rem  s'en sert pour l'assistant). Sans lui, la compilation echoue plus loin sur un message de ressource obscur.
rem  Pour le regenerer depuis assets\images\logo.png : py outils\generer_icone.py
if not exist "windows\runner\resources\app_icon.ico" (
  echo [ERREUR] windows\runner\resources\app_icon.ico absent : lancez  py outils\generer_icone.py
  exit /b 1
)

echo.
echo [1/6] Dependances...
call flutter pub get || goto :echec

echo.
echo [2/6] Generation du code Drift...
call dart run build_runner build --delete-conflicting-outputs || goto :echec

echo.
echo [3/6] Analyse statique (doit finir par "No issues found!")...
call flutter analyze || goto :echec

if "%SANS_TESTS%"=="1" (
  echo.
  echo [4/6] Tests SAUTES ^(--sans-tests^).
) else (
  echo.
  echo [4/6] Tests...
  call flutter test --concurrency=2 || goto :echec
)

echo.
echo [5/6] Compilation release ^(environnement %ENVIRONNEMENT%^)...
call flutter build windows --release --dart-define=AGRIERP_ENV=%ENVIRONNEMENT% || goto :echec
set "SORTIE=build\windows\x64\runner\Release"
if not exist "%SORTIE%\agrierp.exe" (
  echo [ERREUR] %SORTIE%\agrierp.exe absent apres la compilation.
  goto :echec
)

rem --- Runtime Visual C++ : livre a cote de l'exe --------------------------------
rem  Un poste de ferme fraichement installe n'a pas forcement le redistribuable
rem  VC++ : sans ces DLL, agrierp.exe ne demarre pas, sans message utile.
rem  Ticket A7 / D2 : une DLL absente est une ERREUR (un avertissement laissait livrer
rem  un installateur dont l'application ne demarre pas sur un poste neuf).
for %%d in (msvcp140.dll vcruntime140.dll vcruntime140_1.dll) do (
  if exist "%SystemRoot%\System32\%%d" (
    copy /y "%SystemRoot%\System32\%%d" "%SORTIE%\" >nul || goto :echec
  ) else (
    echo [ERREUR] %%d introuvable dans System32 : installez le redistribuable Visual C++ 2015-2022 x64.
    goto :echec
  )
)

echo.
echo [6/6] Installateur...
set "ISCC="
for %%p in ("%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" "%ProgramFiles%\Inno Setup 6\ISCC.exe") do (
  if exist %%p set "ISCC=%%~p"
)
if not defined ISCC (
  where iscc >nul 2>nul && set "ISCC=iscc"
)
if not defined ISCC (
  rem  Ticket A7 / D2 : sortir en SUCCES sans installateur laissait croire a une livraison prete.
  if "%SANS_INSTALLATEUR%"=="1" (
    echo [INFO] --sans-installateur : seul le dossier %SORTIE% est produit.
    exit /b 0
  )
  echo [ERREUR] Inno Setup 6 introuvable ^(ISCC.exe^) : https://jrsoftware.org/isdl.php
  echo          Installez-le, ou relancez avec --sans-installateur pour le seul dossier Release.
  goto :echec
)
"%ISCC%" /Q /DAppVersion=%VERSION_COURTE% /DAppVersionNum=%VERSION_NUM% /DAppEnv=%ENVIRONNEMENT% /DNomInstallateur=%NOM_INSTALLATEUR% installer\agrierp.iss || goto :echec
if not exist "installer\Output\%NOM_INSTALLATEUR%.exe" (
  echo [ERREUR] installer\Output\%NOM_INSTALLATEUR%.exe absent apres Inno Setup.
  goto :echec
)

echo.
echo === Termine : installer\Output\%NOM_INSTALLATEUR%.exe ===
exit /b 0

:version_invalide
echo [ERREUR] Version "%VERSION_COURTE%" invalide dans pubspec.yaml : seul le suffixe -demo ou -demo.N est permis.
exit /b 1

:echec
echo.
echo [ECHEC] La construction s'est arretee : corrigez l'erreur ci-dessus puis relancez.
exit /b 1
