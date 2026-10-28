#!/bin/bash
# Opens Product Review Batch on macOS: a local server (src/mac/server.mjs) and the app window.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.dotnet/tools:$PATH"
if ! command -v node >/dev/null || ! command -v pwsh >/dev/null; then ./setup.command || exit 1; fi
nohup node src/mac/server.mjs >/dev/null 2>&1 &
