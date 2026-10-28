@echo off
chcp 65001 >nul
cd /d "%~dp0"
rem Installs whatever is missing (Node.js, Codex, sign-in, bridge), then runs the readiness check.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\setup-install.ps1"
echo.
pause
