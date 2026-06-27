@echo off
chcp 65001 >nul 2>nul
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0_flutter_env.bat"
if errorlevel 1 goto fail
cd /d "%PROJECT_ROOT%" || goto fail
call "%~dp0prepare_flutter_platforms.bat" || goto fail
call "%~dp0patch_android_permissions.bat" || goto fail
if /I not "%SKIP_CHECKS%"=="1" (
  call "%~dp0analyze.bat" || goto fail
  call "%~dp0run_tests.bat" || goto fail
)
call "%FLUTTER%" build apk --release || goto fail
set "APP_NAME=AIAgent"
set "APP_VERSION=v1.49"
set "APP_PLATFORM=android"
set "APP_ARCH=universal"
set "DIST_ROOT=%PROJECT_ROOT%dist"
set "APK_NAME=%APP_NAME%_%APP_VERSION%_%APP_PLATFORM%_%APP_ARCH%.apk"
if not exist "%DIST_ROOT%" mkdir "%DIST_ROOT%" >nul 2>nul
set "APK_SOURCE=%PROJECT_ROOT%build\app\outputs\flutter-apk\app-release.apk"
if not exist "%APK_SOURCE%" (
  echo Default Android APK not found: %APK_SOURCE%
  echo Searching app-release.apk under build...
  for /f "delims=" %%F in ('dir /b /s "%PROJECT_ROOT%build\app-release.apk" 2^>nul') do set "APK_SOURCE=%%F"
)
if not exist "%APK_SOURCE%" (
  echo Android APK artifact not found.
  goto fail
)
copy /Y "%APK_SOURCE%" "%DIST_ROOT%\%APK_NAME%" >nul || goto fail
echo Android APK copied from %APK_SOURCE% to %DIST_ROOT%\%APK_NAME%
if /I not "%NO_PAUSE%"=="1" pause
exit /b 0
:fail
set "CODE=%ERRORLEVEL%"
echo Android build failed with code %CODE%
if /I not "%NO_PAUSE%"=="1" pause
exit /b %CODE%
