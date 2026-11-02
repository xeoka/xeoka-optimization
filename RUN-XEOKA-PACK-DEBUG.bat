@echo off
fltmc >nul 2>&1 || (
  echo Requesting administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
rem Debug launcher: visible console, errors stay on screen
set "SCRIPT=%~dp0XEOKA-PACK.ps1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%SCRIPT%" -NoElevate
pause
