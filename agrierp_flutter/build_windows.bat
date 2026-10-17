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
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "SANS_TESTS=0"
set "SANS_INSTALLATEUR=0"
for %%a in (%*) do (
  if /i "%%~a"=="--sans-tests" set "SANS_TESTS=1"
  if /i "%%~a"=="--sans-installateur" set "SANS_INSTALLATEUR=1"
)

rem --- Version lue dans pubspec.yaml (ligne "version: 1.0.0+1") ---------------
set "VERSION="
for /f "tokens=2 delims=: " %%v in ('findstr /b /c:"version:" pubspec.yaml') do set "VERSION=%%v"
if not defined VERSION (
  echo [ERREUR] Version introuvable dans pubspec.yaml.
  exit /b 1
)
for /f "tokens=1 delims=+" %%v in ("%VERSION%") do set "VERSION_COURTE=%%v"
rem  Ticket A7 / D2 : une version mal formee donnerait un installateur au nom faux.
echo %VERSION_COURTE%| findstr /r /x "[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" >nul || (
  echo [ERREUR] Version "%VERSION_COURTE%" invalide dans pubspec.yaml : attendu x.y.z+n.
  exit /b 1
)
echo === AgriERP Desktop %VERSION% ===

where flutter >nul 2>nul || (echo [ERREUR] Flutter introuvable dans le PATH. & exit /b 1)

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
echo [5/6] Compilation release...
call flutter build windows --release || goto :echec
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
"%ISCC%" /Q /DAppVersion=%VERSION_COURTE% installer\agrierp.iss || goto :echec
if not exist "installer\Output\AgriERP-Setup-%VERSION_COURTE%.exe" (
  echo [ERREUR] installer\Output\AgriERP-Setup-%VERSION_COURTE%.exe absent apres Inno Setup.
  goto :echec
)

echo.
echo === Termine : installer\Output\AgriERP-Setup-%VERSION_COURTE%.exe ===
exit /b 0

:echec
echo.
echo [ECHEC] La construction s'est arretee : corrigez l'erreur ci-dessus puis relancez.
exit /b 1
