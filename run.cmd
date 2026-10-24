@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist "%~dp0workspace\output" mkdir "%~dp0workspace\output"
:menu
cls
echo ===== PRODUCT IMAGE BATCH =====
echo 1. Run pending URLs
echo 2. Edit urls.txt
echo 3. Open sample data
echo 4. Open output batches
echo 0. Exit
echo.
set "choice="
set /p choice=Select: 
if "%choice%"=="0" exit /b
if "%choice%"=="1" goto run
if "%choice%"=="2" start "" notepad.exe "%~dp0workspace\urls.txt"
if "%choice%"=="3" start "" "%~dp0data"
if "%choice%"=="4" start "" "%~dp0workspace\output"
goto menu
:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\run-images.ps1"
echo.
pause
goto menu
