@echo off
rem Debug launcher: visible console, errors stay on screen
set "SCRIPT=%~dp0XEOKA-PACK.ps1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%SCRIPT%" -NoElevate
pause
