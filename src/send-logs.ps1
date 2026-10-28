# Gửi log, run in its own process by the app: prints "sent|<name>" or "saved|<zip path>" when the
# upload is not possible, so the user can send the file by hand.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'application/workspace.ps1')
. (Join-Path $PSScriptRoot 'infrastructure/drive-storage.ps1')
. (Join-Path $PSScriptRoot 'application/support-logs.ps1')
$zip = New-SupportLogBundle $root
$drive = Get-DriveConfig (Join-Path $root 'workspace')
try {
    if (-not $drive) { throw 'no app password' }
    Write-Output ('sent|' + (Send-SupportLog $drive $zip))
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
} catch { Write-Output ('saved|' + $zip) }
