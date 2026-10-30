# Writes the one-line quota summary for the main window to -OutFile as UTF-8 (run in its own process so the window
# never waits). Redirected console output would use the Windows code page and break the Vietnamese text.
param([Parameter(Mandatory)][string]$OutFile)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../../hub/setup/quota.ps1')
$text = try { Get-QuotaSummary } catch { 'Hạn mức: chưa lấy được' }
[IO.File]::WriteAllText($OutFile, $text, [Text.UTF8Encoding]::new($false))
