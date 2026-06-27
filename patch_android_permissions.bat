@echo off
chcp 65001 >nul 2>nul
call "%~dp0_flutter_env.bat"
if errorlevel 1 exit /b 1
set "MANIFEST=%PROJECT_ROOT%android\app\src\main\AndroidManifest.xml"
if not exist "%MANIFEST%" exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch_android_permissions.ps1" -ManifestPath "%MANIFEST%" || exit /b 1
exit /b 0
