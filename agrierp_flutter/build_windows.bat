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
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "SANS_TESTS=0"
if /i "%~1"=="--sans-tests" set "SANS_TESTS=1"

rem --- Version lue dans pubspec.yaml (ligne "version: 1.0.0+1") ---------------
set "VERSION="
for /f "tokens=2 delims=: " %%v in ('findstr /b /c:"version:" pubspec.yaml') do set "VERSION=%%v"
if not defined VERSION (
  echo [ERREUR] Version introuvable dans pubspec.yaml.
  exit /b 1
)
for /f "tokens=1 delims=+" %%v in ("%VERSION%") do set "VERSION_COURTE=%%v"
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
for %%d in (msvcp140.dll vcruntime140.dll vcruntime140_1.dll) do (
  if exist "%SystemRoot%\System32\%%d" (
    copy /y "%SystemRoot%\System32\%%d" "%SORTIE%\" >nul
  ) else (
    echo [AVERTISSEMENT] %%d introuvable dans System32 : l'installateur ne l'embarquera pas.
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
  echo [AVERTISSEMENT] Inno Setup 6 introuvable : seul le dossier %SORTIE% est produit.
  echo                 Installez-le puis relancez pour obtenir AgriERP-Setup-%VERSION_COURTE%.exe.
  exit /b 0
)
"%ISCC%" /Q /DAppVersion=%VERSION_COURTE% installer\agrierp.iss || goto :echec

echo.
echo === Termine : installer\Output\AgriERP-Setup-%VERSION_COURTE%.exe ===
exit /b 0

:echec
echo.
echo [ECHEC] La construction s'est arretee : corrigez l'erreur ci-dessus puis relancez.
exit /b 1
