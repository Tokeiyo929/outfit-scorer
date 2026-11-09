@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"

if not "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %*
  set "EXIT_CODE=!ERRORLEVEL!"
  goto :finish
)

echo GameNexus Project CI
echo.
set "PROFILE_ROOT=%SCRIPT_DIR%profiles"
set "PROFILE_COUNT=0"
echo Profiles:
for /f "delims=" %%D in ('dir /b /ad "%PROFILE_ROOT%" 2^>nul') do (
  set /a PROFILE_COUNT+=1
  set "PROFILE_!PROFILE_COUNT!=%%D"
  echo   !PROFILE_COUNT!. %%D
)
if "%PROFILE_COUNT%"=="0" (
  echo   No profile directories found under: %PROFILE_ROOT%
)
echo.

:ask_profile
set "PROFILE_INPUT="
set "PROFILE_BUNDLE="
if "%PROFILE_COUNT%"=="0" (
  set /p "PROFILE_INPUT=ProfileBundle name or path: "
) else (
  set /p "PROFILE_INPUT=ProfileBundle [1-%PROFILE_COUNT% or name/path] default 1: "
)
if "%PROFILE_INPUT%"=="" set "PROFILE_INPUT=1"
for /l %%I in (1,1,%PROFILE_COUNT%) do (
  if "%PROFILE_INPUT%"=="%%I" set "PROFILE_BUNDLE=!PROFILE_%%I!"
)
if "%PROFILE_BUNDLE%"=="" set "PROFILE_BUNDLE=%PROFILE_INPUT%"
if "%PROFILE_BUNDLE%"=="" (
  echo ProfileBundle cannot be empty.
  goto :ask_profile
)

echo.
echo Platforms:
echo   1. web-mobile
echo   2. wechatgame
echo   3. bytedance
echo.
set "PLATFORM="
:ask_platform
set /p "PLATFORM_INPUT=Platform [1/web-mobile, 2/wechatgame, 3/bytedance] default 1: "
if "%PLATFORM_INPUT%"=="" set "PLATFORM_INPUT=1"
if /i "%PLATFORM_INPUT%"=="1" set "PLATFORM=web-mobile"
if /i "%PLATFORM_INPUT%"=="web-mobile" set "PLATFORM=web-mobile"
if /i "%PLATFORM_INPUT%"=="2" set "PLATFORM=wechatgame"
if /i "%PLATFORM_INPUT%"=="wechatgame" set "PLATFORM=wechatgame"
if /i "%PLATFORM_INPUT%"=="3" set "PLATFORM=bytedance"
if /i "%PLATFORM_INPUT%"=="bytedance" set "PLATFORM=bytedance"
if "%PLATFORM%"=="" (
  echo Unsupported platform: %PLATFORM_INPUT%
  goto :ask_platform
)

echo.
echo Stages:
echo   all
echo   env-prepare
echo   before-build
echo   build
echo   after-build
echo   upload
echo   cleanup
echo.
set "STAGE="
:ask_stage
set /p "STAGE=Stage default all: "
if "%STAGE%"=="" set "STAGE=all"
if /i "%STAGE%"=="all" goto :stage_ok
if /i "%STAGE%"=="env-prepare" goto :stage_ok
if /i "%STAGE%"=="before-build" goto :stage_ok
if /i "%STAGE%"=="build" goto :stage_ok
if /i "%STAGE%"=="after-build" goto :stage_ok
if /i "%STAGE%"=="upload" goto :stage_ok
if /i "%STAGE%"=="cleanup" goto :stage_ok
echo Unsupported stage: %STAGE%
goto :ask_stage

:stage_ok
set "BUILD_ID="
set /p "BUILD_ID=BuildId optional, press Enter for auto name: "

echo.
echo Running:
if "%BUILD_ID%"=="" (
  echo   ci\run.cmd -ProfileBundle "%PROFILE_BUNDLE%" -Platform "%PLATFORM%" -Stage "%STAGE%"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" -ProfileBundle "%PROFILE_BUNDLE%" -Platform "%PLATFORM%" -Stage "%STAGE%"
) else (
  echo   ci\run.cmd -ProfileBundle "%PROFILE_BUNDLE%" -Platform "%PLATFORM%" -Stage "%STAGE%" -BuildId "%BUILD_ID%"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" -ProfileBundle "%PROFILE_BUNDLE%" -Platform "%PLATFORM%" -Stage "%STAGE%" -BuildId "%BUILD_ID%"
)
set "EXIT_CODE=!ERRORLEVEL!"

:finish
if /i "%GAMENEXUS_CI_NO_PAUSE%"=="1" exit /b %EXIT_CODE%
echo.
echo Build finished with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
