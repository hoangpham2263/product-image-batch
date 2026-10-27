# AI backend (Codex CLI). Dot-sourced by run-images.ps1.
# Reads: $script:Config.Model, $script:Batch.Dir

function ConvertTo-CliArgument([string]$Value) {
    if ($Value -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Get-CodexLaunch {
    $path = (Get-Command codex -ErrorAction Stop).Source
    if ([IO.Path]::GetExtension($path) -eq '.exe') { return @{FileName=$path; Prefix=@()} }
    # npm's PowerShell/cmd shims are unnecessary: start its Node launcher directly.
    $launcher = Join-Path (Split-Path $path -Parent) 'node_modules/@openai/codex/bin/codex.js'
    if (-not (Test-Path -LiteralPath $launcher)) { throw 'Codex executable not found. Run setup to check the installation.' }
    return @{FileName=(Get-Command node.exe -ErrorAction Stop).Source; Prefix=@($launcher)}
}

# Isolate the CLI so its internal reconnect loop cannot block a worker indefinitely.
function Invoke-CodexProcess([string]$PromptText, [string[]]$CommandArgs, [string]$Trace,
    [int]$TimeoutSeconds, [int]$ReconnectSeconds = 60, [string]$CommandPath = '', [int]$ProgressSeconds = 30) {
    $launch = if ($CommandPath) { @{FileName=$CommandPath; Prefix=@()} } else { Get-CodexLaunch }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $launch.FileName
    $allArgs = @($launch.Prefix) + @($CommandArgs)
    $start.Arguments = (@($allArgs | ForEach-Object { ConvertTo-CliArgument $_ }) -join ' ')
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8; $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    $writer = [IO.StreamWriter]::new($Trace, $false, [Text.UTF8Encoding]::new($false)); $writer.AutoFlush = $true
    $watch = [Diagnostics.Stopwatch]::StartNew(); $reconnectAt = -1.0; $notified = $false; $nextProgress = $ProgressSeconds
    $cause = ''; $exitCode = -1; $started = $false; $stopConfirmed = $false
    try {
        [void]$process.Start(); $started = $true
        # Windows PowerShell's default stdin writer may use the system code page.
        # Write explicit UTF-8 bytes so Vietnamese feedback is preserved in every caller.
        $promptBytes = [Text.UTF8Encoding]::new($false).GetBytes($PromptText)
        $inputWrite = $process.StandardInput.BaseStream.WriteAsync($promptBytes, 0, $promptBytes.Length); $inputClosed = $false
        $readers = @($process.StandardOutput, $process.StandardError)
        $pending = @($readers[0].ReadLineAsync(), $readers[1].ReadLineAsync())
        while ($true) {
            if (-not $inputClosed -and $inputWrite.IsCompleted) {
                try {
                    $inputWrite.GetAwaiter().GetResult()
                    $process.StandardInput.Close()
                } catch [IO.IOException] {
                    # A CLI may exit/close stdin early; drain its diagnostic output and exit code.
                    $writer.WriteLine('CLI closed its input stream before the prompt was fully accepted.')
                }
                $inputClosed = $true
            }
            for ($i = 0; $i -lt 2; $i++) {
                # Drain only a bounded number of lines per poll so a noisy CLI cannot defeat the deadline.
                for ($n = 0; $n -lt 100 -and $null -ne $pending[$i] -and $pending[$i].IsCompleted; $n++) {
                    $line = $pending[$i].GetAwaiter().GetResult()
                    if ($null -eq $line) { $pending[$i] = $null; break }
                    $writer.WriteLine($line)
                    # Only CLI stream-status lines start the reconnect deadline. Tool
                    # source text and background MCP/analytics warnings are not a lost model stream.
                    if ($line -match '(?i)^(?:ERROR:\s*)?(?:Reconnecting\b|stream disconnected\b|connection reset\b|failed to connect\b|error sending request\b)') {
                        if (-not $notified) { Write-Host '  [AI-CONNECTION] Connection interrupted; waiting for recovery...' -ForegroundColor Yellow; $notified = $true }
                        if ($reconnectAt -lt 0) { $reconnectAt = $watch.Elapsed.TotalSeconds }
                    } elseif ($reconnectAt -ge 0 -and $line -match '^(assistant|thinking|tool\s|exec\s)') {
                        $reconnectAt = -1; $notified = $false
                        Write-Host '  [AI-RESUMED] Response stream resumed.' -ForegroundColor Cyan
                    }
                    $pending[$i] = $readers[$i].ReadLineAsync()
                }
            }
            if ($process.HasExited -and $null -eq $pending[0] -and $null -eq $pending[1]) { $exitCode = $process.ExitCode; break }
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $cause = 'AI_TIMEOUT'; break }
            if ($reconnectAt -ge 0 -and ($watch.Elapsed.TotalSeconds - $reconnectAt) -ge $ReconnectSeconds) { $cause = 'NETWORK'; break }
            if ($reconnectAt -lt 0 -and $ProgressSeconds -gt 0 -and $watch.Elapsed.TotalSeconds -ge $nextProgress) {
                Write-Host ("  [AI-WAIT] {0}/{1}s elapsed." -f [int]$watch.Elapsed.TotalSeconds, $TimeoutSeconds) -ForegroundColor DarkGray
                $nextProgress += $ProgressSeconds
            }
            Start-Sleep -Milliseconds 100
        }
        if ($cause) { $writer.WriteLine("Stopped local CLI: $cause after $([int]$watch.Elapsed.TotalSeconds)s.") }
    } finally {
        # Kill only this invocation and its descendants; retain the queue and diagnostic files.
        if ($started -and -not $process.HasExited) {
            & taskkill.exe /PID $process.Id /T /F *> $null
            $treeKilled = $LASTEXITCODE -eq 0
            $exited = $process.WaitForExit(5000)
            $stopConfirmed = $treeKilled -and $exited
        } elseif ($started -and -not $cause) {
            $stopConfirmed = $true
        }
        $writer.Dispose(); $process.Dispose(); $watch.Stop()
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Cause = $cause; StopConfirmed = $stopConfirmed }
}

# Run `codex exec` with a prompt and optional images. Returns the model's text reply.
function Invoke-AI([string]$PromptText, [string[]]$Images, [string]$ResultFile, [string]$Sandbox = 'read-only') {
    $isImage = $Sandbox -eq 'workspace-write'
    # Image retries are owned by Complete-ProductImage, which can first recover saved files.
    $maxAttempts = if ($isImage) { 1 } else { 3 }
    $timeout = if ($isImage) { 480 } else { 180 }
    $timeoutKey = if ($isImage) { 'ImageTimeoutSeconds' } else { 'AiTimeoutSeconds' }
    if ($script:Config.ContainsKey($timeoutKey)) { $timeout = [Math]::Max(1, [int]$script:Config[$timeoutKey]) }
    $reconnectTimeout = 60
    if ($script:Config.ContainsKey('AiReconnectTimeoutSeconds')) { $reconnectTimeout = [Math]::Max(1, [int]$script:Config.AiReconnectTimeoutSeconds) }
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $attemptFile = if ($attempt -eq 1) { $ResultFile } else { "$ResultFile.attempt-$attempt.txt" }
        $commandArgs = @('exec', '--skip-git-repo-check', '-s', $Sandbox, '-C', $script:Batch.Dir, '-o', $attemptFile)
        if ($script:Config.Model) { $commandArgs += @('-m', $script:Config.Model) }
        foreach ($photo in $Images) { $commandArgs += @('-i', $photo) }
        $trace = "$attemptFile.console.log"
        $execution = Invoke-CodexProcess $PromptText $commandArgs $trace $timeout $reconnectTimeout
        if ($execution.ExitCode -eq 0 -and (Test-Path -LiteralPath $attemptFile)) {
            $text = (Get-Content -LiteralPath $attemptFile -Raw -Encoding UTF8).Trim()
            if ($text) {
                if ($attemptFile -ne $ResultFile) { Copy-Item -LiteralPath $attemptFile -Destination $ResultFile -Force }
                # Console traces are only needed to diagnose failures.
                Remove-Item -LiteralPath $trace -Force -ErrorAction SilentlyContinue
                return $text
            }
        }
        $failure = if (Test-Path -LiteralPath $trace) { Get-Content -LiteralPath $trace -Raw } else { '' }
        if ($execution.Cause -and -not $execution.StopConfirmed) { throw "AI failed; previous process termination is unconfirmed. Details: $trace [CAUSE:PROCESS_ACTIVE]" }
        # Never change the model, and never retry permanent auth/credit/input failures.
        $permanent = $failure -match '(?i)out of credits|insufficient_quota|invalid.api.key|unauthorized|authentication failed'
        $transient = $execution.Cause -in @('AI_TIMEOUT','NETWORK') -or $failure -match '(?i)Selected model is at capacity|rate.limit.exceeded|too many requests|HTTP\s*(429|502|503|504)|temporarily unavailable|server overloaded|connection reset|Reconnecting|stream disconnected'
        if ($permanent -or -not $transient -or $attempt -eq $maxAttempts) {
            $cause = if ($execution.Cause) { $execution.Cause }
                elseif ($failure -match '(?i)out of credits|insufficient_quota|usage limit|quota exceeded') { 'QUOTA' }
                elseif ($failure -match '(?i)invalid.api.key|unauthorized|authentication failed') { 'AUTH' }
                elseif ($failure -match '(?i)connection reset|timed out|name resolution|Reconnecting|stream disconnected|Transport channel closed') { 'NETWORK' }
                elseif ($transient) { 'BUSY' } else { 'UNKNOWN' }
            throw "AI failed. Details: $trace [CAUSE:$cause]"
        }
        $delay = [int](3 * [Math]::Pow(2, $attempt - 1))
        if ($script:Config.ContainsKey('AiRetryDelaySeconds')) { $delay = [int]$script:Config.AiRetryDelaySeconds }
        Write-Host "  [RETRY] AI busy; attempt $($attempt + 1)/$maxAttempts in ${delay}s..." -ForegroundColor Yellow
        if ($delay -gt 0) { Start-Sleep -Seconds $delay }
    }
}
