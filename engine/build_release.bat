@echo off
REM Double click version of build_release_internal.ps1, for when you would
REM rather not type a PowerShell command. Asks for a version number, builds
REM the zip, then opens the folder and the GitHub page so publishing is just
REM clicking. This is the file to double click, not the _internal.ps1 one.

setlocal enableextensions
cd /d "%~dp0"

set /p VERSION="What version number is this release? (example: 1.1.0) "
if "%VERSION%"=="" (
  echo No version entered, stopping.
  pause
  exit /b 1
)

echo.
echo Building the release zip for version %VERSION% ...
powershell -NoProfile -ExecutionPolicy Bypass -File "build_release_internal.ps1" -Version "%VERSION%"
if errorlevel 1 (
  echo.
  echo Something went wrong building the zip. Scroll up to see the error message.
  pause
  exit /b 1
)

echo.
echo Opening the dist folder and the GitHub release page...
start "" "..\dist"
start "" "https://github.com/pacomc999/pacos-pricing-pipeline/releases/new?tag=v%VERSION%&title=v%VERSION%"

echo.
echo Now in the browser page that just opened:
echo   1. Write a short note about what changed.
echo   2. Drag the zip file from the dist folder into the box that says "Attach binaries".
echo   3. Click "Publish release".
pause
