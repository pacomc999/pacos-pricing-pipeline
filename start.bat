@echo off
REM One-click launcher for Paco's Pragmatic Pricing Pipeline.
REM Double-click this file. If R is not installed it will be downloaded and
REM installed automatically, then the dashboard opens in your browser.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1"
pause
