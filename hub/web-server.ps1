# Windows: the web tools (tool.json "web") served from this install, as hub/picker.mjs serves them on macOS, so they get
# the same Cấu hình and Cập nhật buttons (hub/assets/hub.js) and the same /api. Started hidden by the menu
# (hub/launch.ps1) the first time a web tool opens; one per install, on Get-HubWebPort. Plain TCP, so no admin rights.
#   GET  /api/root                       { root, hub, version }
#   POST /api/setup, /api/setup-step     the Cấu hình steps (setup-check.ps1) / Cài or Đăng nhập in their own window
#   GET|POST /api/config/ai              Model AI;  GET|POST|DELETE /api/config/drive   the app password
#   GET  /api/update-check, POST /api/update   a newer release / install it, then start again on the new files
#   /apps/<id>/..., /hub/<asset>, /icon/<id>   files
param([int]$Port, [switch]$WaitPort)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'update.ps1') -NoRun
. (Join-Path $PSScriptRoot 'setup/ai-settings.ps1')
. (Join-Path $PSScriptRoot 'setup/drive.ps1')
if (-not $Port) { $Port = Get-HubWebPort $root }
$workspace = Join-Path $root 'workspace'
# PowerShell for child scripts: Windows PowerShell as the menu runs it, else pwsh.
$hostExe = if ($PSVersionTable.PSEdition -eq 'Desktop') { Join-Path $PSHOME 'powershell.exe' } else { (Get-Command pwsh).Source }
$onWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
$types = @{ '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.json' = 'application/json'; '.mp4' = 'video/mp4'; '.webp' = 'image/webp'; '.jpg' = 'image/jpeg' }

function Reply([int]$Status, [string]$Type, [byte[]]$Bytes) { @{ Status = $Status; Type = $Type; Bytes = $Bytes } }
function ReplyJson($Data, [int]$Status = 200) { Reply $Status 'application/json' ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Data -Depth 8 -Compress))) }
function ReplyFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return Reply 404 'text/plain' @() }
    $type = $types[[IO.Path]::GetExtension($Path).ToLowerInvariant()]
    Reply 200 $(if ($type) { $type } else { 'application/octet-stream' }) ([IO.File]::ReadAllBytes($Path))
}
# A PowerShell script of the hub in a process of its own; its JSON output, written as UTF-8.
function Invoke-HubScript([string]$Script, [string[]]$Arguments) {
    $out = Join-Path ([IO.Path]::GetTempPath()) ("tools-hub-web-$PID-" + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        $p = @{ FilePath = $hostExe; ArgumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $Script + '"')) + $Arguments; Wait = $true; RedirectStandardOutput = $out }
        if ($onWindows) { $p.WindowStyle = 'Hidden' } else { $p.NoNewWindow = $true }
        Start-Process @p
        return Get-Content -LiteralPath $out -Raw -Encoding UTF8 | ConvertFrom-Json
    } finally { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
}

