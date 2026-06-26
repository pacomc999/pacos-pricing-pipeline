@echo off
REM One-click launcher for Paco's Pragmatic Pricing Pipeline.
REM Pure batch (no PowerShell) so it works on locked-down company machines.
REM It finds an existing R install (any version, any location) via the Windows
REM registry, the PATH, and the usual folders, then opens the dashboard.

setlocal enableextensions
cd /d "%~dp0"
set "RSCRIPT="

REM 0) Manual override: paste a full path to Rscript.exe into R_PATH.txt.
if exist "R_PATH.txt" set /p RSCRIPT=<R_PATH.txt
if defined RSCRIPT if not exist "%RSCRIPT%" set "RSCRIPT="

REM 1) Rscript on the PATH.
if not defined RSCRIPT for /f "delims=" %%i in ('where Rscript 2^>nul') do (
  if not defined RSCRIPT set "RSCRIPT=%%i"
)

REM 2) Windows registry (R records its install path here, wherever it lives).
if not defined RSCRIPT call :fromreg "HKLM\SOFTWARE\R-core\R64"
if not defined RSCRIPT call :fromreg "HKLM\SOFTWARE\R-core\R"
if not defined RSCRIPT call :fromreg "HKCU\SOFTWARE\R-core\R64"
if not defined RSCRIPT call :fromreg "HKCU\SOFTWARE\R-core\R"

REM 3) Common install folders, newest version first.
if not defined RSCRIPT call :fromdir "%ProgramFiles%\R"
if not defined RSCRIPT call :fromdir "%ProgramFiles(x86)%\R"
if not defined RSCRIPT call :fromdir "%LOCALAPPDATA%\Programs\R"

if not defined RSCRIPT goto :notfound

echo Using R at: %RSCRIPT%
echo Checking dependencies (the first run can take a few minutes)...
"%RSCRIPT%" install_deps.R
if not exist "example_input.xlsx" "%RSCRIPT%" make_example.R

echo.
echo Starting Paco's Pragmatic Pricing Pipeline.
echo A browser tab will open. Keep this window open while you use the tool;
echo close it to stop the dashboard.
"%RSCRIPT%" -e "shiny::runApp('.', launch.browser = TRUE)"
goto :end

:fromreg
REM %1 = registry key. Reads InstallPath and checks for Rscript.exe under it.
for /f "tokens=2,*" %%a in ('reg query %1 /v InstallPath 2^>nul ^| findstr /i "InstallPath"') do (
  if exist "%%b\bin\Rscript.exe" set "RSCRIPT=%%b\bin\Rscript.exe"
)
goto :eof

:fromdir
REM %~1 = a folder that may contain R-x.y.z subfolders. Picks the newest.
if not exist "%~1" goto :eof
for /f "delims=" %%d in ('dir /b /ad /o-n "%~1\R-*" 2^>nul') do (
  if not defined RSCRIPT if exist "%~1\%%d\bin\Rscript.exe" set "RSCRIPT=%~1\%%d\bin\Rscript.exe"
)
goto :eof

:notfound
echo.
echo Could not find R on this computer.
echo.
echo Fix it in one of these ways:
echo   - Install R from https://cran.r-project.org (or ask your IT team), or
echo   - If R is installed in an unusual place, create a file named R_PATH.txt
echo     in this folder containing the full path to Rscript.exe, for example:
echo       D:\Tools\R\R-4.5.2\bin\Rscript.exe
echo.

:end
pause
