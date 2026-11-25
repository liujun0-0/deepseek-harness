@echo off
if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh.ps1" -Menu
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh.ps1" %*
exit /b %errorlevel%
