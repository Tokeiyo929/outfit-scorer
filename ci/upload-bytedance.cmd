@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%upload-bytedance.ps1" %*
set "EXIT_CODE=!ERRORLEVEL!"

if /i "%GAMENEXUS_CI_NO_PAUSE%"=="1" exit /b %EXIT_CODE%
echo.
echo Upload finished with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
