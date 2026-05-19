@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_PATH=%SCRIPT_DIR%check_ebs_encryption.py"

where python >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  python "%SCRIPT_PATH%" %*
  exit /b %ERRORLEVEL%
)

where py >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  py -3 "%SCRIPT_PATH%" %*
  exit /b %ERRORLEVEL%
)

echo ERROR: Python 3 is required to run %SCRIPT_PATH%.
exit /b 1
