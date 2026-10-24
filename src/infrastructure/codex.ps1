# AI backend (Codex CLI). Dot-sourced by run-images.ps1.
# Reads: $script:Config.Model, $script:Batch.Dir

# Run `codex exec` with a prompt and optional images. Returns the model's text reply.
function Invoke-AI([string]$PromptText, [string[]]$Images, [string]$ResultFile, [string]$Sandbox = 'read-only') {
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $attemptFile = if ($attempt -eq 1) { $ResultFile } else { "$ResultFile.attempt-$attempt.txt" }
        $commandArgs = @('exec', '--skip-git-repo-check', '-s', $Sandbox, '-C', $script:Batch.Dir, '-o', $attemptFile)
        if ($script:Config.Model) { $commandArgs += @('-m', $script:Config.Model) }
        foreach ($photo in $Images) { $commandArgs += @('-i', $photo) }
        $trace = "$attemptFile.console.log"
        $exitCode = & {
            $ErrorActionPreference = 'Continue'
            $PromptText | & codex @commandArgs - *> $trace
            $LASTEXITCODE
        }
        if ($exitCode -eq 0 -and (Test-Path -LiteralPath $attemptFile)) {
            $text = (Get-Content -LiteralPath $attemptFile -Raw -Encoding UTF8).Trim()
            if ($text) {
                if ($attemptFile -ne $ResultFile) { Copy-Item -LiteralPath $attemptFile -Destination $ResultFile -Force }
                # Console traces are only needed to diagnose failures.
                Remove-Item -LiteralPath $trace -Force -ErrorAction SilentlyContinue
                return $text
            }
        }
        $failure = if (Test-Path -LiteralPath $trace) { Get-Content -LiteralPath $trace -Raw } else { '' }
        # Never change the model, and never retry permanent auth/credit/input failures.
        $permanent = $failure -match '(?i)out of credits|insufficient_quota|invalid.api.key|unauthorized|authentication failed'
        $transient = $failure -match '(?i)Selected model is at capacity|rate.limit.exceeded|too many requests|HTTP\s*(429|502|503|504)|temporarily unavailable|server overloaded|connection reset'
        if ($permanent -or -not $transient -or $attempt -eq $maxAttempts) {
            $cause = if ($failure -match '(?i)out of credits|insufficient_quota|usage limit|quota exceeded') { 'QUOTA' }
                elseif ($failure -match '(?i)invalid.api.key|unauthorized|authentication failed') { 'AUTH' }
                elseif ($failure -match '(?i)connection reset|timed out|name resolution') { 'NETWORK' }
                elseif ($transient) { 'BUSY' } else { 'UNKNOWN' }
            throw "AI failed. Details: $trace [CAUSE:$cause]"
        }
        $delay = [int](3 * [Math]::Pow(2, $attempt - 1))
        if ($script:Config.ContainsKey('AiRetryDelaySeconds')) { $delay = [int]$script:Config.AiRetryDelaySeconds }
        Write-Host "  [RETRY] AI busy; attempt $($attempt + 1)/$maxAttempts in ${delay}s..." -ForegroundColor Yellow
        if ($delay -gt 0) { Start-Sleep -Seconds $delay }
    }
}
