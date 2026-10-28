# Read quota through the signed-in CLI; never inspect or print credential files.
function Get-QuotaMessages($Data) {
    $buckets = @()
    if ($Data.rateLimitsByLimitId) { $buckets = @($Data.rateLimitsByLimitId.PSObject.Properties | ForEach-Object Value | Where-Object { $_ }) }
    if (-not $buckets.Count -and $Data.rateLimits) { $buckets = @($Data.rateLimits) }
    foreach ($bucket in $buckets) {
        $label = if ($bucket.limitName) { ([string]$bucket.limitName -replace '[\r\n\t]', ' ').Trim() } elseif ($bucket.limitId -and $bucket.limitId -ne 'codex') { [string]$bucket.limitId } else { 'Codex' }
        if ($label.Length -gt 60) { $label = $label.Substring(0, 60) }
        foreach ($key in @('primary', 'secondary')) {
            $window = $bucket.$key
            if (-not $window -or $null -eq $window.usedPercent) { continue }
            $used = 0.0
            if (-not [double]::TryParse([string]$window.usedPercent, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$used) -or [double]::IsNaN($used) -or [double]::IsInfinity($used)) { continue }
            $remaining = [Math]::Round([Math]::Max(0.0, [Math]::Min(100.0, 100.0 - $used)), 1).ToString('0.#', [Globalization.CultureInfo]::InvariantCulture)
            $minutes = if ($window.windowDurationMins) { [int]$window.windowDurationMins } else { 0 }
            $duration = if ($minutes -gt 0 -and $minutes % 1440 -eq 0) { "$($minutes / 1440) ngày" }
                elseif ($minutes -gt 0 -and $minutes % 60 -eq 0) { "$($minutes / 60) giờ" }
                elseif ($minutes -gt 0) { "$minutes phút" }
                elseif ($key -eq 'primary') { 'kỳ hiện tại' } else { 'kỳ dài hạn' }
            $resetText = 'Chưa có giờ đặt lại.'
            if ($null -ne $window.resetsAt) {
                try {
                    $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$window.resetsAt)
                    $local = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($reset.UtcDateTime, 'SE Asia Standard Time')
                    $resetText = "Đặt lại $($local.ToString('HH:mm dd/MM')) (GMT+7)."
                } catch {}
            }
            "Hạn mức $label ($duration): còn $remaining%. $resetText Phạm vi do CLI cung cấp; chưa xác minh lượt tạo ảnh còn lại."
        }
    }
}

function Get-ChatGptQuota([string]$CliPath) {
    $unavailable = [pscustomobject]@{ Available = $false; Messages = @('Hạn mức Codex: chưa xác định, chưa lấy được dữ liệu. Không đồng nghĩa hết hạn mức. Vui lòng thử kiểm tra lại.') }
    if (-not $CliPath -or -not (Get-Command node -ErrorAction SilentlyContinue)) { return $unavailable }
    try {
        $helper = Join-Path $PSScriptRoot 'read-quota.cjs'
        $payload = & {
            $ErrorActionPreference = 'Continue'
            & node $helper $CliPath 2>$null | Out-String
        }
        $response = $payload | ConvertFrom-Json
        if (-not $response.available) { return $unavailable }
        $messages = @(Get-QuotaMessages $response.data)
        if (-not $messages.Count) { return $unavailable }
        return [pscustomobject]@{ Available = $true; Messages = $messages }
    } catch { return $unavailable }
}
