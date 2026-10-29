# Prints the one-line quota summary for the main window (run in its own process so the window never waits).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'infrastructure/quota.ps1')
try { Write-Output (Get-QuotaSummary) } catch { Write-Output 'Hạn mức: chưa lấy được' }
