@echo off
cd /d "%~dp0"
rem One line: this file may be replaced by the update while it runs.
(powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0src\update.ps1" & powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0src\gui.ps1") & exit /b
