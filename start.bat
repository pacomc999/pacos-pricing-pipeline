@echo off
REM One-click launcher for Paco's Pragmatic Pricing Pipeline.
REM Double-click this file to install dependencies (first run only) and open
REM the dashboard in your browser.

cd /d "%~dp0"

REM Locate Rscript: prefer the PATH, otherwise the newest R under Program Files.
set "RSCRIPT="
where Rscript >nul 2>nul && set "RSCRIPT=Rscript"
if not defined RSCRIPT (
  for /f "delims=" %%i in ('dir /b /ad /o-n "C:\Program Files\R\R-*" 2^>nul') do (
    if not defined RSCRIPT set "RSCRIPT=C:\Program Files\R\%%i\bin\Rscript.exe"
  )
)
if not defined RSCRIPT (
  echo.
  echo Could not find R on this computer.
  echo Please install R from https://cran.r-project.org and run this again.
  echo.
  pause
  exit /b 1
)

echo Checking dependencies (the first run can take a few minutes)...
"%RSCRIPT%" install_deps.R
if not exist "example_input.xlsx" "%RSCRIPT%" make_example.R

echo.
echo Starting Paco's Pragmatic Pricing Pipeline...
echo A browser tab will open. Keep this window open while you use the tool.
echo Close this window to stop the dashboard.
echo.
"%RSCRIPT%" -e "shiny::runApp('.', launch.browser = TRUE)"
pause
