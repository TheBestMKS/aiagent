@echo off
chcp 65001 >nul 2>nul
call "%~dp0_flutter_env.bat"
if errorlevel 1 exit /b 1
cd /d "%PROJECT_ROOT%" || exit /b 1
if not exist "pubspec.yaml" (
  echo pubspec.yaml not found in %PROJECT_ROOT%
  echo Run this script from the Flutter project root or keep the .bat files in the project root.
  exit /b 1
)
if not exist "windows" (
  echo Creating Windows and Android platform files...
  "%FLUTTER%" create --platforms=windows,android . || exit /b 1
) else if not exist "android" (
  echo Creating Windows and Android platform files...
  "%FLUTTER%" create --platforms=windows,android . || exit /b 1
)
exit /b 0
