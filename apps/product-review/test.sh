#!/bin/sh
# macOS/Linux: run syntax checks and offline test suites with PowerShell 7.
cd "$(dirname "$0")" && exec pwsh -NoProfile -File tests/run.ps1 "$@"
