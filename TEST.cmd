@echo off
setlocal
cd /d "%~dp0"
if not exist ".runtime" mkdir ".runtime"
set "APPDATA=%~dp0.runtime"
"%~dp0Godot_v4.7.2-stable_win64_console.exe" --headless --path "%~dp0." --script res://tests/integration.gd --log-file "%~dp0tests\integration.log"
set "TEST_RESULT=%ERRORLEVEL%"
echo Test exit code: %TEST_RESULT%
exit /b %TEST_RESULT%
