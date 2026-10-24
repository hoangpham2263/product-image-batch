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
    Action = 'Làm theo phần cài đặt trong setup.txt, sau đó mở lại ứng dụng.'
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
    Action = 'Đăng nhập ChatGPT qua Codex theo setup.txt rồi kiểm tra lại.'
})
. (Join-Path $PSScriptRoot 'infrastructure/quota.ps1')
$quotaAvailable = $false
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
$report = [pscustomobject]@{
    Ready = $ready
    QuotaAvailable = $quotaAvailable
    Checks = $checks.ToArray()
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
