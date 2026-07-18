@echo off
chcp 65001 >nul 2>nul
setlocal EnableExtensions DisableDelayedExpansion
title AI Agent - Build Windows
set "EXTRA_ARGS="
if /I "%SKIP_CHECKS%"=="1" set "EXTRA_ARGS=-SkipChecks"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Target Windows %EXTRA_ARGS% %*
set "CODE=%ERRORLEVEL%"
if /I not "%NO_PAUSE%"=="1" pause
exit /b %CODE%
