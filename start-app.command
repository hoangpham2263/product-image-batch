#!/bin/bash
# Opens Product Review Batch on macOS: a local server (src/mac/server.mjs) and the app window.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.dotnet/tools:$PATH"
if ! command -v node >/dev/null || ! command -v pwsh >/dev/null; then bash src/mac/setup.sh || { read -r -p "Chưa cài xong. Nhấn Enter để đóng."; exit 1; }; fi
nohup node src/mac/server.mjs >/dev/null 2>&1 &
disown
# The app keeps running on its own; close this Terminal window once the script has ended.
# nohup: Terminal hangs up this session's processes when the script exits, before the close would run.
nohup /bin/bash -c 'sleep 1; osascript -e "tell application \"Terminal\" to close (every window whose name contains \"start-app.command\")"' >/dev/null 2>&1 &
exit 0
