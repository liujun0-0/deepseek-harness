@echo off
if "%~1"=="" (
  echo Actions: start stop restart status logs url install build rebuild update autostart unautostart
  set /p "action=Action: "
  goto interactive
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh.ps1" %*
exit /b %errorlevel%
:interactive
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh.ps1" %action%
pause
