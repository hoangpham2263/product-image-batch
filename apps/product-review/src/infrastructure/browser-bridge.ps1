# Image generation through the signed-in ChatGPT / Google Flow tab (bridge/ + extension/).
$script:BridgeUrl = 'http://127.0.0.1:8765'

function Test-ImageBridge {
    try { return [bool](Invoke-RestMethod -Uri "$script:BridgeUrl/status" -TimeoutSec 3).extension } catch { return $null }
}

# Start the local bridge when it is not running, then wait for the extension to connect.
function Start-ImageBridge([string]$ProjectRoot) {
    $state = Test-ImageBridge
    if ($null -eq $state) {
        $server = Join-Path $ProjectRoot 'bridge/server.mjs'
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'bridge/node_modules/ws'))) { throw 'Bridge chưa cài. Bấm Kiểm tra cấu hình → Cài trong app, hoặc chạy npm install trong bridge/.' }
        if ($script:OnWindows) { Start-Process node -ArgumentList ('"' + $server + '"') -WindowStyle Hidden | Out-Null }
        else { Start-Process node -ArgumentList $server | Out-Null }
    }
    for ($i = 0; $i -lt 40; $i++) {
        if (Test-ImageBridge) { return }
        Start-Sleep -Milliseconds 750
    }
    throw '[CAUSE:BRIDGE] Extension product-review-bridge chưa kết nối. Mở Chrome có cài extension và giữ tab ChatGPT/Flow đã đăng nhập.'
}

# Browser backends cannot write files themselves; drop the file-delivery lines meant for Codex.
function ConvertTo-BrowserPrompt([string]$Prompt) {
    $lines = $Prompt -split "`r?`n" | Where-Object { $_ -notmatch '^(Save a new PNG at this exact path|Do not modify any input file|End your reply with a line: BRAND)' }
    return ($lines -join "`n").Trim()
}

function Invoke-BrowserImage([string]$Platform, [string]$Prompt, [string[]]$Images, [string]$Output, [int]$TimeoutSec = 600) {
    $body = @{ platform = $Platform; prompt = (ConvertTo-BrowserPrompt $Prompt); images = @($Images); output = $Output; timeoutSec = $TimeoutSec } | ConvertTo-Json -Depth 4
    try {
        $result = Invoke-RestMethod -Uri "$script:BridgeUrl/generate" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec ($TimeoutSec + 120)
    } catch {
        $detail = $_.ErrorDetails.Message
        $cause = if ($detail -match 'Hết thời gian|timeout') { 'AI_TIMEOUT' } elseif ($detail -match 'đăng nhập|Extension') { 'BRIDGE' } else { 'BUSY' }
        throw "[CAUSE:$cause] $Platform không tạo được ảnh. $detail"
    }
    ConvertTo-PngFile $Output
    return $result
}
