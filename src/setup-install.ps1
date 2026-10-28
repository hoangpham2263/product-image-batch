# One-time install on Windows (setup.cmd): Node.js, Codex CLI, ChatGPT sign-in and the browser
# bridge, each only when missing, then the same readiness check as the app's Kiểm tra ChatGPT.
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot -Parent
function Step([string]$Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }
function Update-SessionPath { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }
function Test-Tool([string]$Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

Step 'Node.js'
if (-not (Test-Tool node)) {
    if (Test-Tool winget) { winget install -e --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements; Update-SessionPath }
    if (-not (Test-Tool node)) {
        Write-Host 'Chưa cài được Node.js tự động. Tải bản LTS ở trang vừa mở, cài xong chạy lại setup.cmd.' -ForegroundColor Yellow
        Start-Process 'https://nodejs.org'
        exit 1
    }
}
Write-Host "Node.js $(node --version)"

Step 'Codex'
if (-not (Test-Tool codex)) { npm install -g @openai/codex; Update-SessionPath }
if (-not (Test-Tool codex)) { Write-Host 'Chưa cài được Codex. Chạy lại: npm install -g @openai/codex' -ForegroundColor Yellow; exit 1 }
Write-Host (codex --version)

Step 'Đăng nhập ChatGPT'
$status = (& codex login status 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $status -notmatch '(?i)logged in') { codex login } else { Write-Host 'Đã đăng nhập.' }

Step 'Cầu nối trình duyệt'
$bridge = Join-Path $root 'bridge'
if (Test-Path -LiteralPath (Join-Path $bridge 'package.json')) { Push-Location $bridge; npm install --silent; Pop-Location; Write-Host 'Đã cài.' }

Step 'Kiểm tra'
& (Join-Path $PSScriptRoot 'setup-check.ps1')
