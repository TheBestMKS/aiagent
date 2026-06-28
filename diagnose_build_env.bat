@echo off
chcp 65001 >nul 2>nul
setlocal EnableExtensions
echo ========================================
echo AI Agent build environment diagnostics v1.50
echo Script: %~f0
echo Time: %DATE% %TIME%
echo ========================================
echo.
echo [1] Calling _flutter_env.bat...
call "%~dp0_flutter_env.bat"
set "ENV_CODE=%ERRORLEVEL%"
echo _flutter_env.bat returned %ENV_CODE%
if not "%ENV_CODE%"=="0" (
  echo.
  echo Flutter environment failed.
  pause
  exit /b %ENV_CODE%
)
echo PROJECT_ROOT=%PROJECT_ROOT%
echo FLUTTER=%FLUTTER%
echo.
echo [2] Flutter version:
call "%FLUTTER%" --version
echo.
echo [3] Common tools:
where git 2>nul
where powershell 2>nul
where cmake 2>nul
echo.
echo [4] Project files:
if exist "%PROJECT_ROOT%pubspec.yaml" (echo pubspec.yaml OK) else (echo pubspec.yaml NOT FOUND)
if exist "%PROJECT_ROOT%lib\main.dart" (echo lib\main.dart OK) else (echo lib\main.dart NOT FOUND)
echo.
pause
exit /b 0
