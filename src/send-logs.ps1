# Gửi lỗi, run in its own process by the app (Windows and macOS): prints "step|<text>" as it goes, then
# "sent|<name>|<samples marked Bỏ sent>" or
# "saved|<zip path>|<reason>" when the upload is not possible, so the user can send the file by hand.
$ErrorActionPreference = 'Stop'
# The app reads this output as UTF-8 (paths may hold Vietnamese folder names).
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'application/workspace.ps1')
. (Join-Path $PSScriptRoot 'infrastructure/platform.ps1')
. (Join-Path $PSScriptRoot 'infrastructure/codex.ps1')
. (Join-Path $PSScriptRoot 'infrastructure/drive-storage.ps1')
. (Join-Path $PSScriptRoot 'application/ai-settings.ps1')
. (Join-Path $PSScriptRoot 'application/batch-review.ps1')
. (Join-Path $PSScriptRoot 'application/support-logs.ps1')
$step = { param($Text) [Console]::Out.WriteLine("step|$Text"); [Console]::Out.Flush() }
$bundle = New-SupportLogBundle $root -Analyze -OnStep $step
$drive = Get-DriveConfig (Join-Path $root 'workspace')
try {
    if (-not $drive) { throw 'no app password' }
    & $step 'Đang gửi…'
    $name = Send-SupportLog $drive $bundle.Path
    Complete-RejectedSamples $bundle.Samples
    Complete-SupportLogSend $root
    Write-Output ('sent|' + $name + '|' + @($bundle.Samples).Count)
    Remove-Item -LiteralPath $bundle.Path -Force -ErrorAction SilentlyContinue
} catch {
    $reason = if (-not $drive) { 'chưa có mật khẩu app' } elseif ($_.ErrorDetails.Message) { try { ($_.ErrorDetails.Message | ConvertFrom-Json).error } catch { $_.ErrorDetails.Message } } else { $_.Exception.Message }
    Write-Output ('saved|' + $bundle.Path + '|' + ([string]$reason -replace '[\r\n|]', ' '))
}
