@echo off
rem ТГ: https://t.me/CMEPT0HOCHbIU
setlocal
set "SCRIPT=%~dp0XEOKA-PACK.ps1"
if not exist "%SCRIPT%" (
  echo [ERROR] XEOKA-PACK.ps1 not found. Extract the whole archive first.
  pause
  exit /b 1
)
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT%"
exit /b 0
