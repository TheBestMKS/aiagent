@echo off
chcp 65001 >nul 2>nul
setlocal EnableExtensions DisableDelayedExpansion
set "PROJECT_ROOT=%~dp0"
set "FLUTTER_PORTABLE=%PROJECT_ROOT%tooling\flutter\flutter\bin\flutter.bat"
set "FLUTTER="

echo [env] PROJECT_ROOT=%PROJECT_ROOT%

if exist "%FLUTTER_PORTABLE%" (
  set "FLUTTER=%FLUTTER_PORTABLE%"
  goto :found
)

echo [env] Portable Flutter not found:
echo [env]   %FLUTTER_PORTABLE%
echo [env] Trying Flutter from PATH...

for %%F in (flutter.bat flutter.exe flutter) do (
  if not defined FLUTTER (
    for /f "usebackq delims=" %%P in (`where %%F 2^>nul`) do (
      if not defined FLUTTER set "FLUTTER=%%P"
    )
  )
)

if not defined FLUTTER (
  echo [ERROR] Flutter SDK not found.
  echo Expected portable Flutter:
  echo   %PROJECT_ROOT%tooling\flutter\flutter\bin\flutter.bat
  echo Or flutter must be available in PATH.
  echo.
  echo Put Flutter SDK into:
  echo   tooling\flutter\flutter\
  echo so flutter.bat is located at:
  echo   tooling\flutter\flutter\bin\flutter.bat
  endlocal & exit /b 1
)

:found
echo [env] Flutter found: %FLUTTER%
endlocal & set "FLUTTER=%FLUTTER%" & set "PROJECT_ROOT=%PROJECT_ROOT%"
exit /b 0
