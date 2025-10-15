@echo off
REM Build and package MerkleKV-Mobile Windows app as a single SFX EXE using the PowerShell script.
setlocal enabledelayedexpansion

REM Determine repo root (this file is scripts\windows\make-sfx.cmd)
set SCRIPT_DIR=%~dp0
for %%I in ("%SCRIPT_DIR%..\..") do set REPO_ROOT=%%~fI

REM Default output can be overridden via first argument
set OUTPUT=%~1
if "%OUTPUT%"=="" set OUTPUT=%REPO_ROOT%\apps\flutter_demo\releases\MerkleKV-Mobile.exe

REM Forward optional -SevenZipSfx path via second argument
set SFXPATH=%~2

echo Repo root: %REPO_ROOT%
echo Output:    %OUTPUT%

set PS_SCRIPT=%REPO_ROOT%\scripts\windows\make-sfx.ps1
if not exist "%PS_SCRIPT%" (
  echo PowerShell script not found: %PS_SCRIPT%
  exit /b 1
)

set PS_ARGS=-Output "%OUTPUT%"
if not "%SFXPATH%"=="" set PS_ARGS=%PS_ARGS% -SevenZipSfx "%SFXPATH%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %PS_ARGS%
if errorlevel 1 (
  echo Packaging failed.
  exit /b 1
)

echo SFX created at: %OUTPUT%
exit /b 0
