@echo off
chcp 65001 >nul 2>nul
setlocal EnableExtensions EnableDelayedExpansion
title AI Agent build_all
set "SCRIPT_DIR=%~dp0"
set "LOG=%SCRIPT_DIR%build_logs\build_all_latest.log"

echo ========================================
echo AI Agent build_all v1.49
echo Script: %~f0
echo Time: %DATE% %TIME%
echo ========================================

if not exist "%SCRIPT_DIR%build_logs" mkdir "%SCRIPT_DIR%build_logs" >nul 2>nul
if not exist "%SCRIPT_DIR%dist" mkdir "%SCRIPT_DIR%dist" >nul 2>nul

echo Build started: %DATE% %TIME% > "%LOG%"
echo SCRIPT_DIR=%SCRIPT_DIR% >> "%LOG%"
echo.

echo [1/8] Checking Flutter environment...
echo [1/8] Checking Flutter environment... >> "%LOG%"
call "%SCRIPT_DIR%_flutter_env.bat"
set "ENV_CODE=%ERRORLEVEL%"
echo [1/8] _flutter_env.bat returned %ENV_CODE%
echo [1/8] _flutter_env.bat returned %ENV_CODE% >> "%LOG%"
if not "%ENV_CODE%"=="0" goto fail_env
if not defined FLUTTER goto fail_no_flutter
if not defined PROJECT_ROOT goto fail_no_project_root
if not exist "%FLUTTER%" (
  rem If FLUTTER came from PATH as a command name/path without extension, let Windows try it later.
  echo "%FLUTTER%" | findstr /I /C:"flutter" >nul
)
echo PROJECT_ROOT=%PROJECT_ROOT% >> "%LOG%"
echo FLUTTER=%FLUTTER% >> "%LOG%"
echo Flutter: %FLUTTER%

cd /d "%PROJECT_ROOT%"
if errorlevel 1 goto fail

echo [2/8] Flutter version...
echo [2/8] Flutter version... >> "%LOG%"
call "%FLUTTER%" --version >> "%LOG%" 2>&1
if errorlevel 1 goto fail

powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-PSDrive -PSProvider FileSystem | Format-Table Name,Free,Used,Root -AutoSize" >> "%LOG%" 2>&1

echo [3/8] Preparing Flutter platforms...
echo [3/8] Preparing Flutter platforms... >> "%LOG%"
call "%SCRIPT_DIR%prepare_flutter_platforms.bat" >> "%LOG%" 2>&1
if errorlevel 1 goto fail

echo [4/8] Patching Android permissions...
echo [4/8] Patching Android permissions... >> "%LOG%"
call "%SCRIPT_DIR%patch_android_permissions.bat" >> "%LOG%" 2>&1
if errorlevel 1 goto fail

echo [5/8] Running analyze...
echo [5/8] Running analyze... >> "%LOG%"
call "%SCRIPT_DIR%analyze.bat" >> "%LOG%" 2>&1
if errorlevel 1 goto fail

echo [6/8] Running tests...
echo [6/8] Running tests... >> "%LOG%"
call "%SCRIPT_DIR%run_tests.bat" >> "%LOG%" 2>&1
if errorlevel 1 goto fail

set "SKIP_CHECKS=1"
set "NO_PAUSE=1"

echo [7/8] Building Windows...
echo [7/8] Building Windows... >> "%LOG%"
call "%SCRIPT_DIR%build_windows.bat" >> "%LOG%" 2>&1
if errorlevel 1 goto fail

echo [8/8] Building Android...
echo [8/8] Building Android... >> "%LOG%"
call "%SCRIPT_DIR%build_android.bat" >> "%LOG%" 2>&1
if errorlevel 1 goto fail

set "SKIP_CHECKS="
set "NO_PAUSE="
echo.>> "%LOG%"
echo BUILD OK. Results are in dist. >> "%LOG%"
echo.
echo ========================================
echo BUILD OK
echo Results are in: %PROJECT_ROOT%dist
echo Full log: %LOG%
echo ========================================
pause
exit /b 0

:fail_env
set "CODE=%ENV_CODE%"
goto fail_common

:fail_no_flutter
set "CODE=1"
echo [ERROR] _flutter_env.bat completed but FLUTTER variable is empty.
echo [ERROR] _flutter_env.bat completed but FLUTTER variable is empty. >> "%LOG%"
goto fail_common

:fail_no_project_root
set "CODE=1"
echo [ERROR] _flutter_env.bat completed but PROJECT_ROOT variable is empty.
echo [ERROR] _flutter_env.bat completed but PROJECT_ROOT variable is empty. >> "%LOG%"
goto fail_common

:fail
set "CODE=%ERRORLEVEL%"
if "%CODE%"=="0" set "CODE=1"
goto fail_common

:fail_common
set "SKIP_CHECKS="
set "NO_PAUSE="
echo.>> "%LOG%"
echo BUILD FAILED with code %CODE% >> "%LOG%"
echo.
echo ========================================
echo BUILD FAILED with code %CODE%
echo Full log: %LOG%
echo Last 120 lines:
echo ========================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path '%LOG%') { Get-Content '%LOG%' -Tail 120 } else { Write-Host 'Log file not created.' }"
echo ========================================
pause
exit /b %CODE%
