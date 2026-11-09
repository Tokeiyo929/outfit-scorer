@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%upload-web-mobile.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

if /i "%~1"=="-List" exit /b %EXIT_CODE%
if /i "%GAMENEXUS_CI_NO_PAUSE%"=="1" exit /b %EXIT_CODE%
echo.
echo Upload finished with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
