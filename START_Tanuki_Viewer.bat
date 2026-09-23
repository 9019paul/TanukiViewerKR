@echo off
setlocal
cd /d "%~dp0"
start "Tanuki Viewer KR" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0launcher\server.ps1"
exit /b 0
