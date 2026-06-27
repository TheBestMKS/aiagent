@echo off
chcp 65001 >nul 2>nul
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0_flutter_env.bat"
if errorlevel 1 exit /b 1
cd /d "%PROJECT_ROOT%" || exit /b 1
call "%~dp0prepare_flutter_platforms.bat" || exit /b 1
call "%FLUTTER%" pub get || exit /b 1

if not exist "test" (
  echo No test directory found. Tests skipped.
  exit /b 0
)
dir /b /s "test\*_test.dart" >nul 2>nul
if errorlevel 1 (
  echo No *_test.dart files found. Tests skipped.
  exit /b 0
)

echo Running project tests only...
call "%FLUTTER%" test test
exit /b %ERRORLEVEL%
