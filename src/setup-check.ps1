# Read-only readiness, sign-in and live quota checks; no AI turns are created.
param([switch]$AsJson)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$checks = New-Object Collections.Generic.List[object]
$checks.Add([pscustomobject]@{
    Ok = $PSVersionTable.PSVersion.Major -ge 5
    Message = $(if ($PSVersionTable.PSVersion.Major -ge 5) { 'Hệ thống: sẵn sàng.' } else { 'Hệ thống chưa được hỗ trợ.' })
    Action = 'Sử dụng Windows 10/11 và cài đặt theo setup.txt.'
})
$engine = Get-Command codex -ErrorAction SilentlyContinue
$checks.Add([pscustomobject]@{
    Ok = [bool]$engine
    Message = $(if ($engine) { 'Công cụ xử lý: đã cài đặt.' } else { 'Chưa cài công cụ xử lý.' })
    Action = 'Bấm Kiểm tra cấu hình rồi bấm Cài.'
})
$loggedIn = $false
$apiKey = $false
if ($engine) {
    try {
        $auth = & {
            # The CLI writes successful status to stderr on Windows PowerShell 5.1.
            $ErrorActionPreference = 'Continue'
            $text = & codex login status 2>&1 | Out-String
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = $text.Trim() }
        }
        $status = $auth.Text
        $loggedIn = $auth.ExitCode -eq 0 -and $status -match '(?i)logged in'
        $apiKey = $loggedIn -and $status -match '(?i)api key'
    } catch { $loggedIn = $false }
}
$checks.Add([pscustomobject]@{
    Ok = $loggedIn
    Message = $(if ($apiKey) { 'Tài khoản: đã cấu hình API, tính phí riêng.' } elseif ($loggedIn) { 'ChatGPT: đã đăng nhập.' } else { 'ChatGPT: chưa đăng nhập hoặc phiên đăng nhập đã hết hạn.' })
    Action = 'Bấm Đăng nhập Codex rồi đăng nhập ChatGPT trong trình duyệt.'
})
. (Join-Path $PSScriptRoot 'infrastructure/quota.ps1')
$quotaAvailable = $false
$quotaMessages = @()
if ($loggedIn) {
    if ($apiKey) {
        $quotaMessages = @('Hạn mức: tài khoản API tính phí riêng; app chưa hiển thị số dư API.')
    } else {
        $quota = Get-ChatGptQuota $engine.Source
        $quotaAvailable = $quota.Available
        $quotaMessages = @($quota.Messages)
    }
    foreach ($message in $quotaMessages) {
        $checks.Add([pscustomobject]@{ Ok = $true; Message = $message; Action = '' })
    }
}
$ready = @($checks | Where-Object { -not $_.Ok }).Count -eq 0
# The app's Kiểm tra cấu hình window shows these in order (app password first); each step only matters once the one before it is done.
# State: ok, fail, warn (works but unconfirmed) or wait (blocked by an earlier step). Action names the fix button.
$node = Get-Command node -ErrorAction SilentlyContinue
# The saved app password is tried against the server, so a changed password shows up here.
$driveFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'workspace/drive.json'
$driveState = 'fail'; $driveDetail = 'Chưa nhập; cần để tải ảnh lên Drive và dùng kho Drive.'
if (Test-Path -LiteralPath $driveFile) {
    try {
        $saved = Get-Content -LiteralPath $driveFile -Raw -Encoding UTF8 | ConvertFrom-Json
        Invoke-WebRequest -Uri (([string]$saved.apiUrl).TrimEnd('/') + '/api/app-check') -Headers @{ 'x-admin-key' = [string]$saved.adminKey } -UseBasicParsing -TimeoutSec 10 | Out-Null
        $driveState = 'ok'; $driveDetail = 'Đã đăng nhập; ảnh tạo xong tự tải lên Drive.'
    } catch {
        $code = 0; if ($_.Exception.Response) { try { $code = [int]$_.Exception.Response.StatusCode } catch {} }
        if ($code -in @(401, 403)) { $driveDetail = 'Mật khẩu đã đổi; bấm Đăng nhập để nhập lại.' }
        else { $driveState = 'warn'; $driveDetail = 'Chưa kiểm tra được (mất mạng); dùng mật khẩu đã lưu.' }
    }
}
# The main window shows what is left; here only when it resets, to keep the step short.
$quotaText = if ($quotaAvailable -and $quota.Resets) { "Đặt lại: $($quota.Resets)" } else { (@($quotaMessages) -join ' ').Trim() }
$steps = @(
    [pscustomobject]@{ Id = 'drive'; Title = 'Mật khẩu app'; State = $driveState; Detail = $driveDetail; Action = 'drive' }
    [pscustomobject]@{ Id = 'node'; Title = 'Node.js'; State = $(if ($node) { 'ok' } else { 'fail' }); Detail = $(if ($node) { 'Đã cài.' } else { 'Chưa cài. Cần để cài Codex.' }); Action = $(if ($node) { '' } else { 'install' }) }
    [pscustomobject]@{ Id = 'codex'; Title = 'Codex'; State = $(if ($engine) { 'ok' } else { 'fail' }); Detail = $(if ($engine) { 'Đã cài.' } else { 'Chưa cài công cụ tạo ảnh.' }); Action = $(if ($engine) { '' } else { 'install' }) }
    [pscustomobject]@{ Id = 'login'; Title = 'Đăng nhập ChatGPT'; State = $(if (-not $engine) { 'wait' } elseif ($loggedIn) { 'ok' } else { 'fail' })
        Detail = $(if (-not $engine) { 'Cài Codex trước.' } elseif ($apiKey) { 'Đã cấu hình API, tính phí riêng.' } elseif ($loggedIn) { 'Đã đăng nhập.' } else { 'Chưa đăng nhập hoặc phiên đã hết hạn.' })
        Action = $(if ($engine -and -not $loggedIn) { 'login' } else { '' }) }
    [pscustomobject]@{ Id = 'quota'; Title = 'Hạn mức sử dụng'; State = $(if (-not $loggedIn) { 'wait' } elseif ($apiKey -or $quotaAvailable) { 'ok' } else { 'warn' })
        Detail = $(if (-not $loggedIn) { 'Đăng nhập trước.' } else { $quotaText }); Action = '' }
)
$report = [pscustomobject]@{
    Ready = $ready
    QuotaAvailable = $quotaAvailable
    # The app turns its check button into this step: install, login or nothing left.
    NextAction = $(if (-not $engine) { 'install' } elseif (-not $loggedIn) { 'login' } else { '' })
    Checks = $checks.ToArray()
    Steps = $steps
    Summary = $(if (-not $ready) { 'Vui lòng xử lý các mục trên trước khi bắt đầu.' } elseif ($apiKey) { 'Đã kiểm tra cài đặt và tài khoản API.' } elseif ($quotaAvailable) { 'Đã kiểm tra đăng nhập và hạn mức Codex. Hạn mức tạo ảnh không được thống kê riêng.' } else { 'Đã kiểm tra cài đặt và đăng nhập. Chưa xác định được hạn mức còn lại.' })
}
if ($AsJson) { $report | ConvertTo-Json -Depth 5 }
else {
    Write-Output 'KIỂM TRA CHATGPT'
    foreach ($check in $report.Checks) {
        Write-Output $check.Message
        if (-not $check.Ok) { Write-Output $check.Action }
    }
    Write-Output $report.Summary
}
if (-not $ready) { exit 1 }
