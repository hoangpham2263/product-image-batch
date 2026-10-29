$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/infrastructure/quota.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$data = @'
{
 "rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},
 "rateLimitsByLimitId":{
  "codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1792763111},"secondary":{"usedPercent":100,"windowDurationMins":10080}},
  "other":{"limitName":"Other","primary":{"usedPercent":0,"windowDurationMins":30}}
 }
}
'@ | ConvertFrom-Json
$messages = @(Get-QuotaMessages $data)
Assert ($messages.Count -eq 3 -and $messages[0] -match '5 giờ.*còn 75%.*20:45 23/10.*GMT\+7') 'Wrong remaining percentage, preferred multi-bucket view or reset timezone.'
Assert ($messages[1] -match '7 ngày.*còn 0%.*Chưa có giờ' -and $messages[2] -match '30 phút.*còn 100%') 'Known zero/full percentages or absent reset are wrong.'
# Main window: what is left; Kiểm tra cấu hình: only when it resets.
Assert ((@(Get-QuotaMessages $data -Short) -join ' · ') -eq '5 giờ còn 75% · 7 ngày còn 0% · 30 phút còn 100%') 'The main window line must say what is left per window.'
Assert ((@(Get-QuotaMessages $data -Reset) -join ' · ') -eq '5 giờ lúc 20:45 23/10 · 7 ngày chưa có giờ · 30 phút chưa có giờ') 'Kiểm tra cấu hình must show only the reset times.'
Assert (@(Get-QuotaMessages ('{"rateLimits":{"primary":{"usedPercent":null},"secondary":null}}' | ConvertFrom-Json)).Count -eq 0) 'Missing usage must not become zero usage.'
$legacy = @(Get-QuotaMessages ('{"rateLimits":{"primary":{"usedPercent":12.5,"windowDurationMins":60}}}' | ConvertFrom-Json))
Assert ($legacy.Count -eq 1 -and $legacy[0] -match '1 giờ.*87.5%') 'Legacy single-bucket view failed.'
$invalid = @(Get-QuotaMessages ('{"rateLimits":{"primary":{"usedPercent":"invalid"},"secondary":{"usedPercent":"NaN"}}}' | ConvertFrom-Json))
Assert ($invalid.Count -eq 0) 'Invalid usage was presented as known.'
$clamped = @(Get-QuotaMessages ('{"rateLimits":{"primary":{"usedPercent":110},"secondary":{"usedPercent":-5}}}' | ConvertFrom-Json))
Assert ($clamped[0] -match 'còn 0%' -and $clamped[1] -match 'còn 100%') 'Remaining percentage is outside valid bounds.'
& node (Join-Path $PSScriptRoot 'quota-client.cjs')
if ($LASTEXITCODE -ne 0) { throw 'Quota transport checks failed.' }
# Mock the CLI transport: no paid AI or actual account request in the offline suite.
function node { '{"available":true,"data":{"rateLimits":{"primary":{"usedPercent":30,"windowDurationMins":300}}}}' }
$quota = Get-ChatGptQuota 'fake-codex.exe'
Assert ($quota.Available -and $quota.Messages[0] -match 'còn 70%') 'Quota transport output was not integrated.'
Assert ($quota.Messages[0] -match 'chưa xác minh lượt tạo ảnh') 'CLI quota was presented as verified image-generation availability.'
function node { '{"available":false,"reason":"timeout"}' }
$quota = Get-ChatGptQuota 'fake-codex.exe'
Assert (-not $quota.Available -and $quota.Messages[0] -match 'chưa lấy được dữ liệu') 'Unavailable quota was reported as known.'
Assert ($quota.Messages[0] -match 'chưa xác định' -and $quota.Messages[0] -match 'Không đồng nghĩa hết hạn mức') 'Unreadable quota was confused with exhausted quota.'
function node { 'invalid response with private information' }
$quota = Get-ChatGptQuota 'fake-codex.exe'
Assert (-not $quota.Available -and $quota.Messages[0] -notmatch 'private') 'Raw quota failure leaked.'
Write-Host 'PASS: remaining quota percentages, window labels, local reset time, missing data and fallback messages.'
# Integrate a successful/failing quota read with the actual setup report.
function codex { Write-Output 'Logged in using ChatGPT'; $global:LASTEXITCODE = 0 }
function Get-Command($Name, $ErrorAction) {
    if ($Name -eq 'codex') { return [pscustomobject]@{ Source = 'test-codex.exe' } }
    Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction SilentlyContinue
}
function node { '{"available":true,"data":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300},"secondary":{"usedPercent":20,"windowDurationMins":10080}}}}' }
$report = (& (Join-Path $root 'src/setup-check.ps1') -AsJson | Out-String) | ConvertFrom-Json
Assert ($report.Ready -and $report.QuotaAvailable -and $report.Checks.Count -eq 5 -and $report.Checks[3].Message -match '90%' -and $report.Checks[4].Message -match '80%') 'Live quota messages were not added to the setup report.'
function node { '{"available":false,"reason":"timeout"}' }
$report = (& (Join-Path $root 'src/setup-check.ps1') -AsJson | Out-String) | ConvertFrom-Json
Assert ($report.Ready -and -not $report.QuotaAvailable -and $report.Checks[-1].Message -match 'chưa lấy được') 'Unavailable quota changed login readiness or disappeared.'
Write-Host 'PASS: setup report integrates quota windows and reports unknown quota without rejecting valid sign-in.'
