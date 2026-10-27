@echo off
chcp 65001 >nul
cd /d "%~dp0"
if exist "%~dp0bridge\package.json" (pushd "%~dp0bridge" && call npm install --silent && popd)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\setup-check.ps1"
echo.
pause
