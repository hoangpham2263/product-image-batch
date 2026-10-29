# Tải cả nhóm về máy: download one Drive group into data/source-photos/<group> (run in its own process by the app).
param([Parameter(Mandatory)][string]$Group)
$ErrorActionPreference = 'Stop'
# The app reads this output as UTF-8 (paths may hold Vietnamese folder names).
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'application/workspace.ps1')
. (Join-Path $PSScriptRoot 'infrastructure/platform.ps1')
. (Join-Path $PSScriptRoot 'infrastructure/drive-storage.ps1')
. (Join-Path $PSScriptRoot 'infrastructure/source-catalog.ps1')
. (Join-Path $PSScriptRoot 'infrastructure/source-sync.ps1')
$drive = Get-DriveConfig (Join-Path $root 'workspace')
if (-not $drive) { throw 'Đăng nhập Google Drive trước.' }
$result = Sync-SourceGroup $drive (Join-Path $root 'data/source-photos') $Group
Write-Output ("{0}|{1}|{2}" -f $result.Total, $result.Downloaded, $result.Removed)
