. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/infrastructure/codex.ps1')
$testDir = Join-Path $TestWorkspaceRoot ('ai-retry-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
$script:Config = @{ Model = 'test-model'; AiRetryDelaySeconds = 0 }
$script:Batch = @{ Dir = $testDir }
function Invoke-CodexProcess($PromptText, $CommandArgs, $Trace, $TimeoutSeconds, $ReconnectSeconds) {
    $CliArgs = @($CommandArgs)
    $script:LastCliArgs = $CliArgs
    $script:Calls++
    if ($CliArgs[([Array]::IndexOf($CliArgs, '-m') + 1)] -ne 'test-model') { throw 'Model changed on retry.' }
    if ($script:Scenario -eq 'timeout') { 'Deadline reached' | Set-Content $Trace; return [pscustomobject]@{ExitCode=-1;Cause='AI_TIMEOUT';StopConfirmed=$true} }
    if ($script:Scenario -eq 'network') { 'Connection interrupted' | Set-Content $Trace; return [pscustomobject]@{ExitCode=-1;Cause='NETWORK';StopConfirmed=$true} }
    if ($script:Scenario -eq 'active') { 'Cannot stop process' | Set-Content $Trace; return [pscustomobject]@{ExitCode=-1;Cause='AI_TIMEOUT';StopConfirmed=$false} }
    if ($script:Scenario -eq 'auth') { 'ERROR: authentication failed' | Set-Content $Trace; return [pscustomobject]@{ExitCode=1;Cause=''} }
    if ($script:Scenario -eq 'always-busy' -or $script:Calls -eq 1) {
        'ERROR: Selected model is at capacity. Please try a different model.' | Set-Content $Trace
        return [pscustomobject]@{ExitCode=1;Cause=''}
    }
    $output = $CliArgs[([Array]::IndexOf($CliArgs, '-o') + 1)]
    'FIT' | Set-Content -LiteralPath $output -Encoding UTF8
    '' | Set-Content $Trace
    return [pscustomobject]@{ExitCode=0;Cause=''}
}
try {
    $script:Scenario = 'recover'; $script:Calls = 0
    $result = Join-Path $testDir 'recover.txt'
    $reply = Invoke-AI 'Check' @() $result
    if ($reply -ne 'FIT' -or $script:Calls -ne 2 -or (Get-Content $result -Raw).Trim() -ne 'FIT') { throw 'Capacity retry did not recover.' }
    foreach ($scenario in @('auth', 'always-busy')) {
        $script:Scenario = $scenario; $script:Calls = 0; $failed = $false
        try { Invoke-AI 'Check' @() (Join-Path $testDir "$scenario.txt") | Out-Null } catch {
            if ($_.Exception.Message -notlike 'AI failed. Details:*') { throw }
            $failed = $true
        }
        $expected = if ($scenario -eq 'auth') { 1 } else { 3 }
        if (-not $failed -or $script:Calls -ne $expected) { throw "Incorrect retry count for $scenario" }
    }
    foreach ($scenario in @('timeout', 'network')) {
        $script:Scenario=$scenario; $script:Calls=0; $failed=$false
        try { Invoke-AI 'Check' @() (Join-Path $testDir "$scenario.txt") | Out-Null } catch {
            $cause = if($scenario -eq 'timeout'){'AI_TIMEOUT'}else{'NETWORK'}
            if($_.Exception.Message -notmatch ([regex]::Escape("[CAUSE:$cause]"))){throw}
            $failed=$true
        }
        if(-not $failed -or $script:Calls -ne 3){throw 'Text timeout/network retries were not bounded to three.'}
    }
    $script:Scenario='always-busy'; $script:Calls=0; $failed=$false
    try { Invoke-AI 'Generate' @() (Join-Path $testDir 'image.txt') 'workspace-write' | Out-Null } catch { $failed=$true }
    if(-not $failed -or $script:Calls -ne 1){throw 'Image request must not be submitted repeatedly.'}
    $script:Scenario='active';$script:Calls=0;$failed=$false
    try{Invoke-AI 'Generate' @() (Join-Path $testDir 'active.txt') 'workspace-write'|Out-Null}catch{$failed=$_.Exception.Message -match '\[CAUSE:PROCESS_ACTIVE\]'}
    if(-not $failed -or $script:Calls -ne 1){throw 'Unconfirmed process termination allowed a duplicate request.'}
    Write-Host 'PASS: capacity retry recovers, permanent errors stop, retries are bounded, model is preserved.' -ForegroundColor Green
} finally {
    $resolved = [IO.Path]::GetFullPath($testDir)
    $allowed = [IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\') + '\'
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'ai-retry-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
