#!/bin/zsh -l
# macOS: double-click to open Product Image Batch in the browser.
cd "$(dirname "$0")"
export PATH="$PATH:$HOME/.dotnet/tools:/opt/homebrew/bin:/usr/local/bin"
URL="http://127.0.0.1:8765"
command -v node >/dev/null || { echo "Chưa cài Node.js (https://nodejs.org)."; read -k1; exit 1; }
command -v pwsh >/dev/null || { echo "Chưa cài PowerShell 7: brew install --cask powershell  (hoặc: dotnet tool install --global PowerShell)"; read -k1; exit 1; }
[ -d bridge/node_modules/ws ] || (cd bridge && npm install --silent)
if ! curl -s -o /dev/null "$URL/api/state"; then
  mkdir -p workspace/logs; nohup node bridge/server.mjs > workspace/logs/app-server.log 2>&1 &
  for i in {1..20}; do curl -s -o /dev/null "$URL/api/state" && break; sleep 0.5; done
fi
open "$URL"
