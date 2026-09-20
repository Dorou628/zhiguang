@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch.ps1" -Action logs
if errorlevel 1 (
  pause
  exit /b 1
)
pause
