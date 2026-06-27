@echo off
chcp 65001 >nul 2>nul
setlocal EnableExtensions EnableDelayedExpansion
call "%~dp0_flutter_env.bat"
if errorlevel 1 exit /b 1
cd /d "%PROJECT_ROOT%" || exit /b 1
call "%~dp0prepare_flutter_platforms.bat" || exit /b 1

call "%FLUTTER%" pub get
if errorlevel 1 exit /b 1

set "ANALYZE_LOG=%PROJECT_ROOT%build_logs\analyze_scoped_latest.log"
if not exist "%PROJECT_ROOT%build_logs" mkdir "%PROJECT_ROOT%build_logs" >nul 2>nul
if exist "%ANALYZE_LOG%" del /f /q "%ANALYZE_LOG%" >nul 2>nul

echo Running scoped analyzer only for project sources.
echo This intentionally does NOT analyze bundled Flutter SDK under tooling\.
echo.

echo ===== flutter analyze lib ===== > "%ANALYZE_LOG%"
call "%FLUTTER%" analyze lib >> "%ANALYZE_LOG%" 2>&1
set "LIB_CODE=%ERRORLEVEL%"

if exist "test" (
  dir /b /s "test\*_test.dart" >nul 2>nul
  if not errorlevel 1 (
    echo.>> "%ANALYZE_LOG%"
    echo ===== flutter analyze test ===== >> "%ANALYZE_LOG%"
    call "%FLUTTER%" analyze test >> "%ANALYZE_LOG%" 2>&1
    set "TEST_CODE=%ERRORLEVEL%"
  ) else (
    set "TEST_CODE=0"
    echo.>> "%ANALYZE_LOG%"
    echo No *_test.dart files found, test analyze skipped.>> "%ANALYZE_LOG%"
  )
) else (
  set "TEST_CODE=0"
  echo.>> "%ANALYZE_LOG%"
  echo No test directory found, test analyze skipped.>> "%ANALYZE_LOG%"
)

type "%ANALYZE_LOG%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = Get-Content -Raw -LiteralPath '%ANALYZE_LOG%'; if ($t -match '(?m)^\s*error\s+-\s+') { exit 1 } else { exit 0 }"
if errorlevel 1 (
  echo.
  echo ANALYZE FAILED: real Dart analyzer errors were found.
  exit /b 1
)

echo.
echo ANALYZE PASSED: no analyzer errors found. Warnings/info do not stop release builds.
exit /b 0
