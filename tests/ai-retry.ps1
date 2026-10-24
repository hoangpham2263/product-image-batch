. (Join-Path $PSScriptRoot 'helpers.ps1')
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/infrastructure/codex.ps1')
$testDir = Join-Path $TestWorkspaceRoot ('ai-retry-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
$script:Config = @{ Model = 'test-model'; AiRetryDelaySeconds = 0 }
$script:Batch = @{ Dir = $testDir }
function codex {
    $CliArgs = @($args)
    $script:LastCliArgs = $CliArgs
    $input | Out-Null
    $script:Calls++
    if ($CliArgs[([Array]::IndexOf($CliArgs, '-m') + 1)] -ne 'test-model') { throw 'Model changed on retry.' }
    if ($script:Scenario -eq 'auth') { 'ERROR: authentication failed'; $global:LASTEXITCODE = 1; return }
    if ($script:Scenario -eq 'always-busy' -or $script:Calls -eq 1) {
        'ERROR: Selected model is at capacity. Please try a different model.'
        $global:LASTEXITCODE = 1; return
    }
    $output = $CliArgs[([Array]::IndexOf($CliArgs, '-o') + 1)]
    'FIT' | Set-Content -LiteralPath $output -Encoding UTF8
    $global:LASTEXITCODE = 0
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
    Write-Host 'PASS: capacity retry recovers, permanent errors stop, retries are bounded, model is preserved.' -ForegroundColor Green
} finally {
    $resolved = [IO.Path]::GetFullPath($testDir)
    $allowed = [IO.Path]::GetFullPath($TestWorkspaceRoot).TrimEnd('\') + '\'
    if ($resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'ai-retry-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
