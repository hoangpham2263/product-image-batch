# Gửi log, run in its own process by the app: prints "sent|<name>|<samples marked Bỏ sent>" or
# "saved|<zip path>" when the upload is not possible, so the user can send the file by hand.
$ErrorActionPreference = 'Stop'
# The app reads this output as UTF-8 (paths may hold Vietnamese folder names).
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'application/workspace.ps1')
. (Join-Path $PSScriptRoot 'infrastructure/drive-storage.ps1')
. (Join-Path $PSScriptRoot 'application/ai-settings.ps1')
. (Join-Path $PSScriptRoot 'application/batch-review.ps1')
. (Join-Path $PSScriptRoot 'application/support-logs.ps1')
$bundle = New-SupportLogBundle $root
$drive = Get-DriveConfig (Join-Path $root 'workspace')
try {
    if (-not $drive) { throw 'no app password' }
    $name = Send-SupportLog $drive $bundle.Path
    Complete-RejectedSamples $bundle.Samples
    Write-Output ('sent|' + $name + '|' + @($bundle.Samples).Count)
    Remove-Item -LiteralPath $bundle.Path -Force -ErrorAction SilentlyContinue
} catch { Write-Output ('saved|' + $bundle.Path) }