function Invoke-Route([string]$Method, [string]$Path, [string]$Body) {
    $data = if ($Body) { try { $Body | ConvertFrom-Json } catch { $null } }
    $parts = @($Path.Split('/') | ForEach-Object { [Uri]::UnescapeDataString($_) })
    switch ($Path) {
        '/api/root' { return ReplyJson ([ordered]@{ root = $root; hub = $true; version = (Get-InstalledVersion $root) }) }
        '/api/setup' { try { return ReplyJson (Invoke-HubScript (Join-Path $PSScriptRoot 'setup/setup-check.ps1') @('-AsJson')) } catch { return ReplyJson @{ error = 'setup' } 500 } }
        '/api/setup-step' {
            # Cài and Đăng nhập show their own window (progress, the sign-in link); the page waits for it to close.
            if ($data.step -eq 'install') { Start-Process $hostExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot 'setup/setup-install.ps1') + '"')) -Wait }
            elseif ($data.step -eq 'login') { Start-Process cmd.exe -ArgumentList @('/c', 'codex login') -Wait }
            else { return ReplyJson @{ error = 'Bước không hợp lệ.' } 400 }
            if ($onWindows) { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }
            return ReplyJson @{ ok = $true }
        }
        '/api/config/ai' {
            try {
                if ($Method -eq 'POST') { Set-AiSettings $root ([string]$data.model) ([string]$data.effort); return ReplyJson @{ ok = $true } }
                return ReplyJson ([ordered]@{ settings = (Get-AiSettings $root); models = @(Get-AiModels) })
            } catch { return ReplyJson @{ error = $_.Exception.Message } 400 }
        }
        '/api/config/drive' {
            try {
                if ($Method -eq 'POST') { Connect-DriveAccount $workspace ([string]$data.password) }
                elseif ($Method -eq 'DELETE') { Disconnect-DriveAccount $workspace }
                return ReplyJson @{ drive = (Test-Path -LiteralPath (Get-SharedConfigPath $workspace 'drive.json')) }
            } catch { return ReplyJson @{ error = $_.Exception.Message } 400 }
        }
        '/api/update-check' { try { return ReplyJson ([ordered]@{ current = (Get-InstalledVersion $root); next = (Get-AppUpdate $root) }) } catch { return ReplyJson @{} 502 } }
        '/api/update' {
            if ($Method -ne 'POST') { break }
            try { Update-App $root; $script:Restart = $true; return ReplyJson @{ ok = $true } } catch { return ReplyJson @{ ok = $false } 500 }
        }
    }
    # Shared files: /hub/<name>, or /hub/assets/<name> as web tools link them (../../../hub/assets/<name>).
    if ($parts[1] -eq 'hub' -and $parts[-1] -in @('icon.svg', 'tool.css', 'hub.js')) { return ReplyFile (Join-Path $PSScriptRoot "assets/$($parts[-1])") }
    $tool = @(Get-HubTools $root | Where-Object { $_.id -eq $parts[2] })[0]
    if ($tool -and $parts[1] -eq 'icon') { return ReplyFile (Join-Path $tool.Root $(if ($tool.icon) { $tool.icon } else { 'icon.svg' })) }
    if ($tool -and $parts[1] -eq 'apps' -and $parts.Count -gt 3) {
        $base = [IO.Path]::GetFullPath($tool.Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $file = [IO.Path]::GetFullPath((Join-Path $tool.Root ($parts[3..($parts.Count - 1)] -join '/')))
        if ($file.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { return ReplyFile $file }
    }
    return Reply 404 'text/plain' @()
}

# One request: the head up to the blank line, then Content-Length bytes of body; the reply closes the connection.
function Read-Request([Net.Sockets.NetworkStream]$Stream) {
    $latin = [Text.Encoding]::GetEncoding(28591)
    $buffer = New-Object IO.MemoryStream; $chunk = New-Object byte[] 8192; $headEnd = -1
    while ($headEnd -lt 0) {
        $n = $Stream.Read($chunk, 0, $chunk.Length); if ($n -le 0) { return $null }
        $buffer.Write($chunk, 0, $n)
        $headEnd = $latin.GetString($buffer.ToArray()).IndexOf("`r`n`r`n")
        if ($buffer.Length -gt 65536 -and $headEnd -lt 0) { return $null }
    }
    $all = $buffer.ToArray(); $head = $latin.GetString($all, 0, $headEnd).Split("`n")
    $length = 0; foreach ($line in $head) { if ($line -match '^(?i)content-length:\s*(\d+)') { $length = [int]$Matches[1] } }
    $body = New-Object IO.MemoryStream; $start = $headEnd + 4
    if ($all.Length -gt $start) { $body.Write($all, $start, $all.Length - $start) }
    while ($body.Length -lt $length) { $n = $Stream.Read($chunk, 0, [Math]::Min($chunk.Length, $length - $body.Length)); if ($n -le 0) { break }; $body.Write($chunk, 0, $n) }
    $requestLine = $head[0].Trim().Split(' ')
    return @{ Method = $requestLine[0]; Path = ($requestLine[1] -split '\?')[0]; Body = [Text.Encoding]::UTF8.GetString($body.ToArray()) }
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
for ($attempt = 0; ; $attempt++) {
    try { $listener.Start(); break }
    catch {
        # Already running for this install: nothing to do. Restarting after an update: wait for the old one to let go.
        if (-not $WaitPort -or $attempt -ge 50) { exit 0 }
        Start-Sleep -Milliseconds 200
    }
}
$script:Restart = $false
try {
    while (-not $script:Restart) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream(); $stream.ReadTimeout = 15000
            $request = Read-Request $stream
            if (-not $request) { continue }
            try { $reply = Invoke-Route $request.Method $request.Path $request.Body } catch { $reply = Reply 500 'text/plain' ([Text.Encoding]::UTF8.GetBytes($_.Exception.Message)) }
            $reason = @{ 200 = 'OK'; 400 = 'Bad Request'; 404 = 'Not Found'; 500 = 'Internal Server Error'; 502 = 'Bad Gateway' }[$reply.Status]
            $head = "HTTP/1.1 $($reply.Status) $reason`r`nContent-Type: $($reply.Type)`r`nContent-Length: $($reply.Bytes.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
            $headBytes = [Text.Encoding]::ASCII.GetBytes($head)
            $stream.Write($headBytes, 0, $headBytes.Length)
            if ($reply.Bytes.Length) { $stream.Write($reply.Bytes, 0, $reply.Bytes.Length) }
            $stream.Flush()
        } catch { Write-Verbose $_ } finally { $client.Close() }
    }
} finally { $listener.Stop() }
# Updated: a fresh server on the new files takes the port over.
Start-Process $hostExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + (Join-Path $PSScriptRoot 'web-server.ps1') + '"'), '-Port', $Port, '-WaitPort')
