@echo off
chcp 65001 >nul
cd /d "%~dp0"
if not exist "bridge\node_modules\ws" (pushd bridge && call npm install --silent && popd)
curl -s -o nul http://127.0.0.1:8765/api/state || start "" /min node bridge\server.mjs
timeout /t 2 >nul
start "" http://127.0.0.1:8765
