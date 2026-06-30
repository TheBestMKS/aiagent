@echo off
chcp 65001 >nul 2>nul
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0_flutter_env.bat"
if errorlevel 1 goto fail
cd /d "%PROJECT_ROOT%" || goto fail
call "%~dp0prepare_flutter_platforms.bat" || goto fail
if /I not "%SKIP_CHECKS%"=="1" (
  call "%~dp0analyze.bat" || goto fail
  call "%~dp0run_tests.bat" || goto fail
)
call "%FLUTTER%" build windows --release || goto fail
set "APP_NAME=AIAgent"
set "APP_VERSION=v1.52"
set "APP_PLATFORM=windows"
set "APP_ARCH=x64"
set "DIST_ROOT=%PROJECT_ROOT%dist"
set "DIST_DIR=%DIST_ROOT%\%APP_NAME%_%APP_VERSION%_%APP_PLATFORM%_%APP_ARCH%"
if not exist "%DIST_ROOT%" mkdir "%DIST_ROOT%" >nul 2>nul
if exist "%DIST_DIR%" rmdir /s /q "%DIST_DIR%"
mkdir "%DIST_DIR%" >nul 2>nul
set "WIN_RELEASE=%PROJECT_ROOT%build\windows\x64\runner\Release"
if not exist "%WIN_RELEASE%\*.exe" (
  echo Default Windows release folder not found or empty: %WIN_RELEASE%
  echo Searching built Windows release folder...
  for /f "delims=" %%D in ('dir /b /s /ad "%PROJECT_ROOT%build\windows" 2^>nul') do (
    if /I "%%~nxD"=="Release" if exist "%%D\*.exe" set "WIN_RELEASE=%%D"
  )
)
if not exist "%WIN_RELEASE%\*.exe" (
  echo Windows release artifacts not found. Checked: %WIN_RELEASE%
  goto fail
)
xcopy /E /I /Y "%WIN_RELEASE%\*" "%DIST_DIR%\" >nul || goto fail
echo Windows release copied from %WIN_RELEASE% to %DIST_DIR%
if /I not "%NO_PAUSE%"=="1" pause
exit /b 0
:fail
set "CODE=%ERRORLEVEL%"
echo Windows build failed with code %CODE%
if /I not "%NO_PAUSE%"=="1" pause
exit /b %CODE%
