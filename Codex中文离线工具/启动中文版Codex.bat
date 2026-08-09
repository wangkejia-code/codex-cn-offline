@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Codex-CN-Offline.ps1"
echo.
pause
endlocal
